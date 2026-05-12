// ResourceRepository.qml - central resource request and delivery batching.
//
// Provides one place for runtime code to request avatar resources. The backing
// cache/worker ownership stays in CacheCoordinator; this layer keeps request
// call sites consistent and coalesces resource-ready UI notifications.

import QtQuick
import ".."

Item {
    id: repository
    visible: false

    property var cacheCoordinator: null
    property var _pendingAvatarUpdates: ({})

    signal avatarResourcesReady(var updates)

    function _profile(label, startMs, details) {
        if (!GitHubConstants.profileLoggingEnabled)
            return
        var duration = Date.now() - startMs
        if (!GitHubConstants.profileLogAllOperations
                && duration < GitHubConstants.profileSlowOperationThresholdMs)
            return
        var suffix = details ? (" — " + details) : ""
        console.warn("[GitHubInbox PROFILE] ResourceRepository." + label
                     + " took " + duration + "ms" + suffix)
    }

    function requestMessageAvatars(items) {
        var profileStart = Date.now()
        if (!cacheCoordinator || !items || items.length === 0)
            return
        cacheCoordinator.resolveMessageAvatars(items)
        _profile("requestMessageAvatars", profileStart, "items=" + items.length)
    }

    function requestAuthorAvatars(authors) {
        var profileStart = Date.now()
        if (!cacheCoordinator || !authors || authors.length === 0)
            return
        cacheCoordinator.resolveAuthorAvatars(authors)
        _profile("requestAuthorAvatars", profileStart, "authors=" + authors.length)
    }

    function notifyAvatarCached(login, localUrl) {
        if (!login || !localUrl)
            return

        var next = _cloneMap(_pendingAvatarUpdates)
        next[login] = localUrl
        _pendingAvatarUpdates = next

        if (!avatarReadyFlushTimer.running)
            avatarReadyFlushTimer.restart()
    }

    Timer {
        id: avatarReadyFlushTimer
        interval: GitHubConstants.resourceReadyFlushIntervalMs
        repeat: false
        onTriggered: repository._flushAvatarUpdates()
    }

    Connections {
        target: repository.cacheCoordinator
        function onAvatarCachedLocally(login, localUrl) {
            repository.notifyAvatarCached(login, localUrl)
        }
    }

    function _flushAvatarUpdates() {
        var profileStart = Date.now()
        var updates = _pendingAvatarUpdates || ({})
        if (Object.keys(updates).length === 0)
            return

        _pendingAvatarUpdates = ({})
        avatarResourcesReady(updates)
        _profile("_flushAvatarUpdates", profileStart,
                 "updates=" + Object.keys(updates).length)
    }

    function _cloneMap(source) {
        var copy = {}
        for (var key in source)
            copy[key] = source[key]
        return copy
    }
}
