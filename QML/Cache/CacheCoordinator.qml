// CacheCoordinator.qml - Bridges disk cache with runtime state
//
// Owns the PluginCache and avatar downloader, and provides high-level operations:
// resolving avatar URLs, loading cached state, persisting updates, and
// handling clear-cache requests from the settings panel.

import QtQuick
import ".."

Item {
    id: coordinator
    visible: false

    // -- Configuration --------------------------------------------------------
    property int cacheTtlMinutes: GitHubConstants.defaultCacheTtlMinutes

    // -- Sub-components -------------------------------------------------------
    PluginCache {
        id: diskCache
        cacheTtlMinutes: coordinator.cacheTtlMinutes

        onCacheReady: coordinator.cacheReady()
        onAvatarDownloadsRequested: function(items) {
            avatarWorker.batchQueueAvatarDownloads(items)
        }
    }

    AvatarBackgroundWorker {
        id: avatarWorker
        cacheDir: diskCache.cacheDir
        avatarLocalPaths: diskCache.avatarLocalPaths

        onAvatarDownloaded: function(login, localUrl, nextAvatarLocalPaths) {
            diskCache.updateAvatarLocalPaths(nextAvatarLocalPaths)
            coordinator.avatarCachedLocally(login, localUrl)
        }
    }

    Connections {
        target: diskCache
        function onAvatarLocalPathsChanged() {
            avatarWorker.setAvatarLocalPaths(diskCache.avatarLocalPaths)
        }
    }

    CachedState {
        id: cachedStateModel
    }

    // -- Exposed state --------------------------------------------------------
    readonly property bool initialized: diskCache.initialized
    readonly property bool isDownloadingAvatars: avatarWorker.isBusy

    // -- Signals --------------------------------------------------------------
    signal cacheReady()
    signal avatarCachedLocally(string login, string localUrl)

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        if (!GitHubConstants.debugPerformanceLogging) return
        console.warn("[GitHubInbox PERF] CacheCoord: " + label)
    }

    function _profile(label, startMs, details) {
        if (!GitHubConstants.profileLoggingEnabled)
            return
        var duration = Date.now() - startMs
        if (!GitHubConstants.profileLogAllOperations
                && duration < GitHubConstants.profileSlowOperationThresholdMs)
            return
        var suffix = details ? (" — " + details) : ""
        console.warn("[GitHubInbox PROFILE] CacheCoord." + label
                     + " took " + duration + "ms" + suffix)
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
        var profileStart = Date.now()
        _perfLog("loadCachedState")
        cachedStateModel.readFromObject({
            messages: diskCache.cachedMessages || [],
            authorsByThread: diskCache.cachedAuthorsByThread || ({}),
            authorFetchedAt: diskCache.cachedAuthorFetchedAt || ({}),
            timestamp: diskCache.cachedTimestamp || 0
        })
        var result = cachedStateModel.toObject()
        _profile("loadCachedState", profileStart, "messages=" + result.messages.length)
        return result
    }

    // -- Avatar resolution ----------------------------------------------------

    function resolveMessageAvatars(items) {
        var profileStart = Date.now()
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
            avatarWorker.batchQueueAvatarDownloads(downloads)
        _profile("resolveMessageAvatars", profileStart,
                 "items=" + (items ? items.length : 0) + " downloads=" + downloads.length)
    }

    function resolveAuthorAvatars(authors) {
        var profileStart = Date.now()
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
            avatarWorker.batchQueueAvatarDownloads(downloads)
        _profile("resolveAuthorAvatars", profileStart,
                 "authors=" + (authors ? authors.length : 0) + " downloads=" + downloads.length)
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
        return GitHubConstants.githubAvatarsBaseUrl + "/" + encodeURIComponent(login)
               + "?size=" + GitHubConstants.avatarDefaultSizePx
    }

    // -- Persistence ----------------------------------------------------------

    function updateMessages(items) {
        diskCache.updateMessages(items)
    }

    function bulkUpdateAuthors(authorsMap) {
        diskCache.bulkUpdateAuthors(authorsMap)
    }

    function updateAuthors(threadId, authors) {
        diskCache.updateAuthors(threadId, authors)
    }

    function updateChangedAuthors(changedAuthorsByThread) {
        diskCache.updateChangedAuthors(changedAuthorsByThread)
    }

    function updateAuthorFetchedAt(threadId, updatedAt) {
        diskCache.updateAuthorFetchedAt(threadId, updatedAt)
    }

    function pruneToThreads(keepIds) {
        diskCache.pruneToThreads(keepIds)
    }

    function clearCache() {
        avatarWorker.reset()
        diskCache.clearCache()
    }

    // -- Settings clear-cache flag handling -----------------------------------

    function handleClearCacheRequest(pluginData, pluginService) {
        var flag = (pluginData.clearCacheRequested || "").trim().toLowerCase()
        if (flag === "true" || flag === "1") {
            diskCache.clearCache()
            if (pluginService)
                pluginService.savePluginData(GitHubConstants.pluginNamespaceId, "clearCacheRequested", "")
        }
    }
}
