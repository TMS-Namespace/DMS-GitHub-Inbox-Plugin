// PluginCache.qml - Disk-backed cache for messages, authors, and avatar metadata
//
// Stores serialized object state and avatar files under the plugin cache root.
// Default layout:
//   ~/.cache/dms-github-inbox-plugin/objects/cache.json
//   ~/.cache/dms-github-inbox-plugin/avatars/<login>.png
// Metadata saves are debounced; avatar downloads write their own files.

pragma ComponentBehavior: Bound

import QtQuick
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
    readonly property var cacheWorkerObject: cacheStorage.workerObject
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

    // Decode restored cache fields and validate avatar files before publishing cache readiness.
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
        cacheStorage.backupDamagedCache(message, backupPath);
    }
    // Replace map identity so QML bindings can observe an update.
    function _cloneMap(source) {
        let copy = {};
        for (let key in source)
            copy[key] = source[key];
        return copy;
    }
    // Create the cache's object and avatar directories before reading persisted state.
    function _createDirs() {
        _perfLog("_createDirs --- spawning mkdir -p");
        cacheStorage.createDirectories();
    }
    // Merge staged author records, fetch markers and avatar paths, optionally scheduling a save.
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
    // Replace restored remote avatar URLs with validated local paths matched by login.
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
    // Drop invalid avatar paths, request replacements and finish initialization after validation.
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
    // Send cache text to the parser worker with a sequence number to reject stale results.
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
    // Finish first-run initialization when there is no cache file to restore.
    function _onCacheFileReadFailed() {
        _perfLog("_onCacheFileReadFailed --- file does not exist or is empty (first run)");
        initialized = true;
        cacheReady();
    }
    // Report cache-reset failures and disable writes when the reset command did not succeed.
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
    // Report the damaged-cache backup result and allow recovery writes only if it succeeded.
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
    // Read or clear the cache after directory creation, reporting initialization failures.
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
        _perfLog("_onDirReady --- reading cache via cat");
        cacheStorage.readCacheFile();
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    // Accept the resolved cache root, or use the fallback path, then create its directories.
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
    // Restart the save debounce so rapid metadata changes share one disk write.
    function _queueSave() {
        saveDebounce.restart();
    }
    /// Check which cached avatar files exist and are actually images.
    /// Missing or invalid files are removed from avatarLocalPaths so they get
    /// re-downloaded instead of repeatedly forcing QML Image decode failures.
    function _validateAvatarFiles() {
        let logins = _pendingAvatarValidation;
        _pendingAvatarValidation = [];
        if (logins.length === 0 || !cacheDir)
            return;

        cacheStorage.validateAvatarFiles(logins);
    }
    // Flush staged metadata and send a current-format snapshot to the serialization worker.
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
    // Replace the full cached author map and schedule persistence.
    function bulkUpdateAuthors(authorsMap) {
        cachedAuthorsByThread = authorsMap || ({});
        _queueSave();
    }

    // -- Clear ----------------------------------------------------------------

    // Clear in-memory cache state and run the disk reset once the cache root is available.
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

        cacheStorage.clearCache(_clearCacheDuringInitialize);
    }
    // Validate an avatar destination and start its bounded Dux download with the caller's generation.
    function downloadAvatar(login, remoteUrl, generation) {
        let normalizedLogin = String(login || "");
        let normalizedUrl = String(remoteUrl || "");
        if (!cache.initialized || !cache.providerApi || !cache.providerApi.isSafeLogin(normalizedLogin) || !cache.providerApi.isAllowedAvatarUrl(normalizedUrl)) {
            avatarDownloadFinished(normalizedLogin, "", generation, false);
            return;
        }

        cacheStorage.downloadAvatar(normalizedLogin, normalizedUrl, generation, providerApi.getRetryPolicy());
    }
    // Prefer a staged author-fetch marker over the persisted marker for this thread.
    function getAuthorFetchedAt(threadId) {
        if (_pendingAuthorFetchedAt.hasOwnProperty(threadId))
            return _pendingAuthorFetchedAt[threadId] || "";
        return cachedAuthorFetchedAt[threadId] || "";
    }
    // Return cached authors for this thread, or an empty list when absent.
    function getCachedAuthors(threadId) {
        return cachedAuthorsByThread[threadId] || [];
    }
    // Report whether the thread has at least one cached author.
    function hasAuthors(threadId) {
        let entry = cachedAuthorsByThread[threadId];
        return entry && entry.length > 0;
    }

    // -- Avatar resolution ----------------------------------------------------

    // Include newly staged avatar paths when checking local availability.
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
        cacheStorage.resolveDirectory();
    }
    // Expose whether cache metadata exists; scheduling validates its timestamp separately.
    function isFresh() {
        return cachedTimestamp !== 0;
    }

    // -- Pruning --------------------------------------------------------------

    // Retain author records and fetch markers only for the supplied thread IDs; leave avatars intact.
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
    // Prefer a staged or saved local avatar path, otherwise keep the supplied remote URL.
    function resolveAvatarUrl(remoteUrl, login) {
        if (!login || !remoteUrl)
            return remoteUrl || "";
        if (_pendingAvatarLocalPaths[login])
            return _pendingAvatarLocalPaths[login];
        return avatarLocalPaths[login] || remoteUrl;
    }
    // Stage the thread's author-fetch marker for the next metadata flush.
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
    // Stage a changed local avatar path without requeuing identical values.
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
    // Replace the complete local avatar-path map and schedule persistence.
    function updateAvatarLocalPaths(paths) {
        avatarLocalPaths = paths || ({});
        _queueSave();
    }
    // Stage changed author lists by thread for a batched metadata flush.
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
    // Normalize the Done-state map before scheduling its persistence.
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
    CacheStorageService {
        id: cacheStorage

        avatarsDirectory: cache.cacheAvatarsDir
        cacheDirectory: cache.cacheDir
        cacheFilePath: cache.cacheFilePath
        objectsDirectory: cache.cacheObjectsDir
        workerEnabled: cache.cacheWorkerEnabled

        onAvatarDownloadFinished: (login, localUrl, generation, success) => cache.avatarDownloadFinished(login, localUrl, generation, success)
        onAvatarValidationFinished: output => cache._onAvatarValidationDone(output)
        onBackupFinished: (exitCode, message, backupPath) => cache._onDamagedCacheBackupDone(exitCode, message, backupPath)
        onCacheFileMissing: cache._onCacheFileReadFailed()
        onCacheFileRead: text => cache._onCacheFileRead(text)
        onCacheFileReadFailed: details => cache._backupDamagedCache("The saved cache could not be read: " + details)
        onClearFinished: (exitCode, duringInitialize) => cache._onClearCacheDone(exitCode, duringInitialize)
        onDirectoryReady: success => cache._onDirReady(success)
        onDirectoryResolved: path => cache._onDirResolved(path)
        onSaveFailed: cache.cacheFailure("The inbox cache could not be saved. Check available disk space and file permissions.")
        onWorkerMessage: message => {
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
            if (message.action === "cacheStringified" && message.seq === cache._cacheWriteSeq)
                cacheStorage.writeCacheText(message.text || "{}");
        }
    }
}
