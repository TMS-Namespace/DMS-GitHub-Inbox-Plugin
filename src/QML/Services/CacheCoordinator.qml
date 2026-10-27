// CacheCoordinator.qml - Bridges disk cache with runtime state
//
// Owns the PluginCache and avatar downloader, and provides high-level operations:
// resolving avatar URLs, loading cached state, persisting updates, and
// handling clear-cache requests from the settings panel.

import QtQuick
import ".."

Item {
    id: coordinator

    property bool cacheWorkersEnabled: true

    // -- Exposed state --------------------------------------------------------
    readonly property bool initialized: diskCache.initialized
    readonly property bool isDownloadingAvatars: avatarWorker.isBusy
    property int pollIntervalMs: 0
    property var providerApi: null

    signal avatarCachedLocally(string login, string localUrl)
    signal cacheFailure(string message)

    // -- Signals --------------------------------------------------------------
    signal cacheReady

    /// Returns true if url is a file:// URL
    function _isLocalUrl(url) {
        return url && String(url).indexOf("file://") === 0;
    }

    /// Returns true if url is a file:// URL but the login is NOT in avatarLocalPaths
    function _isStaleLocalUrl(url, login) {
        return _isLocalUrl(url) && !diskCache.hasLocalAvatar(login);
    }

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        PluginLogger.debug("CacheCoord", label);
    }
    // Measure this operation through the shared profiling gate.
    function _profile(label, startMs, details) {
        let duration = Date.now() - startMs;
        PluginLogger.profile("CacheCoord", label, duration, details);
    }

    /// Construct a fresh remote avatar URL from a login
    function _remoteAvatarUrl(login) {
        return providerApi ? providerApi.buildAvatarUrl(login) : "";
    }
    // Persist a replacement author map through the disk-cache owner.
    function bulkUpdateAuthors(authorsMap) {
        diskCache.bulkUpdateAuthors(authorsMap);
    }
    // Return a cached local avatar URL without scheduling a download.
    function cachedLocalAvatarUrl(login) {
        let normalizedLogin = String(login || "").trim();
        if (!diskCache.initialized || !normalizedLogin)
            return "";

        let resolved = diskCache.resolveAvatarUrl(_remoteAvatarUrl(normalizedLogin), normalizedLogin);
        return _isLocalUrl(resolved) ? resolved : "";
    }
    // Cancel avatar downloads before clearing memory and disk cache state.
    function clearCache() {
        avatarWorker.reset();
        diskCache.clearCache();
    }

    // -- Settings clear-cache flag handling -----------------------------------

    // Consume the persisted clear-cache request and clear its flag after dispatch.
    function handleClearCacheRequest(pluginData, pluginService) {
        let flag = (pluginData.clearCacheRequested || "").trim().toLowerCase();
        if (flag === "true" || flag === "1") {
            coordinator.clearCache();
            if (pluginService)
                pluginService.savePluginData(GitHubConstants.pluginNamespaceId, "clearCacheRequested", "");
        }
    }
    // Resolve storage before exposing restored data or accepting background cache work.
    function initialize() {
        _perfLog("initialize");
        diskCache.initialize();
    }
    // Expose whether cache metadata exists; scheduling validates its timestamp separately.
    function isFresh() {
        return diskCache.isFresh();
    }

    // -- Load cached data into runtime structures -----------------------------

    /// Restore message, author, Done-state and refresh-scheduling fields from the disk cache.
    function loadCachedState() {
        let profileStart = Date.now();
        _perfLog("loadCachedState");
        let result = {
            messages: diskCache.cachedMessages || [],
            authorsByThread: diskCache.cachedAuthorsByThread || ({}),
            authorFetchedAt: diskCache.cachedAuthorFetchedAt || ({}),
            doneThreadState: diskCache.cachedDoneThreadState || ({}),
            timestamp: diskCache.cachedTimestamp || 0,
            pollIntervalMs: diskCache.cachedPollIntervalMs
        };
        _profile("loadCachedState", profileStart, "messages=" + result.messages.length);
        return result;
    }
    // Ask the disk cache to retain author metadata only for these thread IDs.
    function pruneToThreads(keepIds) {
        diskCache.pruneToThreads(keepIds);
    }
    // Cancel queued downloads and restore the downloader's known local paths.
    function resetAvatarDownloads() {
        avatarWorker.reset();
        avatarWorker.setAvatarLocalPaths(diskCache.avatarLocalPaths);
    }
    // Replace author avatar URLs with cached files and enqueue missing downloads.
    function resolveAuthorAvatars(authors) {
        let profileStart = Date.now();
        _perfLog("resolveAuthorAvatars --- count=" + (authors ? authors.length : 0));
        if (!diskCache.initialized)
            return;
        let downloads = [];
        let resolvedLocalAvatars = {};
        for (let i = 0; i < authors.length; i++) {
            let author = authors[i];
            let login = (author.login || "").trim();
            if (!login || !author.avatarUrl)
                continue;
            let currentUrl = author.avatarUrl;
            // Fix stale file:// URLs whose files have been removed from disk
            if (_isStaleLocalUrl(currentUrl, login))
                currentUrl = _remoteAvatarUrl(login);

            let resolved = diskCache.resolveAvatarUrl(currentUrl, login);
            if (resolved !== currentUrl) {
                author.avatarUrl = resolved;
                if (_isLocalUrl(resolved))
                    resolvedLocalAvatars[login] = resolved;
            } else if (!_isLocalUrl(resolved)) {
                author.avatarUrl = resolved;
                downloads.push({
                    login: login,
                    remoteUrl: resolved
                });
            } else
                author.avatarUrl = resolved;
        }
        if (downloads.length > 0)
            avatarWorker.batchQueueAvatarDownloads(downloads);
        for (let resolvedLogin in resolvedLocalAvatars)
            coordinator.avatarCachedLocally(resolvedLogin, resolvedLocalAvatars[resolvedLogin]);
        _profile("resolveAuthorAvatars", profileStart, "authors=" + (authors ? authors.length : 0) + " downloads=" + downloads.length);
    }

    // -- Avatar resolution ----------------------------------------------------

    // Replace repository-owner avatar URLs with cached files and enqueue missing downloads.
    function resolveMessageAvatars(items) {
        let profileStart = Date.now();
        _perfLog("resolveMessageAvatars --- count=" + (items ? items.length : 0));
        if (!diskCache.initialized)
            return;
        let downloads = [];
        let resolvedLocalAvatars = {};
        for (let i = 0; i < items.length; i++) {
            let item = items[i];
            let login = (item.repositoryOwnerLogin || "").trim();
            if (!login || !item.repositoryOwnerAvatarUrl)
                continue;
            let currentUrl = item.repositoryOwnerAvatarUrl;
            // Fix stale file:// URLs whose files have been removed from disk
            if (_isStaleLocalUrl(currentUrl, login))
                currentUrl = _remoteAvatarUrl(login);

            let resolved = diskCache.resolveAvatarUrl(currentUrl, login);
            if (resolved !== currentUrl) {
                item.repositoryOwnerAvatarUrl = resolved;
                if (_isLocalUrl(resolved))
                    resolvedLocalAvatars[login] = resolved;
            } else if (!_isLocalUrl(resolved)) {
                item.repositoryOwnerAvatarUrl = resolved;
                downloads.push({
                    login: login,
                    remoteUrl: resolved
                });
            } else
                item.repositoryOwnerAvatarUrl = resolved;
        }
        if (downloads.length > 0)
            avatarWorker.batchQueueAvatarDownloads(downloads);
        for (let resolvedLogin in resolvedLocalAvatars)
            coordinator.avatarCachedLocally(resolvedLogin, resolvedLocalAvatars[resolvedLogin]);
        _profile("resolveMessageAvatars", profileStart, "items=" + (items ? items.length : 0) + " downloads=" + downloads.length);
    }
    // Stage a thread's author-fetch marker through the disk-cache owner.
    function updateAuthorFetchedAt(threadId, updatedAt) {
        diskCache.updateAuthorFetchedAt(threadId, updatedAt);
    }
    // Replace changed author arrays while preserving unrelated thread records.
    function updateAuthors(threadId, authors) {
        diskCache.updateAuthors(threadId, authors);
    }
    // Stage only changed thread author lists through the disk-cache owner.
    function updateChangedAuthors(changedAuthorsByThread) {
        diskCache.updateChangedAuthors(changedAuthorsByThread);
    }
    // Persist the normalized Done-state map through the disk-cache owner.
    function updateDoneThreadState(state) {
        diskCache.updateDoneThreadState(state);
    }

    // -- Persistence ----------------------------------------------------------

    // Publish a new message snapshot without treating local edits as successful remote refreshes.
    function updateMessages(items, fetchedAt) {
        diskCache.updateMessages(items, fetchedAt);
    }

    visible: false

    // -- Sub-components -------------------------------------------------------
    PluginCache {
        id: diskCache

        cacheWorkerEnabled: coordinator.cacheWorkersEnabled
        pollIntervalMs: coordinator.pollIntervalMs
        providerApi: coordinator.providerApi

        onAvatarDownloadFinished: function (login, localUrl, generation, success) {
            avatarWorker.onAvatarDownloadFinished(login, localUrl, generation, success);
        }
        onAvatarDownloadsRequested: function (items) {
            avatarWorker.batchQueueAvatarDownloads(items);
        }
        onCacheFailure: function (message) {
            coordinator.cacheFailure(message);
        }
        onCacheReady: coordinator.cacheReady()
    }
    AvatarBackgroundWorker {
        id: avatarWorker

        avatarLocalPaths: diskCache.avatarLocalPaths
        cacheReady: diskCache.initialized

        onAvatarDownloadRequested: function (login, remoteUrl, generation) {
            diskCache.downloadAvatar(login, remoteUrl, generation);
        }
        onAvatarDownloaded: function (login, localUrl, nextAvatarLocalPaths) {
            diskCache.updateAvatarLocalPath(login, localUrl);
            coordinator.avatarCachedLocally(login, localUrl);
        }
    }
    Connections {
        // Refresh the downloader's known local paths when the disk cache publishes a new map.
        function onAvatarLocalPathsChanged() {
            avatarWorker.setAvatarLocalPaths(diskCache.avatarLocalPaths);
        }

        target: diskCache
    }
}
