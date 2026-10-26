// InboxRefreshCoordinator.qml - refresh gating and stale-work recovery.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: coordinator

    property var authorWorker: null
    property bool automaticScheduling: true
    property var cacheCoordinator: null
    property var enrichmentService: null
    property var fetchService: null
    property bool isRefreshBusy: false
    property real operationBusySinceMs: 0
    property var operations: null
    property int pollIntervalMs: GitHubManager.properties.defaultPollIntervalSeconds * 1000
    property bool popoutVisible: false
    property bool refreshAfterPopoutClose: false
    property real refreshBusySinceMs: 0
    property int scheduledDelayMs: 0
    property string token: ""

    signal missingTokenRequested
    signal staleWorkRecovered

    // Describe queue and activity state without including request URLs or secrets.
    function busyDetails() {
        return "fetchLoading=" + fetchService.isLoading + " authorBusy=" + authorWorker.isBusy + " avatarBusy=" + cacheCoordinator.isDownloadingAvatars + " operationsBusy=" + operations.isBusy + " authorQueue=" + authorWorker.requestQueue.length + " authorInFlight=" + authorWorker.requestsInFlight;
    }
    // Treat a busy operation without a valid start time as stale rather than blocking forever.
    function busyDurationMs(isBusy, sinceMs) {
        if (!isBusy)
            return 0;
        if (sinceMs > 0)
            return Math.max(0, Date.now() - sinceMs);
        return GitHubConstants.refreshBusyStaleMs + 1;
    }
    // Record the start of the current mutation for stale-work recovery.
    function noteOperationBusyChanged(isBusy) {
        operationBusySinceMs = isBusy ? Date.now() : 0;
    }
    // Record the start of the current refresh for stale-work recovery.
    function noteRefreshBusyChanged(isBusy) {
        refreshBusySinceMs = isBusy ? Date.now() : 0;
    }
    // Invalidate stuck generations before resetting their queues and refreshing again.
    function recoverStaleBackgroundWork(reason, force) {
        if (!isRefreshBusy && !operations.isBusy)
            return false;

        let refreshBusyMs = busyDurationMs(isRefreshBusy, refreshBusySinceMs);
        let operationBusyMs = busyDurationMs(operations.isBusy, operationBusySinceMs);
        let stale = !!force || refreshBusyMs >= GitHubConstants.refreshBusyStaleMs || operationBusyMs >= GitHubConstants.refreshBusyStaleMs;
        if (!stale)
            return false;

        PluginLogger.error("refresh", "Recovering stale background work after " + reason + " refreshBusyMs=" + refreshBusyMs + " operationBusyMs=" + operationBusyMs + " " + busyDetails());
        fetchService.cancel();
        authorWorker.resetState();
        cacheCoordinator.resetAvatarDownloads();
        operations.resetState(false);
        enrichmentService.cancelBackgroundEnrichment();
        enrichmentService.cancelPendingScans();
        refreshBusySinceMs = 0;
        operationBusySinceMs = 0;
        staleWorkRecovered();
        return true;
    }
    // Bypass the cached startup delay for an explicit refresh, subject to active-work guards.
    function refreshNow() {
        if (!token) {
            missingTokenRequested();
            return;
        }
        recoverStaleBackgroundWork("manual refresh", false);
        requestFetch(true);
    }
    // Gate background requests on token availability, busy work and popup visibility.
    function requestFetch(allowWhilePopout) {
        recoverStaleBackgroundWork("refresh guard", false);
        if (!token)
            return;
        if (operations.isBusy || isRefreshBusy) {
            scheduleNextPoll();
            PluginLogger.debug("refresh", "Skipped because work is still busy: " + busyDetails());
            return;
        }
        if (popoutVisible && !allowWhilePopout) {
            pollTimer.stop();
            refreshAfterPopoutClose = true;
            PluginLogger.debug("refresh", "Deferred until popup closes");
            return;
        }
        fetchService.fetch(!!allowWhilePopout);
        scheduleNextPoll();
    }

    // Only matching, nonfuture cache timestamps can postpone the first request.
    function restoreSchedule(timestamp, savedIntervalMs, nowMs) {
        let now = nowMs === undefined ? Date.now() : nowMs;
        let valid = Number.isFinite(timestamp) && timestamp > 0 && timestamp <= now && savedIntervalMs === pollIntervalMs;
        let remaining = valid ? pollIntervalMs - (now - timestamp) : 0;
        if (remaining > 0)
            scheduleNextPoll(remaining);
        else
            requestFetch(false);
    }
    // Consume the deferred refresh flag once so closing a popup cannot schedule duplicates.
    function resumeAfterPopoutClose() {
        if (!refreshAfterPopoutClose)
            return false;
        refreshAfterPopoutClose = false;
        return true;
    }
    // One timer owns both restored startup delays and subsequent polling.
    function scheduleNextPoll(delayMs) {
        scheduledDelayMs = delayMs === undefined ? pollIntervalMs : Math.max(1, Math.ceil(delayMs));
        if (automaticScheduling && token)
            pollTimer.restart();
    }

    onPollIntervalMsChanged: {
        if (pollTimer.running)
            scheduleNextPoll();
    }
    onTokenChanged: {
        if (!token) {
            pollTimer.stop();
            scheduledDelayMs = 0;
        }
    }

    Timer {
        id: pollTimer

        interval: Math.max(1, coordinator.scheduledDelayMs)
        repeat: false

        onTriggered: coordinator.requestFetch(false)
    }
}
