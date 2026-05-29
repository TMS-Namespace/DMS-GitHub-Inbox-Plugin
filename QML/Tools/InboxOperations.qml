// InboxOperations.qml - Handles GitHub inbox message operations
//
// Encapsulates mark-as-read, mark-as-unread, mark-done, repo-read, and
// mark-all-read operations. Applies optimistic local state updates and
// queues thread-done sync requests.

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: operations
    visible: false

    // -- Configuration --------------------------------------------------------
    property string token: ""

    // -- State ----------------------------------------------------------------
    property bool isOperating: false
    property bool isLoading: false    // bound from outside — blocks operations
    property var doneThreadState: ({})
    property var pendingDoneThreadState: ({})
    property var pendingDoneMessagesByThread: ({})
    property var pendingReadMessagesByThread: ({})
    readonly property var effectiveDoneThreadState: _mergeDoneStates(doneThreadState, pendingDoneThreadState)
    property var pendingThreadDoneQueue: []
    property var pendingThreadReadQueue: []
    property int pendingThreadDoneIndex: 0
    property int pendingThreadReadIndex: 0
    property int operationGeneration: 0
    readonly property bool isBusy: isOperating
                                   || pendingThreadDoneIndex < pendingThreadDoneQueue.length
                                   || pendingThreadReadIndex < pendingThreadReadQueue.length

    // -- Signals --------------------------------------------------------------
    signal operationApplied(string actionType, string threadId, string repositoryFullName, var threadIds)
    signal operationError(string errorMessage)
    signal stateUpdated()

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    function markThreadAsRead(threadId) {
        if (!threadId) return
        if (!_canStartPublicOperation()) return
        _runMutation(
            "PATCH",
            GitHubConstants.githubThreadApiPrefix + threadId,
            "thread_read", threadId, "", ""
        )
    }

    function markThreadReadAfterOpen(threadId) {
        if (!threadId)
            return
        if (!token)
            return
        operationApplied("thread_read_pending", threadId, "", [])
        _queueThreadReadSync([threadId])
    }

    function markThreadAsUnread(threadId) {
        if (!threadId) return
        if (!_canStartPublicOperation()) return
        _runMutation(
            "PATCH",
            GitHubConstants.githubThreadApiPrefix + threadId,
            "thread_unread", threadId, "", "{\"read\":false}"
        )
    }

    function markThreadDone(threadId) {
        if (!threadId) return
        if (!_canStartPublicOperation()) return

        operationApplied("thread_done", threadId, "", [])
        _addPendingDoneThreadIds([threadId])
        _queueThreadDoneSync([threadId])
    }

    function markThreadsAsRead(messages) {
        if (!_canStartPublicOperation())
            return

        var threadIds = _collectThreadIds(messages, true)
        if (threadIds.length === 0)
            return

        operationApplied("threads_read", "", "", threadIds)
        _queueThreadReadSync(threadIds)
    }

    function markThreadsDone(messages) {
        if (!_canStartPublicOperation())
            return

        var threadIds = _collectThreadIds(messages, false)
        if (threadIds.length === 0)
            return

        operationApplied("threads_done", "", "", threadIds)
        _addPendingDoneThreadIds(threadIds)
        _queueThreadDoneSync(threadIds)
    }

    function markRepoDone(repositoryFullName, messages) {
        if (!repositoryFullName) return
        if (!_canStartPublicOperation()) return

        var threadIds = []

        for (var index = 0; index < messages.length; index++) {
            var item = messages[index]
            if (item.repository === repositoryFullName && item.threadId)
                threadIds.push(item.threadId)
        }

        if (threadIds.length === 0) return

        operationApplied("repo_done", "", repositoryFullName, threadIds)
        _addPendingDoneThreadIds(threadIds)
        _queueThreadDoneSync(threadIds)
    }

    function markRepoAsRead(repositoryFullName) {
        if (!repositoryFullName) return
        if (!_canStartPublicOperation()) return

        var parts = repositoryFullName.split("/")
        if (parts.length !== 2) return

        var owner = encodeURIComponent(parts[0])
        var repo = encodeURIComponent(parts[1])
        _runMutation(
            "PUT",
            GitHubConstants.githubApiReposPrefix + owner + "/" + repo + "/notifications",
            "repo_read", "", repositoryFullName, ""
        )
    }

    function markAllAsRead() {
        if (!_canStartPublicOperation()) return

        _runMutation(
            "PUT",
            GitHubConstants.githubInboxApiUrl,
            "all_read", "", "", ""
        )
    }

    function setDoneThreadState(state) {
        doneThreadState = _normalizeDoneThreadState(state)
    }

    function applyPendingReadState(messages) {
        var hasPending = false
        for (var pendingId in pendingReadMessagesByThread) {
            hasPending = true
            break
        }
        if (!hasPending)
            return messages

        var source = messages || []
        var updated = []
        var changed = false
        for (var index = 0; index < source.length; index++) {
            var item = source[index]
            if (item && item.threadId && pendingReadMessagesByThread[item.threadId] && item.unread) {
                updated.push(_markAsReadItem(item))
                changed = true
            } else {
                updated.push(item)
            }
        }
        return changed ? updated : messages
    }

    /// Apply operation result to a messages list and return updated state.
    function applyResult(actionType, threadId, repositoryFullName, messages, threadIds) {
        var updated = []
        var doneCopy = _cloneMap(doneThreadState)
        var pendingCopy = _cloneMap(pendingDoneThreadState)
        var threadIdSet = _threadIdSet(threadIds || [])

        if (actionType === "thread_done_sync") {
            if (threadId) {
                doneCopy[threadId] = true
                delete pendingCopy[threadId]
                doneThreadState = doneCopy
                pendingDoneThreadState = pendingCopy
                _removePendingDoneMessage(threadId)
            }
            return { items: messages, unreadChanged: false }
        }

        if (actionType === "thread_done_revert") {
            delete pendingCopy[threadId]
            pendingDoneThreadState = pendingCopy
            return _restorePendingDoneMessage(threadId, messages)
        }

        if (actionType === "thread_read_sync") {
            _removePendingReadMessage(threadId)
            return { items: messages, unreadChanged: false }
        }

        if (actionType === "thread_read_revert")
            return _restorePendingReadMessage(threadId, messages)

        if (actionType === "all_read") {
            for (var allIndex = 0; allIndex < messages.length; allIndex++)
                updated.push(_markAsReadItem(messages[allIndex]))
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "repo_read") {
            for (var repoIndex = 0; repoIndex < messages.length; repoIndex++) {
                var repoItem = messages[repoIndex]
                if (repoItem.repository === repositoryFullName)
                    updated.push(_markAsReadItem(repoItem))
                else
                    updated.push(repoItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "repo_done") {
            _stashPendingDoneMessages(threadIds, messages)
            for (var repoDoneIndex = 0; repoDoneIndex < messages.length; repoDoneIndex++) {
                var repoDoneItem = messages[repoDoneIndex]
                if (repoDoneItem.repository === repositoryFullName && repoDoneItem.threadId
                        && threadIdSet[repoDoneItem.threadId])
                    continue
                updated.push(repoDoneItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "threads_read") {
            for (var readIndex = 0; readIndex < messages.length; readIndex++) {
                var readItem = messages[readIndex]
                if (readItem.threadId && threadIdSet[readItem.threadId])
                    updated.push(_markAsReadItem(readItem))
                else
                    updated.push(readItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "threads_done") {
            _stashPendingDoneMessages(threadIds, messages)
            for (var batchDoneIndex = 0; batchDoneIndex < messages.length; batchDoneIndex++) {
                var batchDoneItem = messages[batchDoneIndex]
                if (batchDoneItem.threadId && threadIdSet[batchDoneItem.threadId])
                    continue
                updated.push(batchDoneItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "thread_done") {
            _stashPendingDoneMessages([threadId], messages)
            for (var doneIndex = 0; doneIndex < messages.length; doneIndex++) {
                var doneItem = messages[doneIndex]
                if (doneItem.threadId !== threadId)
                    updated.push(doneItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "thread_unread") {
            for (var unreadIndex = 0; unreadIndex < messages.length; unreadIndex++) {
                var unreadItem = messages[unreadIndex]
                if (unreadItem.threadId === threadId) {
                    var unreadCopy = _cloneItem(unreadItem)
                    unreadCopy.unread = true
                    updated.push(unreadCopy)
                } else {
                    updated.push(unreadItem)
                }
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "thread_read_pending")
            _stashPendingReadMessages([threadId], messages)

        // thread_read, thread_read_pending
        for (var index = 0; index < messages.length; index++) {
            var item = messages[index]
            if (item.threadId === threadId)
                updated.push(_markAsReadItem(item))
            else
                updated.push(item)
        }
        return { items: updated, unreadChanged: true }
    }

    function processPendingDoneQueue() {
        if (!token || isOperating || isLoading)
            return
        if (pendingThreadDoneIndex >= pendingThreadDoneQueue.length)
            return

        var threadId = pendingThreadDoneQueue[pendingThreadDoneIndex]
        pendingThreadDoneIndex++
        _compactDoneQueueIfNeeded()

        _runMutation(
            "DELETE",
            GitHubConstants.githubThreadApiPrefix + threadId,
            "thread_done_sync", threadId, "", ""
        )
    }

    function resetState(clearDoneState) {
        operationGeneration = operationGeneration + 1
        isOperating = false
        pendingThreadDoneQueue = []
        pendingThreadReadQueue = []
        pendingDoneThreadState = ({})
        pendingDoneMessagesByThread = ({})
        pendingReadMessagesByThread = ({})
        pendingThreadDoneIndex = 0
        pendingThreadReadIndex = 0
        if (clearDoneState === undefined || clearDoneState)
            doneThreadState = ({})
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    function _runMutation(method, url, actionType, threadId, repositoryFullName, payloadJson) {
        if (!token || isOperating || isLoading)
            return

        isOperating = true

        var process = operationComponentDef.createObject(operations, {
            actionType: actionType || "thread_read",
            threadId: threadId || "",
            repositoryFullName: repositoryFullName || "",
            generation: operationGeneration
        })

        var cmd = [
            "curl", "-sS",
            "-o", "/dev/null",
            "-w", GitHubConstants.curlStatusCodeFormat,
            "--connect-timeout", GitHubConstants.curlConnectTimeoutSeconds,
            "--max-time", GitHubConstants.curlMaxTimeSeconds,
            "-X", method,
            "-H", "Accept: " + GitHubConstants.httpAcceptHeader,
            "-H", "X-GitHub-Api-Version: " + GitHubConstants.githubApiVersionHeader,
            "-H", "Authorization: token " + token,
            url
        ]
        if (payloadJson)
            cmd.splice(cmd.length - 1, 0, "-H", "Content-Type: application/json", "-d", payloadJson)

        ApiCallStats.recordCalls(1)
        process.command = cmd
        process.running = true
    }

    function _canStartPublicOperation() {
        return token !== "" && !isLoading && !isBusy
    }

    function _queueThreadDoneSync(threadIds) {
        if (!threadIds || threadIds.length === 0) return

        _compactDoneQueueIfNeeded()
        var nextQueue = pendingThreadDoneQueue
        var seen = {}
        for (var existingIndex = pendingThreadDoneIndex; existingIndex < nextQueue.length; existingIndex++)
            seen[nextQueue[existingIndex]] = true

        for (var index = 0; index < threadIds.length; index++) {
            var threadId = threadIds[index]
            if (!threadId || seen[threadId]) continue
            seen[threadId] = true
            nextQueue.push(threadId)
        }

        pendingThreadDoneQueue = nextQueue
        processPendingDoneQueue()
    }

    function _queueThreadReadSync(threadIds) {
        if (!threadIds || threadIds.length === 0) return

        _compactReadQueueIfNeeded()
        var nextQueue = pendingThreadReadQueue
        var seen = {}
        for (var existingIndex = pendingThreadReadIndex; existingIndex < nextQueue.length; existingIndex++)
            seen[nextQueue[existingIndex]] = true

        for (var index = 0; index < threadIds.length; index++) {
            var threadId = threadIds[index]
            if (!threadId || seen[threadId]) continue
            seen[threadId] = true
            nextQueue.push(threadId)
        }

        pendingThreadReadQueue = nextQueue
        processPendingReadQueue()
    }

    function processPendingReadQueue() {
        if (!token || isOperating || isLoading)
            return
        if (pendingThreadReadIndex >= pendingThreadReadQueue.length)
            return

        var threadId = pendingThreadReadQueue[pendingThreadReadIndex]
        pendingThreadReadIndex++
        _compactReadQueueIfNeeded()

        _runMutation(
            "PATCH",
            GitHubConstants.githubThreadApiPrefix + threadId,
            "thread_read_sync", threadId, "", ""
        )
    }

    function _processPendingOperationQueues() {
        processPendingReadQueue()
        if (!isOperating)
            processPendingDoneQueue()
    }

    function _compactDoneQueueIfNeeded() {
        if (pendingThreadDoneIndex === 0)
            return
        if (pendingThreadDoneIndex >= pendingThreadDoneQueue.length) {
            pendingThreadDoneQueue = []
            pendingThreadDoneIndex = 0
            return
        }
        if (pendingThreadDoneIndex >= 32) {
            pendingThreadDoneQueue = pendingThreadDoneQueue.slice(pendingThreadDoneIndex)
            pendingThreadDoneIndex = 0
        }
    }

    function _compactReadQueueIfNeeded() {
        if (pendingThreadReadIndex === 0)
            return
        if (pendingThreadReadIndex >= pendingThreadReadQueue.length) {
            pendingThreadReadQueue = []
            pendingThreadReadIndex = 0
            return
        }
        if (pendingThreadReadIndex >= 32) {
            pendingThreadReadQueue = pendingThreadReadQueue.slice(pendingThreadReadIndex)
            pendingThreadReadIndex = 0
        }
    }

    function _collectThreadIds(messages, unreadOnly) {
        var result = []
        var seen = {}
        var items = messages || []
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            if (!item || !item.threadId || seen[item.threadId])
                continue
            if (unreadOnly && !item.unread)
                continue
            seen[item.threadId] = true
            result.push(item.threadId)
        }
        return result
    }

    function _threadIdSet(threadIds) {
        var result = {}
        var ids = threadIds || []
        for (var index = 0; index < ids.length; index++) {
            if (ids[index])
                result[ids[index]] = true
        }
        return result
    }

    function _markAsReadItem(item) {
        var copy = _cloneItem(item)
        copy.unread = false
        return copy
    }

    function _cloneItem(item) {
        var copy = {}
        for (var key in item)
            copy[key] = item[key]
        return copy
    }

    function _cloneMap(source) {
        var copy = {}
        for (var key in source)
            copy[key] = source[key]
        return copy
    }

    function _mergeDoneStates(confirmed, pending) {
        var merged = _cloneMap(confirmed || ({}))
        for (var key in pending) {
            if (pending[key])
                merged[key] = true
        }
        return merged
    }

    function _addPendingDoneThreadIds(threadIds) {
        var pendingCopy = _cloneMap(pendingDoneThreadState)
        var changed = false
        var ids = threadIds || []
        for (var index = 0; index < ids.length; index++) {
            var threadId = ids[index]
            if (!threadId || doneThreadState[threadId] || pendingCopy[threadId])
                continue
            pendingCopy[threadId] = true
            changed = true
        }
        if (changed)
            pendingDoneThreadState = pendingCopy
    }

    function _stashPendingDoneMessages(threadIds, messages) {
        var idSet = _threadIdSet(threadIds || [])
        var next = _cloneMap(pendingDoneMessagesByThread)
        var changed = false
        var items = messages || []
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            if (!item || !item.threadId || !idSet[item.threadId] || next[item.threadId])
                continue
            next[item.threadId] = _cloneItem(item)
            changed = true
        }
        if (changed)
            pendingDoneMessagesByThread = next
    }

    function _removePendingDoneMessage(threadId) {
        if (!threadId || !pendingDoneMessagesByThread[threadId])
            return
        var next = _cloneMap(pendingDoneMessagesByThread)
        delete next[threadId]
        pendingDoneMessagesByThread = next
    }

    function _stashPendingReadMessages(threadIds, messages) {
        var idSet = _threadIdSet(threadIds || [])
        var next = _cloneMap(pendingReadMessagesByThread)
        var changed = false
        var items = messages || []
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            if (!item || !item.threadId || !idSet[item.threadId] || next[item.threadId])
                continue
            if (!item.unread)
                continue
            next[item.threadId] = _cloneItem(item)
            changed = true
        }
        if (changed)
            pendingReadMessagesByThread = next
    }

    function _removePendingReadMessage(threadId) {
        if (!threadId || !pendingReadMessagesByThread[threadId])
            return
        var next = _cloneMap(pendingReadMessagesByThread)
        delete next[threadId]
        pendingReadMessagesByThread = next
    }

    function _restorePendingDoneMessage(threadId, messages) {
        var stored = pendingDoneMessagesByThread[threadId]
        _removePendingDoneMessage(threadId)
        if (!stored)
            return { items: messages, unreadChanged: false }

        var source = messages || []
        for (var index = 0; index < source.length; index++) {
            if (source[index] && source[index].threadId === threadId)
                return { items: messages, unreadChanged: false }
        }

        var restored = source.slice(0)
        restored.push(stored)
        restored.sort(function(left, right) {
            var leftTime = left.updatedAtMs || 0
            var rightTime = right.updatedAtMs || 0
            return rightTime - leftTime
        })
        return { items: restored, unreadChanged: true }
    }

    function _restorePendingReadMessage(threadId, messages) {
        var stored = pendingReadMessagesByThread[threadId]
        _removePendingReadMessage(threadId)
        if (!stored)
            return { items: messages, unreadChanged: false }

        var source = messages || []
        var updated = []
        var changed = false
        for (var index = 0; index < source.length; index++) {
            var item = source[index]
            if (item && item.threadId === threadId) {
                var copy = _cloneItem(item)
                copy.unread = true
                updated.push(copy)
                changed = true
            } else {
                updated.push(item)
            }
        }

        return changed ? { items: updated, unreadChanged: true }
                       : { items: messages, unreadChanged: false }
    }

    function _normalizeDoneThreadState(source) {
        var result = {}
        var value = source || ({})

        if (Array.isArray(value)) {
            for (var index = 0; index < value.length; index++) {
                var arrayId = String(value[index] || "").trim()
                if (arrayId)
                    result[arrayId] = true
            }
            return result
        }

        for (var key in value) {
            if (value[key]) {
                var objectId = String(key || "").trim()
                if (objectId)
                    result[objectId] = true
            }
        }

        return result
    }

    // =========================================================================
    //  PROCESS COMPONENT
    // =========================================================================

    Component {
        id: operationComponentDef

        Process {
            property string _buffer: ""
            property string actionType: "thread_read"
            property string threadId: ""
            property string repositoryFullName: ""
            property int generation: 0

            stdout: SplitParser {
                onRead: line => _buffer += line
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[GitHubInbox] operate:", line)
                }
            }

            onExited: exitCode => {
                if (generation !== operations.operationGeneration) {
                    destroy()
                    return
                }

                operations.isOperating = false

                if (exitCode !== 0) {
                    operations._handleMutationFailure(actionType, threadId)
                    operations.operationError("Action failed. Check token permissions.")
                    Qt.callLater(operations._processPendingOperationQueues)
                    destroy()
                    return
                }

                var statusCode = parseInt((_buffer || "").trim())
                if (!isNaN(statusCode)
                        && statusCode >= GitHubConstants.httpSuccessMin
                        && statusCode < GitHubConstants.httpSuccessMax) {
                    operations.operationApplied(actionType, threadId, repositoryFullName, [])
                } else {
                    operations._handleMutationFailure(actionType, threadId)
                    operations.operationError("Action failed (HTTP "
                                          + (isNaN(statusCode) ? "?" : statusCode) + ").")
                }

                Qt.callLater(operations._processPendingOperationQueues)
                destroy()
            }
        }
    }

    function _handleMutationFailure(actionType, threadId) {
        if (actionType === "thread_done_sync" && threadId)
            operationApplied("thread_done_revert", threadId, "", [])
        if (actionType === "thread_read_sync" && threadId)
            operationApplied("thread_read_revert", threadId, "", [])
    }
}
