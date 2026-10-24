// tst_inbox_view_state.qml - tests deferred rendered-message updates.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    function test_queueAndChunkAppendMessagesInOrder() {
        viewState.popoutVisible = true;
        viewState.queue([
            {
                threadId: "a"
            },
            {
                threadId: "b"
            },
            {
                threadId: "c"
            }
        ]);

        compare(viewState.messagesForView.length, 0);
        compare(viewState.pendingCount, 3);
        viewState.applyChunk();
        compare(viewState.messagesForView.length, 2);
        compare(viewState.messagesForView[0].threadId, "a");
        compare(viewState.pendingCount, 1);
        viewState.applyChunk();
        compare(viewState.messagesForView[2].threadId, "c");
        compare(viewState.pendingCount, 0);
        verify(!viewState.isApplying);
    }
    function test_queueWhileHiddenDropsPendingButKeepsCurrentRender() {
        viewState.popoutVisible = true;
        viewState.replace([
            {
                threadId: "visible"
            }
        ]);
        viewState.popoutVisible = false;
        viewState.queue([
            {
                threadId: "deferred"
            }
        ]);

        compare(viewState.messagesForView[0].threadId, "visible");
        compare(viewState.pendingCount, 0);
    }

    name: "InboxViewState"

    InboxViewState {
        id: viewState

        automaticProcessing: false
        chunkSize: 2
    }
}
