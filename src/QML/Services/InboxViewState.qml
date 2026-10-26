// InboxViewState.qml - batches rendered inbox updates while the popout is visible.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: state

    property bool automaticProcessing: true
    property int chunkSize: GitHubConstants.viewApplyChunkSize
    readonly property bool isApplying: applyTimer.running
    property var messagesForView: []
    readonly property int pendingCount: pendingMessages.length
    property var pendingMessages: []
    property bool popoutVisible: false
    property var sourceMessages: []

    signal settled

    // Append visible work without restarting a batch that is already being applied.
    function append(items) {
        let additions = items || [];
        if (!popoutVisible || additions.length === 0)
            return;
        pendingMessages = pendingMessages.concat(additions);
        if (automaticProcessing && !applyTimer.running)
            applyTimer.restart();
    }
    // Apply at most one configured UI batch before yielding to the event loop.
    function applyChunk() {
        if (pendingCount === 0) {
            applyTimer.stop();
            return;
        }
        let count = Math.min(Math.max(1, chunkSize), pendingCount);
        messagesForView = messagesForView.concat(pendingMessages.slice(0, count));
        pendingMessages = pendingMessages.slice(count);
        if (pendingCount === 0) {
            applyTimer.stop();
            settled();
        }
    }
    // Coalesce pending work before its owning timer or bounded processor runs.
    function queue(items) {
        if (!popoutVisible) {
            pendingMessages = [];
            applyTimer.stop();
            return;
        }
        pendingMessages = (items || []).slice(0);
        messagesForView = [];
        if (pendingCount > 0 && automaticProcessing)
            applyTimer.restart();
        else
            applyTimer.stop();
    }
    // Replace the rendered snapshot only after the service has received visible popup state.
    function replace(items) {
        pendingMessages = [];
        applyTimer.stop();
        if (popoutVisible)
            messagesForView = (items || []).slice(0);
    }
    // Restore idle state and invalidate work belonging to an obsolete generation.
    function reset() {
        pendingMessages = [];
        messagesForView = [];
        applyTimer.stop();
    }
    // Publish an already reconciled snapshot without restarting queued fetch work.
    function updateRendered(items) {
        messagesForView = (items || []).slice(0);
    }

    // Refresh only after this service has received the host's new visibility state.
    onPopoutVisibleChanged: {
        if (popoutVisible)
            replace(sourceMessages);
    }

    Timer {
        id: applyTimer

        interval: GitHubConstants.viewApplyTimerIntervalMs
        repeat: true
        running: state.automaticProcessing && state.pendingCount > 0

        onTriggered: state.applyChunk()
    }
}
