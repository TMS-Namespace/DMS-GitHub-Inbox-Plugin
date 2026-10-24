// tst_inbox_fetch_service.qml - tests inbox fetch result buffering.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    id: testCase

    property bool receivedComplete: false
    property var receivedItems: []
    property int receivedUnreadCount: -1

    function test_cancelClearsBufferedStateAndManualFlag() {
        fetchService.pendingMessages = [
            {
                threadId: "thread-1"
            }
        ];
        fetchService.pendingUnreadCount = 1;
        fetchService.activeFetchWasManual = true;

        fetchService.cancel();

        compare(fetchService.pendingMessages.length, 0);
        compare(fetchService.pendingUnreadCount, 0);
        compare(fetchService.activeFetchWasManual, false);
    }
    function test_takePendingResultEmitsAndClearsBufferedState() {
        receivedItems = [];
        receivedUnreadCount = -1;
        receivedComplete = false;
        fetchService.pendingMessages = [
            {
                threadId: "thread-1"
            },
            {
                threadId: "thread-2"
            }
        ];
        fetchService.pendingUnreadCount = 1;

        fetchService.takePendingResult(true);

        compare(receivedItems.length, 2);
        compare(receivedItems[0].threadId, "thread-1");
        compare(receivedUnreadCount, 1);
        compare(receivedComplete, true);
        compare(fetchService.pendingMessages.length, 0);
        compare(fetchService.pendingUnreadCount, 0);
    }

    name: "InboxFetchService"

    InboxFetchService {
        id: fetchService

        parserWorkerEnabled: false

        onFetchResultReady: function (items, unreadCount, complete) {
            testCase.receivedItems = items;
            testCase.receivedUnreadCount = unreadCount;
            testCase.receivedComplete = complete;
        }
    }
}
