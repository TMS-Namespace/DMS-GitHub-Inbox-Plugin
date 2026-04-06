// CacheCoordinator.qml - Bridges disk cache with runtime state
//
// Owns the InboxCache instance and provides high-level operations:
// resolving avatar URLs, loading cached state, persisting updates, and
// handling clear-cache requests from the settings panel.

import QtQuick

Item {
    id: coordinator
    visible: false

    // -- Configuration --------------------------------------------------------
    property int cacheTtlMinutes: Constants.defaultCacheTtlMinutes

    // -- Sub-components -------------------------------------------------------
    InboxCache {
        id: diskCache
        cacheTtlMinutes: coordinator.cacheTtlMinutes

        onCacheReady: coordinator.cacheReady()
        onAvatarDownloaded: function(login, localUrl) {
            coordinator.avatarCachedLocally(login, localUrl)
        }
    }

    // -- Exposed state --------------------------------------------------------
    readonly property bool initialized: diskCache.initialized
    readonly property bool isDownloadingAvatars: diskCache.isDownloadingAvatars

    // -- Signals --------------------------------------------------------------
    signal cacheReady()
    signal avatarCachedLocally(string login, string localUrl)

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        if (!Constants.debugPerformanceLogging) return
        console.warn("[GitHubInbox PERF] CacheCoord: " + label)
    }

    function initialize() {
        _perfLog("initialize")
        diskCache.initialize()
    }

    function isFresh() {
        return diskCache.isFresh()
    }

    // -- Load cached data into runtime structures -----------------------------

    /// Returns { messages, authorsByThread, authorFetchedAt, timestamp }
    function loadCachedState() {
        _perfLog("loadCachedState")
        return {
            messages: diskCache.cachedMessages || [],
            authorsByThread: diskCache.cachedAuthorsByThread || ({}),
            authorFetchedAt: diskCache.cachedAuthorFetchedAt || ({}),
            timestamp: diskCache.cachedTimestamp || 0
        }
    }

    // -- Avatar resolution ----------------------------------------------------

    function resolveMessageAvatars(items) {
        _perfLog("resolveMessageAvatars — count=" + (items ? items.length : 0))
        if (!diskCache.initialized) return
        var downloads = []
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            var login = (item.repositoryOwnerLogin || "").trim()
            if (!login || !item.repositoryOwnerAvatarUrl)
                continue

            var currentUrl = item.repositoryOwnerAvatarUrl
            // Fix stale file:// URLs whose files have been removed from disk
            if (_isStaleLocalUrl(currentUrl, login))
                currentUrl = _remoteAvatarUrl(login)

            var resolved = diskCache.resolveAvatarUrl(currentUrl, login)
            if (resolved !== currentUrl)
                item.repositoryOwnerAvatarUrl = resolved
            else if (!_isLocalUrl(resolved)) {
                item.repositoryOwnerAvatarUrl = resolved
                downloads.push({ login: login, remoteUrl: resolved })
            } else
                item.repositoryOwnerAvatarUrl = resolved
        }
        if (downloads.length > 0)
            diskCache.batchQueueAvatarDownloads(downloads)
    }

    function resolveAuthorAvatars(authors) {
        _perfLog("resolveAuthorAvatars — count=" + (authors ? authors.length : 0))
        if (!diskCache.initialized) return
        var downloads = []
        for (var i = 0; i < authors.length; i++) {
            var author = authors[i]
            var login = (author.login || "").trim()
            if (!login || !author.avatarUrl)
                continue

            var currentUrl = author.avatarUrl
            // Fix stale file:// URLs whose files have been removed from disk
            if (_isStaleLocalUrl(currentUrl, login))
                currentUrl = _remoteAvatarUrl(login)

            var resolved = diskCache.resolveAvatarUrl(currentUrl, login)
            if (resolved !== currentUrl)
                author.avatarUrl = resolved
            else if (!_isLocalUrl(resolved)) {
                author.avatarUrl = resolved
                downloads.push({ login: login, remoteUrl: resolved })
            } else
                author.avatarUrl = resolved
        }
        if (downloads.length > 0)
            diskCache.batchQueueAvatarDownloads(downloads)
    }

    /// Returns true if url is a file:// URL
    function _isLocalUrl(url) {
        return url && String(url).indexOf("file://") === 0
    }

    /// Returns true if url is a file:// URL but the login is NOT in avatarLocalPaths
    function _isStaleLocalUrl(url, login) {
        return _isLocalUrl(url) && !diskCache.hasLocalAvatar(login)
    }

    /// Construct a fresh remote avatar URL from a login
    function _remoteAvatarUrl(login) {
        return Constants.githubAvatarsBaseUrl + "/" + encodeURIComponent(login)
               + "?size=" + Constants.avatarDefaultSizePx
    }

    // -- Persistence ----------------------------------------------------------

    function updateMessages(items) {
        diskCache.updateMessages(items)
    }

    function bulkUpdateAuthors(authorsMap) {
        diskCache.bulkUpdateAuthors(authorsMap)
    }

    function updateAuthorFetchedAt(threadId, updatedAt) {
        diskCache.updateAuthorFetchedAt(threadId, updatedAt)
    }

    function pruneToThreads(keepIds) {
        diskCache.pruneToThreads(keepIds)
    }

    function clearCache() {
        diskCache.clearCache()
    }

    // -- Settings clear-cache flag handling -----------------------------------

    function handleClearCacheRequest(pluginData, pluginService) {
        var flag = (pluginData.clearCacheRequested || "").trim().toLowerCase()
        if (flag === "true" || flag === "1") {
            diskCache.clearCache()
            if (pluginService)
                pluginService.savePluginData(Constants.pluginNamespaceId, "clearCacheRequested", "")
        }
    }
}
