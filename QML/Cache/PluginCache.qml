// PluginCache.qml - Disk-backed cache for messages, authors, and avatar metadata
//
// Stores serialized object state and avatar files under the plugin cache root.
// Default layout:
//   ~/.cache/dms-github-inbox-plugin/objects/cache.json
//   ~/.cache/dms-github-inbox-plugin/avatars/<login>.png
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
    readonly property string cacheObjectsDir: cacheDir ? (cacheDir + "/" + GitHubConstants.cacheObjectsSubdirectory) : ""
    readonly property string cacheAvatarsDir: cacheDir ? (cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory) : ""
    readonly property string cacheFilePath: cacheObjectsDir ? (cacheObjectsDir + "/" + GitHubConstants.cacheFileName) : ""

    // -- Exposed cached state -------------------------------------------------
    property var cachedMessages: []
    property var cachedAuthorsByThread: ({})
    property var cachedAuthorFetchedAt: ({})
    property var avatarLocalPaths: ({})     // login -> "file:///abs/path.png"
    property real cachedTimestamp: 0
    property bool initialized: false

    signal cacheReady()
    signal avatarDownloadsRequested(var items)

    // -- FileView for the JSON cache file -------------------------------------
    FileView {
        id: cacheFileView
        path: cache.cacheFilePath
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

    CachePayload {
        id: cachePayloadModel
    }

    AvatarCacheEntry {
        id: avatarCacheEntryModel
    }

    // -- Initialization / worker state ---------------------------------------
    property bool _initializing: false
    property var _pendingAvatarValidation: []
    property var _pendingAvatarValidationPaths: ({})
    property bool _avatarValidationDuringInit: false
    property int _cacheParseSeq: 0
    property int _cacheWriteSeq: 0
    property var _pendingChangedAuthors: ({})
    property var _pendingAuthorFetchedAt: ({})
    property var _pendingAvatarLocalPaths: ({})
    property bool _clearCachePending: false
    property bool _clearCacheDuringInitialize: false

    Timer {
        id: metadataFlushTimer
        interval: GitHubConstants.cacheMetadataFlushIntervalMs
        repeat: false
        onTriggered: cache._flushPendingMetadata(true)
    }

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
        id: clearCacheComponent
        Process {
            property bool duringInitialize: false
            stdout: SplitParser { onRead: function(line) {} }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                cache._onClearCacheDone(exitCode, duringInitialize)
                destroy()
            }
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
        source: Qt.resolvedUrl("../../JS/BackgroundWorkers/CacheBackgroundWorker.js")

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
        console.warn("[GitHubInbox PERF] PluginCache: " + label)
    }

    function _profile(label, startMs, details) {
        if (!GitHubConstants.profileLoggingEnabled)
            return
        var duration = Date.now() - startMs
        if (!GitHubConstants.profileLogAllOperations
                && duration < GitHubConstants.profileSlowOperationThresholdMs)
            return
        var suffix = details ? (" — " + details) : ""
        console.warn("[GitHubInbox PROFILE] PluginCache." + label
                     + " took " + duration + "ms" + suffix)
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
            "echo \"${XDG_CACHE_HOME:-$HOME/.cache}/" + GitHubConstants.cacheRootDirectoryName + "\""
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

    function updateChangedAuthors(changedAuthorsByThread) {
        if (!changedAuthorsByThread)
            return

        var nextPending = _cloneMap(_pendingChangedAuthors)
        var changed = false
        for (var threadId in changedAuthorsByThread) {
            nextPending[threadId] = changedAuthorsByThread[threadId] || []
            changed = true
        }
        if (!changed)
            return

        _pendingChangedAuthors = nextPending
        metadataFlushTimer.restart()
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
        if (!threadId)
            return

        var nextPending = _cloneMap(_pendingAuthorFetchedAt)
        nextPending[threadId] = updatedAt || ""
        _pendingAuthorFetchedAt = nextPending
        metadataFlushTimer.restart()
    }

    function getAuthorFetchedAt(threadId) {
        if (_pendingAuthorFetchedAt.hasOwnProperty(threadId))
            return _pendingAuthorFetchedAt[threadId] || ""
        return cachedAuthorFetchedAt[threadId] || ""
    }

    // -- Avatar resolution ----------------------------------------------------

    function hasLocalAvatar(login) {
        return avatarLocalPaths.hasOwnProperty(login)
               || _pendingAvatarLocalPaths.hasOwnProperty(login)
    }

    function resolveAvatarUrl(remoteUrl, login) {
        if (!login || !remoteUrl)
            return remoteUrl || ""
        if (_pendingAvatarLocalPaths[login])
            return _pendingAvatarLocalPaths[login]
        return avatarLocalPaths[login] || remoteUrl
    }

    function updateAvatarLocalPaths(paths) {
        avatarLocalPaths = paths || ({})
        _queueSave()
    }

    function updateAvatarLocalPath(login, localUrl) {
        if (!login || !localUrl)
            return
        if ((avatarLocalPaths[login] || "") === localUrl
                || (_pendingAvatarLocalPaths[login] || "") === localUrl)
            return

        var nextPending = _cloneMap(_pendingAvatarLocalPaths)
        nextPending[login] = localUrl
        _pendingAvatarLocalPaths = nextPending
        metadataFlushTimer.restart()
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
        metadataFlushTimer.stop()
        saveDebounce.stop()
        _pendingChangedAuthors = ({})
        _pendingAuthorFetchedAt = ({})
        _pendingAvatarLocalPaths = ({})
        cachedMessages = []
        cachedAuthorsByThread = ({})
        cachedAuthorFetchedAt = ({})
        avatarLocalPaths = ({})
        cachedTimestamp = 0

        if (!cacheDir) {
            _clearCachePending = true
            return
        }

        _clearCachePending = false
        _clearCacheDuringInitialize = _initializing && !initialized

        var proc = clearCacheComponent.createObject(cache, {
            duringInitialize: _clearCacheDuringInitialize
        })
        proc.command = [
            "sh", "-c",
            "find " + _shellQuote(cacheDir) + " -mindepth 1 -exec rm -rf -- {} +"
            + " ; mkdir -p " + _shellQuote(cacheObjectsDir)
            + " " + _shellQuote(cacheAvatarsDir)
        ]
        proc.running = true
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
        proc.command = ["mkdir", "-p", cacheObjectsDir, cacheAvatarsDir]
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

        if (_clearCachePending) {
            clearCache()
            return
        }

        // Read existing cache file via Process (FileView.reload is unreliable)
        var cachePath = cacheFileView.path || cacheFilePath
        _perfLog("_onDirReady — reading cache via cat: '" + cachePath + "'")
        var proc = readCacheComponent.createObject(cache)
        proc.command = ["cat", cachePath]
        proc.running = true
    }

    function _onClearCacheDone(exitCode, duringInitialize) {
        _perfLog("_onClearCacheDone — exitCode=" + exitCode + " duringInitialize=" + duringInitialize)
        _clearCacheDuringInitialize = false

        if (exitCode !== 0)
            console.warn("[GitHubInbox] Failed to clear cache directory:", cacheDir)

        if (duringInitialize) {
            _initializing = false
            initialized = true
            cacheReady()
        }
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
        var profileStart = Date.now()
        _perfLog("_applyParsedCache — start")
        cachePayloadModel.readFromObject(data, GitHubConstants.cacheFormatVersion)

        cachedMessages = cachePayloadModel.notifications || []
        cachedAuthorsByThread = cachePayloadModel.authorsByThread || ({})
        cachedAuthorFetchedAt = cachePayloadModel.authorFetchedAt || ({})
        cachedTimestamp = cachePayloadModel.lastFetched || 0

        // Rebuild avatar local path map, validating files still exist on disk
        var avatarMap = cachePayloadModel.avatarMap || ({})
        var paths = {}
        for (var login in avatarMap) {
            avatarCacheEntryModel.readFromObject(
                avatarMap[login],
                login,
                cacheDir,
                GitHubConstants.cacheAvatarsSubdirectory
            )
            if (avatarCacheEntryModel.localUrl)
                paths[login] = avatarCacheEntryModel.localUrl
        }
        // Validate before exposing local file:// URLs to the view. Old cache
        // entries may be HTML/JSON error bodies saved as .png, which causes
        // repeated QML Image decoder warnings and UI stalls.
        _pendingAvatarValidation = Object.keys(paths)
        _pendingAvatarValidationPaths = paths
        if (_pendingAvatarValidation.length > 0) {
            _avatarValidationDuringInit = true
            _validateAvatarFiles()
            _profile("_applyParsedCache", profileStart,
                     "msgs=" + cachedMessages.length + " authors=" + Object.keys(cachedAuthorsByThread).length
                     + " avatarsPendingValidation=" + _pendingAvatarValidation.length)
            return
        }

        avatarLocalPaths = paths
        _perfLog("_applyParsedCache — end, msgs=" + cachedMessages.length + " avatars=" + Object.keys(paths).length)
        _profile("_applyParsedCache", profileStart,
                 "msgs=" + cachedMessages.length + " authors=" + Object.keys(cachedAuthorsByThread).length
                 + " avatars=" + Object.keys(paths).length)
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
        var profileStart = Date.now()
        if (!cacheDir || !initialized)
            return

        _flushPendingMetadata(false)

        var avatarMap = {}
        for (var login in avatarLocalPaths) {
            avatarCacheEntryModel.login = login
            avatarCacheEntryModel.localFile = login + ".png"
            avatarCacheEntryModel.localUrl = avatarLocalPaths[login] || ""
            avatarMap[login] = avatarCacheEntryModel.toObject()
        }

        cachePayloadModel.version = GitHubConstants.cacheFormatVersion
        cachePayloadModel.lastFetched = cachedTimestamp
        cachePayloadModel.notifications = cachedMessages
        cachePayloadModel.authorsByThread = cachedAuthorsByThread
        cachePayloadModel.authorFetchedAt = cachedAuthorFetchedAt
        cachePayloadModel.avatarMap = avatarMap

        _cacheWriteSeq = _cacheWriteSeq + 1
        cacheWorker.sendMessage({
            action: "stringifyCache",
            seq: _cacheWriteSeq,
            payload: cachePayloadModel.toObject()
        })
        _profile("_writeToDisk.preparePayload", profileStart,
                 "msgs=" + cachedMessages.length + " authors=" + Object.keys(cachedAuthorsByThread).length
                 + " avatars=" + Object.keys(avatarMap).length)
    }

    function _flushPendingMetadata(queueSaveAfterFlush) {
        var profileStart = Date.now()
        var pendingAuthors = _pendingChangedAuthors || ({})
        var pendingFetchedAt = _pendingAuthorFetchedAt || ({})
        var pendingAvatars = _pendingAvatarLocalPaths || ({})
        var hasAuthorChanges = false
        var hasFetchedAtChanges = false
        var hasAvatarChanges = false

        for (var authorThreadId in pendingAuthors) {
            cachedAuthorsByThread[authorThreadId] = pendingAuthors[authorThreadId] || []
            hasAuthorChanges = true
        }

        for (var fetchedThreadId in pendingFetchedAt) {
            var fetchedValue = pendingFetchedAt[fetchedThreadId] || ""
            if (fetchedValue)
                cachedAuthorFetchedAt[fetchedThreadId] = fetchedValue
            else
                delete cachedAuthorFetchedAt[fetchedThreadId]
            hasFetchedAtChanges = true
        }

        for (var avatarLogin in pendingAvatars) {
            var localUrl = pendingAvatars[avatarLogin] || ""
            if (!localUrl)
                continue
            if ((avatarLocalPaths[avatarLogin] || "") === localUrl)
                continue
            avatarLocalPaths[avatarLogin] = localUrl
            hasAvatarChanges = true
        }

        if (!hasAuthorChanges && !hasFetchedAtChanges && !hasAvatarChanges)
            return false

        _pendingChangedAuthors = ({})
        _pendingAuthorFetchedAt = ({})
        _pendingAvatarLocalPaths = ({})

        if (queueSaveAfterFlush)
            _queueSave()

        _profile("_flushPendingMetadata", profileStart,
                 "authors=" + Object.keys(pendingAuthors).length
                 + " fetchedAt=" + Object.keys(pendingFetchedAt).length
                 + " avatars=" + Object.keys(pendingAvatars).length)
        return true
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
        var avatarDir = cacheAvatarsDir
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
                avatarDownloadsRequested(redownloads)
        }

        if (initializing) {
            _perfLog("_applyParsedCache — end, msgs=" + cachedMessages.length + " avatars=" + Object.keys(nextPaths).length)
            initialized = true
            cacheReady()
        }
    }
}
