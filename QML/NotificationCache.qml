// NotificationCache.qml - Disk-backed cache for notifications, authors, and avatars
//
// Stores a single JSON file (notifications + author data + avatar map) and
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
    property var cachedNotifications: []
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
        path: cache.cacheDir ? (cache.cacheDir + "/cache.json") : ""
        preload: false
        blockLoading: false
        atomicWrites: true
    }

    Connections {
        target: cacheFileView
        function onLoaded() { cache._onCacheLoaded() }
        function onLoadFailed(error) { cache._onCacheLoadFailed(error) }
    }

    // -- Save debounce timer --------------------------------------------------
    Timer {
        id: saveDebounce
        interval: Constants.cacheSaveDebounceMs
        onTriggered: cache._writeToDisk()
    }

    // -- Avatar download queue ------------------------------------------------
    property var _avatarQueue: []
    property bool _avatarBusy: false

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

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    function initialize() {
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

    // -- Notifications --------------------------------------------------------

    function updateNotifications(items) {
        cachedNotifications = items || []
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
        cachedNotifications = []
        cachedAuthorsByThread = ({})
        cachedAuthorFetchedAt = ({})
        avatarLocalPaths = ({})
        cachedTimestamp = 0
        _avatarQueue = []

        if (cacheDir) {
            var proc = clearCacheComponent.createObject(cache)
            proc.command = [
                "sh", "-c",
                "rm -f " + _shellQuote(cacheDir + "/cache.json")
                + " && rm -rf " + _shellQuote(cacheDir + "/avatars")
                + " && mkdir -p " + _shellQuote(cacheDir + "/avatars")
            ]
            proc.running = true
        }
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    function _onDirResolved(resolvedPath) {
        if (!resolvedPath) {
            console.warn("[GitHubInbox] Could not resolve cache directory, using fallback")
            resolvedPath = "/tmp/github-inbox-cache"
        }
        cacheDir = resolvedPath
        _createDirs()
    }

    function _createDirs() {
        var proc = initDirComponent.createObject(cache)
        proc.command = ["mkdir", "-p", cacheDir + "/avatars"]
        proc.running = true
    }

    function _onDirReady(success) {
        if (!success) {
            console.warn("[GitHubInbox] Failed to create cache directory:", cacheDir)
            initialized = true
            cacheReady()
            return
        }

        // Load existing cache
        if (cacheFileView.path)
            cacheFileView.reload()
        else
            cacheFileView.path = cacheDir + "/cache.json"
    }

    function _onCacheLoaded() {
        var data
        try {
            data = JSON.parse(cacheFileView.text() || "{}")
        } catch (e) {
            data = {}
        }

        if ((data.version || 0) !== Constants.cacheFormatVersion)
            data = {}

        cachedNotifications = data.notifications || []
        cachedAuthorsByThread = data.authorsByThread || ({})
        cachedAuthorFetchedAt = data.authorFetchedAt || ({})
        cachedTimestamp = data.lastFetched || 0

        // Rebuild avatar local path map
        var avatarMap = data.avatarMap || ({})
        var paths = {}
        for (var login in avatarMap) {
            var localFile = avatarMap[login].localFile || ""
            if (localFile)
                paths[login] = "file://" + cacheDir + "/avatars/" + localFile
        }
        avatarLocalPaths = paths

        initialized = true
        cacheReady()
    }

    function _onCacheLoadFailed(error) {
        // File doesn't exist yet — first run
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
            notifications: cachedNotifications,
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
        var localPath = cacheDir + "/avatars/" + item.login + ".png"

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
}
