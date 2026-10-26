// InboxFetchService.qml - owns inbox polling requests and accumulates worker chunks.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: service

    property bool activeFetchWasManual: false
    readonly property bool isLoading: worker.isLoading
    readonly property bool lastFetchWasComplete: worker.lastFetchWasComplete
    property bool parserWorkerEnabled: true
    property var pendingMessages: []
    property int pendingUnreadCount: 0
    property var providerApi: null
    property real targetOldestVisibleUpdatedAtMs: 0
    property string token: ""

    signal authorResultReceived(var message)
    signal fetchBegan(int totalCount, int unreadCount)
    signal fetchFailed(string errorMessage, bool wasManual)
    signal fetchResultReady(var items, int unreadCount, bool complete)

    // Invalidate pending generations so obsolete responses cannot enter current state.
    function cancel() {
        worker.cancel();
        pendingMessages = [];
        pendingUnreadCount = 0;
        activeFetchWasManual = false;
    }
    // Start a bounded request cycle using the currently configured provider facade.
    function fetch(wasManual) {
        activeFetchWasManual = !!wasManual;
        worker.fetch();
    }
    // Consume one deferred request after the current generation has finished.
    function retryIfQueued() {
        worker.retryIfQueued();
    }
    // Forward parsing work through the existing background worker.
    function sendWorkerMessage(message) {
        worker.sendWorkerMessage(message);
    }
    // Deliver one complete buffered result and clear its transient request state.
    function takePendingResult(complete) {
        let items = pendingMessages;
        let unread = pendingUnreadCount;
        pendingMessages = [];
        pendingUnreadCount = 0;
        activeFetchWasManual = false;
        fetchResultReady(items, unread, complete);
    }

    InboxBackgroundWorker {
        id: worker

        parserWorkerEnabled: service.parserWorkerEnabled
        providerApi: service.providerApi
        targetOldestVisibleUpdatedAtMs: service.targetOldestVisibleUpdatedAtMs
        token: service.token

        onAuthorResultReceived: function (message) {
            service.authorResultReceived(message);
        }
        onFetchBegin: function (totalCount, unreadCount) {
            service.pendingMessages = [];
            service.pendingUnreadCount = unreadCount;
            service.fetchBegan(totalCount, unreadCount);
        }
        onFetchChunk: function (chunk, isLast) {
            let nextMessages = service.pendingMessages.slice(0);
            for (let index = 0; index < chunk.length; index++)
                nextMessages.push(chunk[index]);
            service.pendingMessages = nextMessages;
            if (isLast)
                service.takePendingResult(worker.lastFetchWasComplete);
        }
        onFetchComplete: function (items, unreadCount) {
            service.pendingUnreadCount = unreadCount;
            service.pendingMessages = items || [];
            service.takePendingResult(worker.lastFetchWasComplete);
        }
        onFetchError: function (errorMessage) {
            let wasManual = service.activeFetchWasManual;
            service.pendingMessages = [];
            service.pendingUnreadCount = 0;
            service.activeFetchWasManual = false;
            service.fetchFailed(errorMessage, wasManual);
        }
    }
}
