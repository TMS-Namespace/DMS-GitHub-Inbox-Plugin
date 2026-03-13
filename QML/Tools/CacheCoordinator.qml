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

    function initialize() {
        diskCache.initialize()
    }

    function isFresh() {
        return diskCache.isFresh()
    }

    // -- Load cached data into runtime structures -----------------------------

    /// Returns { messages, authorsByThread, authorFetchedAt, timestamp }
    function loadCachedState() {
        return {
            messages: diskCache.cachedMessages || [],
            authorsByThread: diskCache.cachedAuthorsByThread || ({}),
            authorFetchedAt: diskCache.cachedAuthorFetchedAt || ({}),
            timestamp: diskCache.cachedTimestamp || 0
        }
    }

    // -- Avatar resolution ----------------------------------------------------

    function resolveMessageAvatars(items) {
        if (!diskCache.initialized) return
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            var login = (item.repositoryOwnerLogin || "").trim()
            if (login && item.repositoryOwnerAvatarUrl) {
                var resolved = diskCache.resolveAvatarUrl(item.repositoryOwnerAvatarUrl, login)
                if (resolved !== item.repositoryOwnerAvatarUrl)
                    item.repositoryOwnerAvatarUrl = resolved
                else
                    diskCache.queueAvatarDownload(login, item.repositoryOwnerAvatarUrl)
            }
        }
    }

    function resolveAuthorAvatars(authors) {
        if (!diskCache.initialized) return
        for (var i = 0; i < authors.length; i++) {
            var author = authors[i]
            var login = (author.login || "").trim()
            if (login && author.avatarUrl) {
                var resolved = diskCache.resolveAvatarUrl(author.avatarUrl, login)
                if (resolved !== author.avatarUrl)
                    author.avatarUrl = resolved
                else
                    diskCache.queueAvatarDownload(login, author.avatarUrl)
            }
        }
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
