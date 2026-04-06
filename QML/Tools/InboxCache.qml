// InboxCache.qml - Disk-backed cache for inbox messages, authors, and avatars
//
// Stores a single JSON file (messages + author data + avatar map) and
// individual avatar image files under a configurable XDG-compatible cache dir.
// All writes are debounced so rapid updates are batched into one disk flush.

import QtQuick
import Quickshell.Io

Item {
    id: cache
    visible: false

    // -- Configuration --------------------------------------------------------
    property string cacheDir: ""
    property int cacheTtlMinutes: Constants.defaultCacheTtlMinutes

    // -- Exposed cached state -------------------------------------------------
    property var cachedMessages: []
    property var cachedAuthorsByThread: ({})
    property var cachedAuthorFetchedAt: ({})
    property var avatarLocalPaths: ({})     // login -> "file:///abs/path.png"
    property real cachedTimestamp: 0
    property bool initialized: false

    signal cacheReady()
    signal avatarDownloaded(string login, string localUrl)

    // -- FileView for the JSON cache file -------------------------------------
    FileView {
        id: cacheFileView
        path: cache.cacheDir ? (cache.cacheDir + "/" + Constants.cacheFileName) : ""
        preload: false
        blockLoading: false
        atomicWrites: true
    }

    Connections {
        target: cacheFileView
        function onLoadFailed(error) {
            // Only used if FileView is ever reloaded elsewhere
            console.warn("[GitHubInbox] FileView load failed:", error)
        }
    }

    // -- Save debounce timer --------------------------------------------------
    Timer {
        id: saveDebounce
        interval: Constants.cacheSaveDebounceMs
        onTriggered: cache._writeToDisk()
    }

    // -- Avatar download queue ------------------------------------------------
    readonly property bool isDownloadingAvatars: _avatarBusy || _avatarQueue.length > 0
    property var _avatarQueue: []
    property bool _avatarBusy: false
    property bool _initializing: false
    property var _pendingAvatarValidation: []

    Component {
        id: initDirComponent
        Process {
            property bool _done: false
            stdout: SplitParser { onRead: function(line) {} }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                if (!_done) {
                    _done = true
                    cache._onDirReady(exitCode === 0)
                }
                destroy()
            }
        }
    }

    Component {
        id: readCacheComponent
        Process {
            property var _lines: []
            stdout: SplitParser {
                onRead: function(line) { _lines.push(line) }
            }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                if (exitCode === 0 && _lines.length > 0)
                    cache._onCacheFileRead(_lines.join("\n"))
                else
                    cache._onCacheFileReadFailed()
                destroy()
            }
        }
    }

    Component {
        id: resolveDirComponent
        Process {
            property string _captured: ""
            stdout: SplitParser {
                onRead: function(line) { _captured = line.trim() }
            }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                cache._onDirResolved(exitCode === 0 ? _captured : "")
                destroy()
            }
        }
    }

    Component {
        id: avatarDlComponent
        Process {
            property string login: ""
            property string localPath: ""
            property string remoteUrl: ""
            stdout: SplitParser { onRead: function(line) {} }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                if (exitCode === 0 && login)
                    cache._onAvatarDlDone(login, localPath, remoteUrl)
                cache._avatarBusy = false
                cache._processAvatarQueue()
                destroy()
            }
        }
    }

    Component {
        id: clearCacheComponent
        Process {
            stdout: SplitParser { onRead: function(line) {} }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) { destroy() }
        }
    }

    Component {
        id: avatarValidateComponent
        Process {
            property string _output: ""
            stdout: SplitParser {
                onRead: function(line) { _output = (_output ? _output + "\n" : "") + line }
            }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                cache._onAvatarValidationDone(_output)
                destroy()
            }
        }
    }

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper (standalone, no Widget dependency) --------------
    function _perfLog(label) {
        if (!Constants.debugPerformanceLogging) return
        console.warn("[GitHubInbox PERF] InboxCache: " + label)
    }

    function initialize() {
        if (_initializing || initialized)
            return
        _initializing = true
        _perfLog("initialize — start")

        if (cacheDir) {
            _createDirs()
            return
        }
        // Determine default cache dir from environment
        var proc = resolveDirComponent.createObject(cache)
        proc.command = [
            "sh", "-c",
            "echo \"${XDG_CACHE_HOME:-$HOME/.cache}/" + Constants.cacheSubdirectory + "\""
        ]
        proc.running = true
    }

    function isFresh() {
        if (cachedTimestamp === 0)
            return false
        return (Date.now() - cachedTimestamp) < cacheTtlMinutes * 60 * 1000
    }

    // -- Inbox Messages -------------------------------------------------------

    function updateMessages(items) {
        cachedMessages = items || []
        cachedTimestamp = Date.now()
        _queueSave()
    }

    // -- Authors --------------------------------------------------------------

    function updateAuthors(threadId, authors) {
        var next = _cloneMap(cachedAuthorsByThread)
        next[threadId] = authors || []
        cachedAuthorsByThread = next
        _queueSave()
    }

    function bulkUpdateAuthors(authorsMap) {
        cachedAuthorsByThread = authorsMap || ({})
        _queueSave()
    }

    function hasAuthors(threadId) {
        var entry = cachedAuthorsByThread[threadId]
        return entry && entry.length > 0
    }

    function getCachedAuthors(threadId) {
        return cachedAuthorsByThread[threadId] || []
    }

    function updateAuthorFetchedAt(threadId, updatedAt) {
        var next = _cloneMap(cachedAuthorFetchedAt)
        next[threadId] = updatedAt || ""
        cachedAuthorFetchedAt = next
        // authorFetchedAt changes piggyback on the next debounced save
    }

    function getAuthorFetchedAt(threadId) {
        return cachedAuthorFetchedAt[threadId] || ""
    }

    // -- Avatar resolution ----------------------------------------------------

    function hasLocalAvatar(login) {
        return avatarLocalPaths.hasOwnProperty(login)
    }

    function resolveAvatarUrl(remoteUrl, login) {
        if (!login || !remoteUrl)
            return remoteUrl || ""
        return avatarLocalPaths[login] || remoteUrl
    }

    function queueAvatarDownload(login, remoteUrl) {
        if (!cacheDir || !login || !remoteUrl)
            return
        if (avatarLocalPaths.hasOwnProperty(login))
            return

        for (var i = 0; i < _avatarQueue.length; i++) {
            if (_avatarQueue[i].login === login)
                return
        }

        var nextQueue = _avatarQueue.slice(0)
        nextQueue.push({ login: login, remoteUrl: remoteUrl })
        _avatarQueue = nextQueue
        _processAvatarQueue()
    }

    function batchQueueAvatarDownloads(items) {
        if (!cacheDir || !items || items.length === 0)
            return

        var existingLogins = {}
        for (var qi = 0; qi < _avatarQueue.length; qi++)
            existingLogins[_avatarQueue[qi].login] = true

        var toAdd = []
        for (var i = 0; i < items.length; i++) {
            var login = items[i].login
            var remoteUrl = items[i].remoteUrl
            if (!login || !remoteUrl)
                continue
            if (avatarLocalPaths.hasOwnProperty(login))
                continue
            if (existingLogins[login])
                continue
            existingLogins[login] = true
            toAdd.push({ login: login, remoteUrl: remoteUrl })
        }

        if (toAdd.length === 0)
            return

        var nextQueue = _avatarQueue.slice(0)
        for (var j = 0; j < toAdd.length; j++)
            nextQueue.push(toAdd[j])
        _avatarQueue = nextQueue
        _processAvatarQueue()
    }

    // -- Pruning --------------------------------------------------------------

    function pruneToThreads(keepIds) {
        var keep = {}
        for (var i = 0; i < keepIds.length; i++)
            keep[keepIds[i]] = true

        var nextAuthors = {}
        for (var tid in cachedAuthorsByThread) {
            if (keep[tid])
                nextAuthors[tid] = cachedAuthorsByThread[tid]
        }
        cachedAuthorsByThread = nextAuthors

        var nextFetchedAt = {}
        for (var ftid in cachedAuthorFetchedAt) {
            if (keep[ftid])
                nextFetchedAt[ftid] = cachedAuthorFetchedAt[ftid]
        }
        cachedAuthorFetchedAt = nextFetchedAt

        _queueSave()
    }

    // -- Clear ----------------------------------------------------------------

    function clearCache() {
        cachedMessages = []
        cachedAuthorsByThread = ({})
        cachedAuthorFetchedAt = ({})
        avatarLocalPaths = ({})
        cachedTimestamp = 0
        _avatarQueue = []

        if (cacheDir) {
            var proc = clearCacheComponent.createObject(cache)
            proc.command = [
                "sh", "-c",
                "rm -f " + _shellQuote(cacheDir + "/" + Constants.cacheFileName)
                + " && rm -rf " + _shellQuote(cacheDir + "/" + Constants.cacheAvatarsSubdirectory)
                + " && mkdir -p " + _shellQuote(cacheDir + "/" + Constants.cacheAvatarsSubdirectory)
            ]
            proc.running = true
        }
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    function _onDirResolved(resolvedPath) {
        _perfLog("_onDirResolved — path='" + (resolvedPath || "(empty)") + "'")
        if (!resolvedPath) {
            console.warn("[GitHubInbox] Could not resolve cache directory, using fallback")
            resolvedPath = Constants.cacheFallbackDirPath
        }
        cacheDir = resolvedPath
        _perfLog("_onDirResolved — cacheDir set, FileView.path='" + cacheFileView.path + "'")
        _createDirs()
    }

    function _createDirs() {
        _perfLog("_createDirs — spawning mkdir -p")
        var proc = initDirComponent.createObject(cache)
        proc.command = ["mkdir", "-p", cacheDir + "/" + Constants.cacheAvatarsSubdirectory]
        proc.running = true
    }

    function _onDirReady(success) {
        _perfLog("_onDirReady — success=" + success)
        if (!success) {
            console.warn("[GitHubInbox] Failed to create cache directory:", cacheDir)
            initialized = true
            cacheReady()
            return
        }

        // Read existing cache file via Process (FileView.reload is unreliable)
        var cachePath = cacheFileView.path || (cacheDir + "/" + Constants.cacheFileName)
        _perfLog("_onDirReady — reading cache via cat: '" + cachePath + "'")
        var proc = readCacheComponent.createObject(cache)
        proc.command = ["cat", cachePath]
        proc.running = true
    }

    function _onCacheFileRead(text) {
        _perfLog("_onCacheFileRead — start (JSON.parse), len=" + text.length)
        var t0 = Date.now()
        var data
        try {
            data = JSON.parse(text || "{}")
        } catch (e) {
            data = {}
        }
        _perfLog("_onCacheFileRead — JSON.parse done in " + (Date.now() - t0) + "ms")

        if ((data.version || 0) !== Constants.cacheFormatVersion)
            data = {}

        cachedMessages = data.notifications || []
        cachedAuthorsByThread = data.authorsByThread || ({})
        cachedAuthorFetchedAt = data.authorFetchedAt || ({})
        cachedTimestamp = data.lastFetched || 0

        // Rebuild avatar local path map, validating files still exist on disk
        var avatarMap = data.avatarMap || ({})
        var paths = {}
        var missingAvatars = []
        for (var login in avatarMap) {
            var localFile = avatarMap[login].localFile || ""
            if (localFile) {
                var fullPath = cacheDir + "/" + Constants.cacheAvatarsSubdirectory + "/" + localFile
                paths[login] = "file://" + fullPath
            }
        }
        avatarLocalPaths = paths

        // Schedule validation of avatar files on disk (runs after init completes)
        _pendingAvatarValidation = Object.keys(paths)
        if (_pendingAvatarValidation.length > 0)
            Qt.callLater(_validateAvatarFiles)

        _perfLog("_onCacheFileRead — end, msgs=" + cachedMessages.length + " avatars=" + Object.keys(paths).length)
        initialized = true
        cacheReady()
    }

    function _onCacheFileReadFailed() {
        _perfLog("_onCacheFileReadFailed — file does not exist or is empty (first run)")
        initialized = true
        cacheReady()
    }

    function _queueSave() {
        saveDebounce.restart()
    }

    function _writeToDisk() {
        if (!cacheDir || !initialized)
            return

        var avatarMap = {}
        for (var login in avatarLocalPaths)
            avatarMap[login] = { localFile: login + ".png" }

        var payload = {
            version: Constants.cacheFormatVersion,
            lastFetched: cachedTimestamp,
            notifications: cachedMessages,
            authorsByThread: cachedAuthorsByThread,
            authorFetchedAt: cachedAuthorFetchedAt,
            avatarMap: avatarMap
        }

        cacheFileView.setText(JSON.stringify(payload))
    }

    function _processAvatarQueue() {
        if (_avatarBusy || _avatarQueue.length === 0)
            return

        var nextQueue = _avatarQueue.slice(0)
        var item = nextQueue.shift()
        _avatarQueue = nextQueue

        // Skip if already downloaded between queue and now
        if (avatarLocalPaths.hasOwnProperty(item.login)) {
            Qt.callLater(cache._processAvatarQueue)
            return
        }

        _avatarBusy = true
        var localPath = cacheDir + "/" + Constants.cacheAvatarsSubdirectory + "/" + item.login + ".png"

        var proc = avatarDlComponent.createObject(cache, {
            login: item.login,
            localPath: localPath,
            remoteUrl: item.remoteUrl
        })
        proc.command = [
            "curl", "-sS", "-L",
            "--connect-timeout", Constants.avatarDownloadConnectTimeoutSeconds,
            "--max-time", Constants.avatarDownloadMaxTimeSeconds,
            "-o", localPath,
            item.remoteUrl
        ]
        proc.running = true
    }

    function _onAvatarDlDone(login, localPath, remoteUrl) {
        var nextPaths = _cloneMap(avatarLocalPaths)
        nextPaths[login] = "file://" + localPath
        avatarLocalPaths = nextPaths
        avatarDownloaded(login, "file://" + localPath)
        _queueSave()
    }

    function _cloneMap(source) {
        var copy = {}
        for (var key in source)
            copy[key] = source[key]
        return copy
    }

    function _shellQuote(str) {
        return "'" + String(str).replace(/'/g, "'\\''") + "'"
    }

    /// Check which cached avatar files actually exist on disk.
    /// Missing files are removed from avatarLocalPaths so they get re-downloaded.
    function _validateAvatarFiles() {
        var logins = _pendingAvatarValidation
        _pendingAvatarValidation = []
        if (logins.length === 0 || !cacheDir)
            return

        // Build a command that tests each file and prints logins of missing ones
        var avatarDir = cacheDir + "/" + Constants.cacheAvatarsSubdirectory
        var parts = []
        for (var i = 0; i < logins.length; i++) {
            var login = logins[i]
            var file = avatarDir + "/" + login + ".png"
            parts.push("[ -f " + _shellQuote(file) + " ] || echo " + _shellQuote(login))
        }

        var proc = avatarValidateComponent.createObject(cache)
        proc.command = ["sh", "-c", parts.join("; ")]
        proc.running = true
    }

    function _onAvatarValidationDone(output) {
        if (!output)
            return

        var lines = output.split("\n")
        var nextPaths = _cloneMap(avatarLocalPaths)
        var changed = false
        var redownloads = []

        for (var i = 0; i < lines.length; i++) {
            var login = lines[i].trim()
            if (login && nextPaths.hasOwnProperty(login)) {
                _perfLog("avatar file missing on disk, re-queuing download: " + login)
                delete nextPaths[login]
                changed = true
                redownloads.push({
                    login: login,
                    remoteUrl: Constants.githubAvatarsBaseUrl + "/" + encodeURIComponent(login)
                              + "?size=" + Constants.avatarDefaultSizePx
                })
            }
        }

        if (changed) {
            avatarLocalPaths = nextPaths
            _queueSave()
            if (redownloads.length > 0)
                batchQueueAvatarDownloads(redownloads)
        }
    }
}
