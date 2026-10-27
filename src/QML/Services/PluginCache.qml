// PluginCache.qml - Disk-backed cache for messages, authors, and avatar metadata
//
// Stores serialized object state and avatar files under the plugin cache root.
// Default layout:
//   ~/.cache/dms-github-inbox-plugin/objects/cache.json
//   ~/.cache/dms-github-inbox-plugin/avatars/<login>.png
// All writes are debounced so rapid updates are batched into one disk flush.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../JS/Helpers/CacheCommands.js" as CacheCommands
import "../../JS/Storage/CacheSerialization.js" as CacheSerialization
import ".."

Item {
    id: cache

    property bool _avatarValidationDuringInit: false
    property int _cacheParseSeq: 0
    property int _cacheWriteSeq: 0
    property bool _clearCacheDuringInitialize: false
    property bool _clearCachePending: false

    // -- Initialization / worker state ---------------------------------------
    property bool _initializing: false
    property var _pendingAuthorFetchedAt: ({})
    property var _pendingAvatarLocalPaths: ({})
    property var _pendingAvatarValidation: []
    property var _pendingAvatarValidationPaths: ({})
    property var _pendingChangedAuthors: ({})
    property bool _preserveDamagedCache: false
    property var avatarLocalPaths: ({})     // login -> "file:///abs/path.png"
    readonly property string cacheAvatarsDir: cacheDir ? (cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory) : ""

    // -- Configuration --------------------------------------------------------
    property string cacheDir: ""
    readonly property string cacheFilePath: cacheObjectsDir ? (cacheObjectsDir + "/" + GitHubConstants.cacheFileName) : ""
    readonly property string cacheObjectsDir: cacheDir ? (cacheDir + "/" + GitHubConstants.cacheObjectsSubdirectory) : ""
    property bool cacheWorkerEnabled: true
    property var cacheWorkerObject: null
    property var cachedAuthorFetchedAt: ({})
    property var cachedAuthorsByThread: ({})
    property var cachedDoneThreadState: ({})

    // -- Exposed cached state -------------------------------------------------
    property var cachedMessages: []
    property int cachedPollIntervalMs: 0
    property real cachedTimestamp: 0
    property bool initialized: false
    property int pollIntervalMs: 0
    property var providerApi: null

    signal avatarDownloadFinished(string login, string localUrl, int generation, bool success)
    signal avatarDownloadsRequested(var items)
    signal cacheFailure(string message)
    signal cacheReady

    // Keep optimistic mutation state separate from confirmed server state.
    function _applyParsedCache(data) {
        let profileStart = Date.now();
        _perfLog("_applyParsedCache --- start");
        let payload = CacheSerialization.decodePayload(data, GitHubConstants.cacheFormatVersion);
        cachePayloadModel.version = payload.version;
        cachePayloadModel.lastFetched = payload.lastFetched;
        cachePayloadModel.pollIntervalMs = payload.pollIntervalMs;
        cachePayloadModel.notifications = payload.notifications;
        cachePayloadModel.authorsByThread = payload.authorsByThread;
        cachePayloadModel.authorFetchedAt = payload.authorFetchedAt;
        cachePayloadModel.avatarMap = payload.avatarMap;
        cachePayloadModel.doneThreadState = payload.doneThreadState;

        cachedMessages = cachePayloadModel.notifications || [];
        cachedAuthorsByThread = cachePayloadModel.authorsByThread || ({});
        cachedAuthorFetchedAt = cachePayloadModel.authorFetchedAt || ({});
        cachedDoneThreadState = cachePayloadModel.doneThreadState || ({});
        cachedTimestamp = cachePayloadModel.lastFetched || 0;
        cachedPollIntervalMs = cachePayloadModel.pollIntervalMs;

        // Rebuild avatar local path map, validating files still exist on disk
        let avatarMap = cachePayloadModel.avatarMap || ({});
        let paths = {};
        for (let login in avatarMap) {
            let localUrl = CacheSerialization.avatarLocalUrl(avatarMap[login], cacheDir, GitHubConstants.cacheAvatarsSubdirectory);
            if (localUrl)
                paths[login] = localUrl;
        }
        // Validate before exposing local file:// URLs to the view. Old cache
        // entries may be HTML/JSON error bodies saved as .png, which causes
        // repeated QML Image decoder warnings and UI stalls.
        _pendingAvatarValidation = Object.keys(paths);
        _pendingAvatarValidationPaths = paths;
        if (_pendingAvatarValidation.length > 0) {
            _avatarValidationDuringInit = true;
            _validateAvatarFiles();
            _profile("_applyParsedCache", profileStart, "msgs=" + cachedMessages.length + " authors=" + Object.keys(cachedAuthorsByThread).length + " avatarsPendingValidation=" + _pendingAvatarValidation.length);
            return;
        }

        let normalized = _normalizeCachedResourceUrls(paths);
        avatarLocalPaths = paths;
        if (normalized)
            _queueSave();
        _perfLog("_applyParsedCache --- end, msgs=" + cachedMessages.length + " avatars=" + Object.keys(paths).length);
        _profile("_applyParsedCache", profileStart, "msgs=" + cachedMessages.length + " authors=" + Object.keys(cachedAuthorsByThread).length + " avatars=" + Object.keys(paths).length);
        initialized = true;
        cacheReady();
    }

    // Preserve unreadable or incompatible cache data before a fresh fetch can
    // schedule a write to the active cache path.
    function _backupDamagedCache(message) {
        _preserveDamagedCache = true;
        let backupPath = cacheFilePath + ".damaged-" + Date.now();
        damagedCacheBackupComponent.createObject(cache, {
            failureMessage: message,
            backupPath: backupPath,
            command: ["cp", "-p", "--", cacheFilePath, backupPath],
            running: true
        });
    }
    // Replace map identity so QML bindings can observe an update.
    function _cloneMap(source) {
        let copy = {};
        for (let key in source)
            copy[key] = source[key];
        return copy;
    }
    // Coordinate storage and resource work through this owner rather than from visual components.
    function _createDirs() {
        _perfLog("_createDirs --- spawning mkdir -p");
        initDirComponent.createObject(cache, {
            command: ["mkdir", "-p", cacheObjectsDir, cacheAvatarsDir],
            running: true
        });
    }
    // Coordinate storage and resource work through this owner rather than from visual components.
    function _flushPendingMetadata(queueSaveAfterFlush) {
        let profileStart = Date.now();
        let pendingAuthors = _pendingChangedAuthors || ({});
        let pendingFetchedAt = _pendingAuthorFetchedAt || ({});
        let pendingAvatars = _pendingAvatarLocalPaths || ({});
        let hasAuthorChanges = false;
        let hasFetchedAtChanges = false;
        let hasAvatarChanges = false;

        for (let authorThreadId in pendingAuthors) {
            cachedAuthorsByThread[authorThreadId] = pendingAuthors[authorThreadId] || [];
            hasAuthorChanges = true;
        }

        for (let fetchedThreadId in pendingFetchedAt) {
            let fetchedValue = pendingFetchedAt[fetchedThreadId] || "";
            if (fetchedValue)
                cachedAuthorFetchedAt[fetchedThreadId] = fetchedValue;
            else
                delete cachedAuthorFetchedAt[fetchedThreadId];
            hasFetchedAtChanges = true;
        }

        for (let avatarLogin in pendingAvatars) {
            let localUrl = pendingAvatars[avatarLogin] || "";
            if (!localUrl)
                continue;
            if ((avatarLocalPaths[avatarLogin] || "") === localUrl)
                continue;
            avatarLocalPaths[avatarLogin] = localUrl;
            hasAvatarChanges = true;
        }

        if (!hasAuthorChanges && !hasFetchedAtChanges && !hasAvatarChanges)
            return false;

        _pendingChangedAuthors = ({});
        _pendingAuthorFetchedAt = ({});
        _pendingAvatarLocalPaths = ({});

        if (queueSaveAfterFlush)
            _queueSave();

        _profile("_flushPendingMetadata", profileStart, "authors=" + Object.keys(pendingAuthors).length + " fetchedAt=" + Object.keys(pendingFetchedAt).length + " avatars=" + Object.keys(pendingAvatars).length);
        return true;
    }
    // Apply the owning module's rules before exposing data to dependent components.
    function _normalizeCachedResourceUrls(localPaths) {
        let paths = localPaths || ({});
        let changed = false;

        for (let messageIndex = 0; messageIndex < cachedMessages.length; messageIndex++) {
            let message = cachedMessages[messageIndex];
            if (!message)
                continue;
            let ownerLogin = String(message.repositoryOwnerLogin || "").trim();
            let ownerLocalUrl = ownerLogin ? (paths[ownerLogin] || "") : "";
            if (ownerLocalUrl && message.repositoryOwnerAvatarUrl !== ownerLocalUrl) {
                message.repositoryOwnerAvatarUrl = ownerLocalUrl;
                changed = true;
            }
        }

        for (let threadId in cachedAuthorsByThread) {
            let authors = cachedAuthorsByThread[threadId] || [];
            for (let authorIndex = 0; authorIndex < authors.length; authorIndex++) {
                let author = authors[authorIndex];
                if (!author)
                    continue;
                let login = String(author.login || "").trim();
                let localUrl = login ? (paths[login] || "") : "";
                if (localUrl && author.avatarUrl !== localUrl) {
                    author.avatarUrl = localUrl;
                    changed = true;
                }
            }
        }

        return changed;
    }
    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _onAvatarValidationDone(output) {
        let lines = output ? output.split("\n") : [];
        let initializing = _avatarValidationDuringInit;
        let validationPaths = _pendingAvatarValidationPaths || ({});
        _avatarValidationDuringInit = false;
        _pendingAvatarValidationPaths = ({});

        let invalid = {};
        for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            let invalidLogin = lines[lineIndex].trim();
            if (invalidLogin)
                invalid[invalidLogin] = true;
        }

        let nextPaths = initializing ? {} : _cloneMap(avatarLocalPaths);
        let changed = false;
        let redownloads = [];

        if (initializing) {
            for (let validLogin in validationPaths) {
                if (!invalid[validLogin])
                    nextPaths[validLogin] = validationPaths[validLogin];
            }
        }

        for (let login in invalid) {
            if ((initializing && validationPaths.hasOwnProperty(login)) || (!initializing && nextPaths.hasOwnProperty(login))) {
                _perfLog("avatar file missing or invalid on disk, re-queuing download: " + login);
                delete nextPaths[login];
                changed = true;
                redownloads.push({
                    login: login,
                    remoteUrl: cache.providerApi ? cache.providerApi.buildAvatarUrl(login) : ""
                });
            }
        }

        let normalized = initializing ? _normalizeCachedResourceUrls(nextPaths) : false;

        if (changed || initializing || normalized) {
            avatarLocalPaths = nextPaths;
            _queueSave();
            if (redownloads.length > 0)
                avatarDownloadsRequested(redownloads);
        }

        if (initializing) {
            _perfLog("_applyParsedCache --- end, msgs=" + cachedMessages.length + " avatars=" + Object.keys(nextPaths).length);
            initialized = true;
            cacheReady();
        }
    }
    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _onCacheFileRead(text) {
        _perfLog("_onCacheFileRead --- dispatching JSON parse to worker, len=" + text.length);
        _cacheParseSeq = _cacheParseSeq + 1;
        if (!cache.cacheWorkerObject) {
            cache.cacheFailure("Cache processing is unavailable.");
            return;
        }
        cache.cacheWorkerObject.sendMessage({
            action: "parseCache",
            seq: _cacheParseSeq,
            text: text,
            expectedVersion: GitHubConstants.cacheFormatVersion
        });
    }
    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _onCacheFileReadFailed() {
        _perfLog("_onCacheFileReadFailed --- file does not exist or is empty (first run)");
        initialized = true;
        cacheReady();
    }
    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _onClearCacheDone(exitCode, duringInitialize) {
        _perfLog("_onClearCacheDone --- exitCode=" + exitCode + " duringInitialize=" + duringInitialize);
        _clearCacheDuringInitialize = false;

        if (exitCode !== 0) {
            PluginLogger.error("cache", "Failed to clear the cache directory (exit code " + exitCode + ")");
            _preserveDamagedCache = true;
            cacheFailure("The cache could not be cleared. Existing files have been preserved and cache writes are disabled.");
        } else
            _preserveDamagedCache = false;

        if (duringInitialize) {
            _initializing = false;
            initialized = true;
            cacheReady();
        }
    }
    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _onDamagedCacheBackupDone(exitCode, message, backupPath) {
        let backupSucceeded = exitCode === 0;
        _preserveDamagedCache = !backupSucceeded;
        if (!backupSucceeded)
            message += " The original cache could not be backed up; cache writes are disabled until it is cleared.";
        else
            message += " The original file was preserved as " + backupPath + ".";
        PluginLogger.error("cache", backupSucceeded ? "Damaged cache was preserved before recovery" : "Damaged cache backup failed; cache writes are disabled");
        cacheFailure(message);
        initialized = true;
        cacheReady();
    }
    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _onDirReady(success) {
        _perfLog("_onDirReady --- success=" + success);
        if (!success) {
            PluginLogger.error("cache", "Failed to create the cache directory");
            initialized = true;
            cacheReady();
            return;
        }

        if (_clearCachePending) {
            clearCache();
            return;
        }

        // Read existing cache file via Process (FileView.reload is unreliable)
        let cachePath = cacheFileView.path || cacheFilePath;
        _perfLog("_onDirReady --- reading cache via cat");
        readCacheComponent.createObject(cache, {
            command: ["env", "LC_ALL=C", "cat", cachePath],
            running: true
        });
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _onDirResolved(resolvedPath) {
        _perfLog("_onDirResolved --- cache path resolved=" + Boolean(resolvedPath));
        if (!resolvedPath) {
            PluginLogger.error("cache", "Could not resolve cache directory; using fallback");
            resolvedPath = GitHubConstants.cacheFallbackDirPath;
        }
        cacheDir = resolvedPath;
        _perfLog("_onDirResolved --- cache directory set");
        _createDirs();
    }

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper (standalone, no Widget dependency) --------------
    function _perfLog(label) {
        PluginLogger.debug("PluginCache", label);
    }
    // Measure this operation through the shared profiling gate.
    function _profile(label, startMs, details) {
        let duration = Date.now() - startMs;
        PluginLogger.profile("PluginCache", label, duration, details);
    }
    // Keep queued work bounded and discard requests that no longer belong to the active state.
    function _queueSave() {
        saveDebounce.restart();
    }
    // Discard obsolete work through the owning component so unrelated state is preserved.
    function _removeAvatarFile(localPath) {
        if (!localPath || localPath.indexOf(cacheAvatarsDir + "/") !== 0)
            return;
        removeAvatarComponent.createObject(cache, {
            command: ["rm", "-f", localPath],
            running: true
        });
    }
    /// Check which cached avatar files exist and are actually images.
    /// Missing or invalid files are removed from avatarLocalPaths so they get
    /// re-downloaded instead of repeatedly forcing QML Image decode failures.
    function _validateAvatarFiles() {
        let logins = _pendingAvatarValidation;
        _pendingAvatarValidation = [];
        if (logins.length === 0 || !cacheDir)
            return;

        // Paths remain process arguments, not shell source. Invalid downloads
        // are usually GitHub HTML/JSON error pages saved under a .png name.
        let avatarDir = cacheAvatarsDir;
        let avatarPaths = [];
        for (let i = 0; i < logins.length; i++) {
            let login = logins[i];
            avatarPaths.push(avatarDir + "/" + login + ".png");
        }

        avatarValidateComponent.createObject(cache, {
            command: CacheCommands.buildAvatarValidationCommand(avatarPaths),
            running: true
        });
    }
    // Coordinate storage and resource work through this owner rather than from visual components.
    function _writeToDisk() {
        let profileStart = Date.now();
        if (!cacheDir || !initialized || _preserveDamagedCache)
            return;
        _flushPendingMetadata(false);

        let avatarMap = {};
        for (let login in avatarLocalPaths) {
            avatarMap[login] = {
                localFile: login + ".png"
            };
        }

        cachePayloadModel.version = GitHubConstants.cacheFormatVersion;
        cachePayloadModel.lastFetched = cachedTimestamp;
        cachePayloadModel.pollIntervalMs = pollIntervalMs;
        cachePayloadModel.notifications = cachedMessages;
        cachePayloadModel.authorsByThread = cachedAuthorsByThread;
        cachePayloadModel.authorFetchedAt = cachedAuthorFetchedAt;
        cachePayloadModel.avatarMap = avatarMap;
        cachePayloadModel.doneThreadState = cachedDoneThreadState;

        _cacheWriteSeq = _cacheWriteSeq + 1;
        if (!cache.cacheWorkerObject) {
            cache.cacheFailure("Cache processing is unavailable.");
            return;
        }
        cache.cacheWorkerObject.sendMessage({
            action: "stringifyCache",
            seq: _cacheWriteSeq,
            payload: CacheSerialization.serializePayload(cachePayloadModel)
        });
        _profile("_writeToDisk.preparePayload", profileStart, "msgs=" + cachedMessages.length + " authors=" + Object.keys(cachedAuthorsByThread).length + " avatars=" + Object.keys(avatarMap).length + " done=" + Object.keys(cachedDoneThreadState).length);
    }
    // Publish changed state through the owning component so consumers observe one coherent update.
    function bulkUpdateAuthors(authorsMap) {
        cachedAuthorsByThread = authorsMap || ({});
        _queueSave();
    }

    // -- Clear ----------------------------------------------------------------

    // Discard obsolete work through the owning component so unrelated state is preserved.
    function clearCache() {
        metadataFlushTimer.stop();
        saveDebounce.stop();
        _pendingChangedAuthors = ({});
        _pendingAuthorFetchedAt = ({});
        _pendingAvatarLocalPaths = ({});
        cachedMessages = [];
        cachedAuthorsByThread = ({});
        cachedAuthorFetchedAt = ({});
        cachedDoneThreadState = ({});
        avatarLocalPaths = ({});
        cachedTimestamp = 0;

        if (!cacheDir) {
            _clearCachePending = true;
            return;
        }

        _clearCachePending = false;
        _clearCacheDuringInitialize = _initializing && !initialized;

        clearCacheComponent.createObject(cache, {
            duringInitialize: _clearCacheDuringInitialize,
            command: CacheCommands.buildCacheResetCommand(cacheDir, cacheObjectsDir, cacheAvatarsDir),
            running: true
        });
    }
    // Coordinate storage and resource work through this owner rather than from visual components.
    function downloadAvatar(login, remoteUrl, generation) {
        let normalizedLogin = String(login || "");
        let normalizedUrl = String(remoteUrl || "");
        if (!cache.initialized || !cache.providerApi || !cache.providerApi.isSafeLogin(normalizedLogin) || !cache.providerApi.isAllowedAvatarUrl(normalizedUrl)) {
            avatarDownloadFinished(normalizedLogin, "", generation, false);
            return;
        }

        let localPath = cacheAvatarsDir + "/" + normalizedLogin + ".png";
        let retryPolicy = providerApi.getRetryPolicy();
        // Unlike authenticated API calls, public avatars need no token or secret headers, so dms dl is safe here.
        avatarDownloadComponent.createObject(cache, {
            login: normalizedLogin,
            localPath: localPath,
            generation: generation,
            downloadCommand: ["dms", "dl", "--connect-timeout", GitHubConstants.avatarDownloadConnectTimeoutSeconds, "--timeout", GitHubConstants.avatarDownloadMaxTimeSeconds, "-o", localPath, "--", normalizedUrl],
            maximumRetries: retryPolicy.retryCount,
            retryWindowMs: retryPolicy.maximumRetryTimeSeconds * 1000,
            retryDelayMs: GitHubConstants.avatarDownloadRetryDelayMs
        });
    }
    // Read the owner's current data without initiating unrelated background work.
    function getAuthorFetchedAt(threadId) {
        if (_pendingAuthorFetchedAt.hasOwnProperty(threadId))
            return _pendingAuthorFetchedAt[threadId] || "";
        return cachedAuthorFetchedAt[threadId] || "";
    }
    // Read the owner's current data without initiating unrelated background work.
    function getCachedAuthors(threadId) {
        return cachedAuthorsByThread[threadId] || [];
    }
    // Check the relevant invariants before dependent work can proceed.
    function hasAuthors(threadId) {
        let entry = cachedAuthorsByThread[threadId];
        return entry && entry.length > 0;
    }

    // -- Avatar resolution ----------------------------------------------------

    // Check the relevant invariants before dependent work can proceed.
    function hasLocalAvatar(login) {
        return avatarLocalPaths.hasOwnProperty(login) || _pendingAvatarLocalPaths.hasOwnProperty(login);
    }
    // Resolve storage before exposing restored data or accepting background cache work.
    function initialize() {
        if (_initializing || initialized)
            return;
        _initializing = true;
        _perfLog("initialize --- start");

        if (cacheDir) {
            _createDirs();
            return;
        }
        // Determine default cache dir from environment
        resolveDirComponent.createObject(cache, {
            command: CacheCommands.buildCacheRootResolveCommand(GitHubConstants.cacheRootDirectoryName),
            running: true
        });
    }
    // Expose whether cache metadata exists; scheduling validates its timestamp separately.
    function isFresh() {
        return cachedTimestamp !== 0;
    }

    // -- Pruning --------------------------------------------------------------

    // Discard obsolete work through the owning component so unrelated state is preserved.
    function pruneToThreads(keepIds) {
        let keep = {};
        for (let i = 0; i < keepIds.length; i++)
            keep[keepIds[i]] = true;

        let nextAuthors = {};
        for (let tid in cachedAuthorsByThread) {
            if (keep[tid])
                nextAuthors[tid] = cachedAuthorsByThread[tid];
        }
        cachedAuthorsByThread = nextAuthors;

        let nextFetchedAt = {};
        for (let ftid in cachedAuthorFetchedAt) {
            if (keep[ftid])
                nextFetchedAt[ftid] = cachedAuthorFetchedAt[ftid];
        }
        cachedAuthorFetchedAt = nextFetchedAt;

        _queueSave();
    }
    // Coordinate storage and resource work through this owner rather than from visual components.
    function resolveAvatarUrl(remoteUrl, login) {
        if (!login || !remoteUrl)
            return remoteUrl || "";
        if (_pendingAvatarLocalPaths[login])
            return _pendingAvatarLocalPaths[login];
        return avatarLocalPaths[login] || remoteUrl;
    }
    // Publish changed state through the owning component so consumers observe one coherent update.
    function updateAuthorFetchedAt(threadId, updatedAt) {
        if (!threadId)
            return;
        let nextPending = _cloneMap(_pendingAuthorFetchedAt);
        nextPending[threadId] = updatedAt || "";
        _pendingAuthorFetchedAt = nextPending;
        metadataFlushTimer.restart();
    }

    // -- Authors --------------------------------------------------------------

    // Replace changed author arrays while preserving unrelated thread records.
    function updateAuthors(threadId, authors) {
        let next = _cloneMap(cachedAuthorsByThread);
        next[threadId] = authors || [];
        cachedAuthorsByThread = next;
        _queueSave();
    }
    // Publish changed state through the owning component so consumers observe one coherent update.
    function updateAvatarLocalPath(login, localUrl) {
        if (!login || !localUrl)
            return;
        if ((avatarLocalPaths[login] || "") === localUrl || (_pendingAvatarLocalPaths[login] || "") === localUrl)
            return;
        let nextPending = _cloneMap(_pendingAvatarLocalPaths);
        nextPending[login] = localUrl;
        _pendingAvatarLocalPaths = nextPending;
        metadataFlushTimer.restart();
    }
    // Publish changed state through the owning component so consumers observe one coherent update.
    function updateAvatarLocalPaths(paths) {
        avatarLocalPaths = paths || ({});
        _queueSave();
    }
    // Publish changed state through the owning component so consumers observe one coherent update.
    function updateChangedAuthors(changedAuthorsByThread) {
        if (!changedAuthorsByThread)
            return;
        let nextPending = _cloneMap(_pendingChangedAuthors);
        let changed = false;
        for (let threadId in changedAuthorsByThread) {
            nextPending[threadId] = changedAuthorsByThread[threadId] || [];
            changed = true;
        }
        if (!changed)
            return;
        _pendingChangedAuthors = nextPending;
        metadataFlushTimer.restart();
    }
    // Publish changed state through the owning component so consumers observe one coherent update.
    function updateDoneThreadState(state) {
        cachedDoneThreadState = CacheSerialization.normalizeDoneThreadState(state);
        _queueSave();
    }

    // -- Inbox Messages -------------------------------------------------------

    // Publish a new message snapshot without treating local edits as successful remote refreshes.
    function updateMessages(items, fetchedAt) {
        cachedMessages = items || [];
        // Local read/done/avatar edits must not pretend a remote refresh succeeded.
        if (Number.isFinite(fetchedAt) && fetchedAt > 0)
            cachedTimestamp = fetchedAt;
        _queueSave();
    }

    visible: false

    // -- FileView for the JSON cache file -------------------------------------
    FileView {
        id: cacheFileView

        atomicWrites: true
        blockLoading: false
        path: cache.cacheFilePath
        preload: false
    }
    Connections {
        // Handle this workflow result at the ownership boundary and preserve failure visibility.
        function onLoadFailed(error) {
            // Only used if FileView is ever reloaded elsewhere
            PluginLogger.error("cache", "Cache file could not be loaded");
        }
        // Handle this workflow result at the ownership boundary and preserve failure visibility.
        function onSaveFailed(error) {
            PluginLogger.error("cache", "Cache file could not be saved");
            cache.cacheFailure("The inbox cache could not be saved. Check available disk space and file permissions.");
        }

        target: cacheFileView
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

            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {}
            }

            onExited: function (exitCode) {
                if (!_done) {
                    _done = true;
                    cache._onDirReady(exitCode === 0);
                }
                destroy();
            }
        }
    }
    Component {
        id: avatarDownloadComponent

        AvatarDownloadWorker {
            property int generation: 0
            property string localPath: ""
            property string login: ""

            onFinished: function (success) {
                if (!success)
                    cache._removeAvatarFile(localPath);
                cache.avatarDownloadFinished(login, success ? ("file://" + localPath) : "", generation, success);
                destroy();
            }
        }
    }
    Component {
        id: removeAvatarComponent

        Process {
            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {}
            }

            onExited: function (exitCode) {
                destroy();
            }
        }
    }
    Component {
        id: readCacheComponent

        Process {
            id: readCacheProcess

            property var _errorLines: []
            property var _lines: []

            stderr: SplitParser {
                onRead: function (line) {
                    readCacheProcess._errorLines.push(line);
                }
            }
            stdout: SplitParser {
                onRead: function (line) {
                    readCacheProcess._lines.push(line);
                }
            }

            onExited: function (exitCode) {
                if (exitCode === 0)
                    cache._onCacheFileRead(readCacheProcess._lines.join("\n"));
                else if (readCacheProcess._errorLines.join("\n").toLowerCase().indexOf("no such file or directory") >= 0)
                    cache._onCacheFileReadFailed();
                else
                    cache._backupDamagedCache("The saved cache could not be read: " + readCacheProcess._errorLines.join(" "));
                destroy();
            }
        }
    }
    Component {
        id: resolveDirComponent

        Process {
            id: resolveDirProcess

            property string _captured: ""

            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {
                    resolveDirProcess._captured = line.trim();
                }
            }

            onExited: function (exitCode) {
                cache._onDirResolved(exitCode === 0 ? resolveDirProcess._captured : "");
                destroy();
            }
        }
    }
    Component {
        id: clearCacheComponent

        Process {
            property bool duringInitialize: false

            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {}
            }

            onExited: function (exitCode) {
                cache._onClearCacheDone(exitCode, duringInitialize);
                destroy();
            }
        }
    }
    Component {
        id: avatarValidateComponent

        Process {
            id: avatarValidationProcess

            property string _output: ""

            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {
                    avatarValidationProcess._output = (avatarValidationProcess._output ? avatarValidationProcess._output + "\n" : "") + line;
                }
            }

            onExited: function (exitCode) {
                cache._onAvatarValidationDone(avatarValidationProcess._output);
                destroy();
            }
        }
    }
    Loader {
        id: cacheWorkerLoader

        active: cache.cacheWorkerEnabled

        sourceComponent: Component {
            WorkerScript {
                source: Qt.resolvedUrl("../../JS/BackgroundWorkers/CacheBackgroundWorker.js")

                onMessage: function (message) {
                    if (message.action === "cacheError") {
                        if (message.failure)
                            PluginLogger.error("cache worker", message.failure.details);
                        if (message.operation === "parseCache" && message.seq === cache._cacheParseSeq) {
                            cache._preserveDamagedCache = true;
                            cache._backupDamagedCache(message.error);
                        } else if (message.operation === "stringifyCache" && message.seq === cache._cacheWriteSeq) {
                            PluginLogger.error("cache", message.error);
                            cache.cacheFailure(message.error);
                        }
                        return;
                    }

                    if (message.action === "cacheParsed") {
                        if (message.seq !== cache._cacheParseSeq)
                            return;
                        if (!message.data || message.data.version !== GitHubConstants.cacheFormatVersion) {
                            cache._preserveDamagedCache = true;
                            cache._backupDamagedCache("The saved cache uses an unsupported format.");
                            return;
                        }
                        cache._applyParsedCache(message.data);
                        return;
                    }

                    if (message.action === "cacheStringified") {
                        if (message.seq !== cache._cacheWriteSeq)
                            return;
                        cacheFileView.setText(message.text || "{}");
                    }
                }
            }
        }

        onItemChanged: cache.cacheWorkerObject = item
    }
    Component {
        id: damagedCacheBackupComponent

        Process {
            property string backupPath: ""
            property string failureMessage: ""

            onExited: function (exitCode) {
                cache._onDamagedCacheBackupDone(exitCode, failureMessage, backupPath);
                destroy();
            }
        }
    }
}
