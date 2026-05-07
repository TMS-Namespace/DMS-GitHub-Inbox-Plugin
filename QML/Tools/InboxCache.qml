// InboxCache.qml - Disk-backed cache for inbox messages, authors, and avatars
//
// Stores a single JSON file (messages + author data + avatar map) and
// individual avatar image files under a configurable XDG-compatible cache dir.
// All writes are debounced so rapid updates are batched into one disk flush.

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: cache
    visible: false

    // -- Configuration --------------------------------------------------------
    property string cacheDir: ""
    property int cacheTtlMinutes: GitHubConstants.defaultCacheTtlMinutes

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
        path: cache.cacheDir ? (cache.cacheDir + "/" + GitHubConstants.cacheFileName) : ""
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
        interval: GitHubConstants.cacheSaveDebounceMs
        onTriggered: cache._writeToDisk()
    }

    // -- Avatar download queue ------------------------------------------------
    readonly property bool isDownloadingAvatars: _avatarBusy || _avatarQueue.length > 0
    property var _avatarQueue: []
    property bool _avatarBusy: false
    property bool _initializing: false
    property var _pendingAvatarValidation: []
    property var _pendingAvatarValidationPaths: ({})
    property bool _avatarValidationDuringInit: false
    property var _avatarFailedLogins: ({})
    property int _cacheParseSeq: 0
    property int _cacheWriteSeq: 0

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
                else if (login)
                    cache._onAvatarDlFailed(login, localPath)
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

    WorkerScript {
        id: cacheWorker
        source: Qt.resolvedUrl("../../JS/CacheWorker.js")

        onMessage: function(message) {
            if (message.action === "cacheParsed") {
                if (message.seq !== cache._cacheParseSeq)
                    return
                cache._applyParsedCache(message.data || ({}))
                return
            }

            if (message.action === "cacheStringified") {
                if (message.seq !== cache._cacheWriteSeq)
                    return
                cacheFileView.setText(message.text || "{}")
            }
        }
    }

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper (standalone, no Widget dependency) --------------
    function _perfLog(label) {
        if (!GitHubConstants.debugPerformanceLogging) return
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
            "echo \"${XDG_CACHE_HOME:-$HOME/.cache}/" + GitHubConstants.cacheSubdirectory + "\""
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
        if (_avatarFailedLogins[login])
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
            if (_avatarFailedLogins[login])
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
        _avatarFailedLogins = ({})

        if (cacheDir) {
            var proc = clearCacheComponent.createObject(cache)
            proc.command = [
                "sh", "-c",
                "rm -f " + _shellQuote(cacheDir + "/" + GitHubConstants.cacheFileName)
                + " && rm -rf " + _shellQuote(cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory)
                + " && mkdir -p " + _shellQuote(cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory)
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
            resolvedPath = GitHubConstants.cacheFallbackDirPath
        }
        cacheDir = resolvedPath
        _perfLog("_onDirResolved — cacheDir set, FileView.path='" + cacheFileView.path + "'")
        _createDirs()
    }

    function _createDirs() {
        _perfLog("_createDirs — spawning mkdir -p")
        var proc = initDirComponent.createObject(cache)
        proc.command = ["mkdir", "-p", cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory]
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
        var cachePath = cacheFileView.path || (cacheDir + "/" + GitHubConstants.cacheFileName)
        _perfLog("_onDirReady — reading cache via cat: '" + cachePath + "'")
        var proc = readCacheComponent.createObject(cache)
        proc.command = ["cat", cachePath]
        proc.running = true
    }

    function _onCacheFileRead(text) {
        _perfLog("_onCacheFileRead — dispatching JSON parse to worker, len=" + text.length)
        _cacheParseSeq = _cacheParseSeq + 1
        cacheWorker.sendMessage({
            action: "parseCache",
            seq: _cacheParseSeq,
            text: text || "{}"
        })
    }

    function _applyParsedCache(data) {
        _perfLog("_applyParsedCache — start")
        if ((data.version || 0) !== GitHubConstants.cacheFormatVersion)
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
                var fullPath = cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory + "/" + localFile
                paths[login] = "file://" + fullPath
            }
        }
        // Validate before exposing local file:// URLs to the view. Old cache
        // entries may be HTML/JSON error bodies saved as .png, which causes
        // repeated QML Image decoder warnings and UI stalls.
        _pendingAvatarValidation = Object.keys(paths)
        _pendingAvatarValidationPaths = paths
        if (_pendingAvatarValidation.length > 0) {
            _avatarValidationDuringInit = true
            _validateAvatarFiles()
            return
        }

        _perfLog("_applyParsedCache — end, msgs=" + cachedMessages.length + " avatars=" + Object.keys(paths).length)
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
            version: GitHubConstants.cacheFormatVersion,
            lastFetched: cachedTimestamp,
            notifications: cachedMessages,
            authorsByThread: cachedAuthorsByThread,
            authorFetchedAt: cachedAuthorFetchedAt,
            avatarMap: avatarMap
        }

        _cacheWriteSeq = _cacheWriteSeq + 1
        cacheWorker.sendMessage({
            action: "stringifyCache",
            seq: _cacheWriteSeq,
            payload: payload
        })
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
        var localPath = cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory + "/" + item.login + ".png"

        var proc = avatarDlComponent.createObject(cache, {
            login: item.login,
            localPath: localPath,
            remoteUrl: item.remoteUrl
        })
        proc.command = [
            "curl", "-f", "-sS", "-L",
            "--connect-timeout", GitHubConstants.avatarDownloadConnectTimeoutSeconds,
            "--max-time", GitHubConstants.avatarDownloadMaxTimeSeconds,
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

    function _onAvatarDlFailed(login, localPath) {
        var failed = _cloneMap(_avatarFailedLogins)
        failed[login] = true
        _avatarFailedLogins = failed
        if (localPath) {
            var proc = clearCacheComponent.createObject(cache)
            proc.command = ["rm", "-f", localPath]
            proc.running = true
        }
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

    /// Check which cached avatar files exist and are actually images.
    /// Missing or invalid files are removed from avatarLocalPaths so they get
    /// re-downloaded instead of repeatedly forcing QML Image decode failures.
    function _validateAvatarFiles() {
        var logins = _pendingAvatarValidation
        _pendingAvatarValidation = []
        if (logins.length === 0 || !cacheDir)
            return

        // Build a command that tests each file and prints logins of missing or
        // non-image files. Invalid downloads are usually GitHub HTML/JSON error
        // pages saved under a .png name.
        var avatarDir = cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory
        var parts = []
        for (var i = 0; i < logins.length; i++) {
            var login = logins[i]
            var file = avatarDir + "/" + login + ".png"
            var quotedFile = _shellQuote(file)
            parts.push("if [ ! -f " + quotedFile + " ]; then echo " + _shellQuote(login)
                       + "; else mime=$(file -b --mime-type " + quotedFile + " 2>/dev/null); case \"$mime\" in image/*) ;; *) rm -f "
                       + quotedFile + "; echo "
                       + _shellQuote(login) + " ;; esac; fi")
        }

        var proc = avatarValidateComponent.createObject(cache)
        proc.command = ["sh", "-c", parts.join("; ")]
        proc.running = true
    }

    function _onAvatarValidationDone(output) {
        var lines = output ? output.split("\n") : []
        var initializing = _avatarValidationDuringInit
        var validationPaths = _pendingAvatarValidationPaths || ({})
        _avatarValidationDuringInit = false
        _pendingAvatarValidationPaths = ({})

        var invalid = {}
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            var invalidLogin = lines[lineIndex].trim()
            if (invalidLogin)
                invalid[invalidLogin] = true
        }

        var nextPaths = initializing ? {} : _cloneMap(avatarLocalPaths)
        var changed = false
        var redownloads = []

        if (initializing) {
            for (var validLogin in validationPaths) {
                if (!invalid[validLogin])
                    nextPaths[validLogin] = validationPaths[validLogin]
            }
        }

        for (var login in invalid) {
            if ((initializing && validationPaths.hasOwnProperty(login))
                    || (!initializing && nextPaths.hasOwnProperty(login))) {
                _perfLog("avatar file missing or invalid on disk, re-queuing download: " + login)
                delete nextPaths[login]
                changed = true
                redownloads.push({
                    login: login,
                    remoteUrl: GitHubConstants.githubAvatarsBaseUrl + "/" + encodeURIComponent(login)
                              + "?size=" + GitHubConstants.avatarDefaultSizePx
                })
            }
        }

        if (changed || initializing) {
            avatarLocalPaths = nextPaths
            _queueSave()
            if (redownloads.length > 0)
                batchQueueAvatarDownloads(redownloads)
        }

        if (initializing) {
            _perfLog("_applyParsedCache — end, msgs=" + cachedMessages.length + " avatars=" + Object.keys(nextPaths).length)
            initialized = true
            cacheReady()
        }
    }
}
