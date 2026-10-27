// InboxMutationQueue.qml - holds distinct read and Done requests until the mutation service is idle.

import QtQuick

QtObject {
    id: queue

    property int doneIndex: 0
    property var doneThreads: []
    readonly property bool hasPending: doneIndex < doneThreads.length || readIndex < readThreads.length
    property int readIndex: 0
    property var readThreads: []

    // Append IDs once per queue, retaining the order in which they were requested.
    function appendDistinct(current, startIndex, threadIds) {
        let next = current.slice(startIndex);
        let seen = {};
        for (let index = 0; index < next.length; index++)
            seen[next[index]] = true;
        for (let index = 0; index < (threadIds || []).length; index++) {
            let threadId = threadIds[index];
            if (!threadId || seen[threadId])
                continue;
            seen[threadId] = true;
            next.push(threadId);
        }
        return next;
    }
    // Queue remote Done operations without changing read-request order.
    function enqueueDone(threadIds) {
        doneThreads = appendDistinct(doneThreads, doneIndex, threadIds);
        doneIndex = 0;
    }
    // Queue remote read operations without changing Done-request order.
    function enqueueRead(threadIds) {
        readThreads = appendDistinct(readThreads, readIndex, threadIds);
        readIndex = 0;
    }
    // Drop queued requests when their owning widget state is reset.
    function reset() {
        doneThreads = [];
        readThreads = [];
        doneIndex = 0;
        readIndex = 0;
    }
    // Remove and return the oldest queued Done thread, or an empty string.
    function takeDone() {
        if (doneIndex >= doneThreads.length)
            return "";
        let threadId = doneThreads[doneIndex++];
        if (doneIndex >= doneThreads.length || doneIndex >= 32) {
            doneThreads = doneThreads.slice(doneIndex);
            doneIndex = 0;
        }
        return threadId;
    }
    // Remove and return the oldest queued read thread, or an empty string.
    function takeRead() {
        if (readIndex >= readThreads.length)
            return "";
        let threadId = readThreads[readIndex++];
        if (readIndex >= readThreads.length || readIndex >= 32) {
            readThreads = readThreads.slice(readIndex);
            readIndex = 0;
        }
        return threadId;
    }
}
