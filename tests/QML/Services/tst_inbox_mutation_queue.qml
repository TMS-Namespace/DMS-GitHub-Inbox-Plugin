// tst_inbox_mutation_queue.qml - tests distinct queue ordering and reset behavior.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    function init() {
        queue.reset();
    }
    function test_compactionAndRequeueKeepPendingOrder() {
        let threads = [];
        for (let index = 0; index < 40; index++)
            threads.push(String(index));
        queue.enqueueDone(threads);
        for (let index = 0; index < 33; index++)
            compare(queue.takeDone(), String(index));
        queue.enqueueDone(["1", "39", "40"]);
        for (let index = 33; index < 40; index++)
            compare(queue.takeDone(), String(index));
        compare(queue.takeDone(), "1");
        compare(queue.takeDone(), "40");
        verify(!queue.hasPending);
    }
    function test_distinctRequestsKeepIndependentOrder() {
        queue.enqueueDone(["a", "b", "a", ""]);
        queue.enqueueDone(["b", "c"]);
        queue.enqueueRead(["b", "b", "a"]);
        verify(queue.hasPending);
        compare(queue.takeRead(), "b");
        compare(queue.takeDone(), "a");
        compare(queue.takeDone(), "b");
        compare(queue.takeRead(), "a");
        compare(queue.takeDone(), "c");
        compare(queue.takeRead(), "");
        compare(queue.takeDone(), "");
        verify(!queue.hasPending);
    }
    function test_resetDiscardsBothQueues() {
        queue.enqueueDone(["a"]);
        queue.enqueueRead(["b"]);
        queue.reset();
        verify(!queue.hasPending);
        compare(queue.takeDone(), "");
        compare(queue.takeRead(), "");
    }

    name: "InboxMutationQueue"

    InboxMutationQueue {
        id: queue
    }
}
