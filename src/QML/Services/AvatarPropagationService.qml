// AvatarPropagationService.qml - batches local avatar updates by account login.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: service

    property bool automaticProcessing: true
    property int batchSize: GitHubConstants.localAvatarPropagationBatchSize
    property int delayMs: GitHubConstants.localAvatarPropagationDelayMs
    readonly property int pendingCount: Object.keys(pendingUpdates).length
    property var pendingUpdates: ({})

    signal batchReady(var updates)

    // Apply only one configured propagation batch per UI turn.
    function processBatch() {
        let batch = {};
        let remaining = {};
        let processed = 0;
        for (let login in pendingUpdates) {
            if (processed >= Math.max(1, batchSize)) {
                remaining[login] = pendingUpdates[login];
                continue;
            }
            batch[login] = pendingUpdates[login];
            processed++;
        }
        pendingUpdates = remaining;
        if (Object.keys(batch).length > 0)
            batchReady(batch);
        if (automaticProcessing && pendingCount > 0)
            applyTimer.restart();
        return batch;
    }
    // Coalesce pending work before its owning timer or bounded processor runs.
    function queue(login, localUrl) {
        let normalizedLogin = String(login || "").trim();
        let normalizedUrl = String(localUrl || "");
        if (!normalizedLogin || !normalizedUrl)
            return;
        let updates = {};
        for (let existingLogin in pendingUpdates)
            updates[existingLogin] = pendingUpdates[existingLogin];
        updates[normalizedLogin] = normalizedUrl;
        pendingUpdates = updates;
        if (automaticProcessing)
            applyTimer.restart();
    }
    // Restore idle state and invalidate work belonging to an obsolete generation.
    function reset() {
        applyTimer.stop();
        pendingUpdates = ({});
    }

    Timer {
        id: applyTimer

        interval: service.delayMs
        repeat: false
        running: service.automaticProcessing && service.pendingCount > 0

        onTriggered: service.processBatch()
    }
}
