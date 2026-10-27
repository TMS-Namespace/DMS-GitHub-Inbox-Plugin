// ResourceRepository.qml - central resource request and delivery batching.
//
// Provides one place for runtime code to request avatar resources. The backing
// cache/worker ownership stays in CacheCoordinator; this layer keeps request
// call sites consistent and coalesces resource-ready UI notifications.

import QtQuick
import ".."

Item {
    id: repository

    property int _pendingAvatarUpdateCount: 0
    property var _pendingAvatarUpdates: ({})
    property var cacheCoordinator: null

    signal avatarResourcesReady(var updates)

    // Deliver one coalesced resource batch instead of notifying each image separately.
    function _flushAvatarUpdates() {
        let profileStart = Date.now();
        let updates = _pendingAvatarUpdates || ({});
        let updateCount = _pendingAvatarUpdateCount;
        if (updateCount === 0)
            return;
        _pendingAvatarUpdates = ({});
        _pendingAvatarUpdateCount = 0;
        avatarResourcesReady(updates);
        _profile("_flushAvatarUpdates", profileStart, "updates=" + updateCount);
    }
    // Measure this operation through the shared profiling gate.
    function _profile(label, startMs, details) {
        let duration = Date.now() - startMs;
        PluginLogger.profile("ResourceRepository", label, duration, details);
    }
    // Coalesce ready resources by login before notifying the UI.
    function notifyAvatarCached(login, localUrl) {
        if (!login || !localUrl)
            return;
        if (!_pendingAvatarUpdates.hasOwnProperty(login))
            _pendingAvatarUpdateCount++;
        _pendingAvatarUpdates[login] = localUrl;

        if (!avatarReadyFlushTimer.running)
            avatarReadyFlushTimer.restart();
    }
    // Delegate author resources to the owning cache and download queue.
    function requestAuthorAvatars(authors) {
        let profileStart = Date.now();
        if (!cacheCoordinator || !authors || authors.length === 0)
            return;
        cacheCoordinator.resolveAuthorAvatars(authors);
        _profile("requestAuthorAvatars", profileStart, "authors=" + authors.length);
    }
    // Delegate repository resources to the owning cache and download queue.
    function requestMessageAvatars(items) {
        let profileStart = Date.now();
        if (!cacheCoordinator || !items || items.length === 0)
            return;
        cacheCoordinator.resolveMessageAvatars(items);
        _profile("requestMessageAvatars", profileStart, "items=" + items.length);
    }

    visible: false

    Timer {
        id: avatarReadyFlushTimer

        interval: GitHubConstants.resourceReadyFlushIntervalMs
        repeat: false

        onTriggered: repository._flushAvatarUpdates()
    }
    Connections {
        // Batch the cache coordinator's completed avatar paths for resource consumers.
        function onAvatarCachedLocally(login, localUrl) {
            repository.notifyAvatarCached(login, localUrl);
        }

        target: repository.cacheCoordinator
    }
}
