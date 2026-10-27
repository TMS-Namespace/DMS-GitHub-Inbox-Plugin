// InboxOperations.qml - coordinates inbox actions, optimistic state and serialized mutations.

pragma ComponentBehavior: Bound

import QtQuick
import "../../JS/Helpers/InboxOperationRules.js" as InboxOperationRules
import ".."

Item {
    id: operations

    property alias doneThreadState: operationState.doneThreadState
    readonly property var effectiveDoneThreadState: operationState.effectiveDoneThreadState
    readonly property bool isBusy: mutationService.isOperating || mutationQueue.hasPending
    property bool isLoading: false
    property alias isOperating: mutationService.isOperating
    property alias operationGeneration: mutationService.operationGeneration
    property alias pendingDoneMessagesByThread: operationState.pendingDoneMessagesByThread
    property alias pendingDoneThreadState: operationState.pendingDoneThreadState
    property alias pendingReadMessagesByThread: operationState.pendingReadMessagesByThread
    property var providerApi: null
    property string token: ""

    signal operationApplied(string actionType, string threadId, string repositoryFullName, var threadIds)
    signal operationError(string errorMessage)
    signal stateUpdated

    // Reserve Done IDs until the corresponding requests complete or fail.
    function _addPendingDoneThreadIds(threadIds) {
        operationState._addPendingDoneThreadIds(threadIds);
    }

    // Require a token and idle fetch/mutation queues before accepting a public action.
    function _canStartPublicOperation() {
        return token !== "" && !isLoading && !isBusy;
    }

    // Emit rollback actions for failed optimistic read or Done requests.
    function _handleMutationFailure(actionType, threadId) {
        if (actionType === "thread_done_sync" && threadId)
            operationApplied("thread_done_revert", threadId, "", []);
        if (actionType === "thread_read_sync" && threadId)
            operationApplied("thread_read_revert", threadId, "", []);
    }

    // Give queued read requests priority over Done requests while keeping mutations serial.
    function _processPendingOperationQueues() {
        processPendingReadQueue();
        if (!isOperating)
            processPendingDoneQueue();
    }
    // Enqueue distinct Done threads and start one when the service is available.
    function _queueThreadDoneSync(threadIds) {
        mutationQueue.enqueueDone(threadIds);
        processPendingDoneQueue();
    }
    // Enqueue distinct read threads and start one when the service is available.
    function _queueThreadReadSync(threadIds) {
        mutationQueue.enqueueRead(threadIds);
        processPendingReadQueue();
    }

    // Send an action to the provider-backed mutation service.
    function _runProviderMutation(request, actionType, threadId, repositoryFullName) {
        mutationService.run(request, actionType, threadId, repositoryFullName);
    }
    // Preserve optimistic read flags when a refreshed snapshot arrives.
    function applyPendingReadState(messages) {
        return operationState.applyPendingReadState(messages);
    }
    // Apply a completed or optimistic action to the message snapshot.
    function applyResult(actionType, threadId, repositoryFullName, messages, threadIds) {
        return operationState.applyResult(actionType, threadId, repositoryFullName, messages, threadIds);
    }
    // Expose request construction for callers and request-security checks.
    function buildMutationCommand(method, url, payloadJson) {
        return mutationService.buildMutationCommand(method, url, payloadJson);
    }
    // Clear local Done records when GitHub returns a reopened thread.
    function clearReturnedDoneThreadState(messages) {
        operationState.clearReturnedDoneThreadState(messages);
    }

    // Request GitHub's all-read action when no fetch or mutation is active.
    function markAllAsRead() {
        if (!_canStartPublicOperation())
            return;
        _runProviderMutation(providerApi ? providerApi.buildMarkAllReadRequest() : null, "all_read", "", "");
    }
    // Mark inferred or explicit messages Done in local state.
    function markMessagesLocallyDone(messages, source) {
        operationState.markMessagesLocallyDone(messages, source);
    }

    // Request GitHub's repository-read action when no fetch or mutation is active.
    function markRepoAsRead(repositoryFullName) {
        if (!repositoryFullName)
            return;
        if (!_canStartPublicOperation())
            return;
        _runProviderMutation(providerApi ? providerApi.buildRepositoryReadRequest(repositoryFullName) : null, "repo_read", "", repositoryFullName);
    }

    // Hide the supplied repository messages immediately and queue per-thread Done requests.
    function markRepoDone(repositoryFullName, messages) {
        if (!repositoryFullName)
            return;
        if (!_canStartPublicOperation())
            return;
        let threadIds = [];

        for (let index = 0; index < messages.length; index++) {
            let item = messages[index];
            if (item.repository === repositoryFullName && item.threadId)
                threadIds.push(item.threadId);
        }

        if (threadIds.length === 0)
            return;
        operationApplied("repo_done", "", repositoryFullName, threadIds);
        _addPendingDoneThreadIds(threadIds);
        _queueThreadDoneSync(threadIds);
    }

    // Request a thread read mutation when no fetch or mutation is active.
    function markThreadAsRead(threadId) {
        if (!threadId)
            return;
        if (!_canStartPublicOperation())
            return;
        _runProviderMutation(providerApi ? providerApi.buildThreadActionRequest("read", threadId) : null, "thread_read", threadId, "");
    }

    // Request a thread unread mutation when no fetch or mutation is active.
    function markThreadAsUnread(threadId) {
        if (!threadId)
            return;
        if (!_canStartPublicOperation())
            return;
        _runProviderMutation(providerApi ? providerApi.buildThreadActionRequest("unread", threadId) : null, "thread_unread", threadId, "");
    }

    // Hide a thread immediately and queue its remote Done request.
    function markThreadDone(threadId) {
        if (!threadId)
            return;
        if (!_canStartPublicOperation())
            return;
        operationApplied("thread_done", threadId, "", []);
        _addPendingDoneThreadIds([threadId]);
        _queueThreadDoneSync([threadId]);
    }
    // Mark thread IDs Done locally when no message records are available.
    function markThreadIdsLocallyDone(threadIds, source) {
        operationState.markThreadIdsLocallyDone(threadIds, source);
    }

    // Mark an opened thread read immediately and queue its remote read request.
    function markThreadReadAfterOpen(threadId) {
        if (!threadId)
            return;
        if (!token)
            return;
        operationApplied("thread_read_pending", threadId, "", []);
        _queueThreadReadSync([threadId]);
    }

    // Mark unread members of the supplied message set read and queue their remote requests.
    function markThreadsAsRead(messages) {
        if (!_canStartPublicOperation())
            return;
        let threadIds = InboxOperationRules.collectThreadIds(messages, true);
        if (threadIds.length === 0)
            return;
        operationApplied("threads_read", "", "", threadIds);
        _queueThreadReadSync(threadIds);
    }

    // Hide distinct threads in the supplied message set and queue remote Done requests.
    function markThreadsDone(messages) {
        if (!_canStartPublicOperation())
            return;
        let threadIds = InboxOperationRules.collectThreadIds(messages, false);
        if (threadIds.length === 0)
            return;
        operationApplied("threads_done", "", "", threadIds);
        _addPendingDoneThreadIds(threadIds);
        _queueThreadDoneSync(threadIds);
    }
    // Start one queued Done mutation when the provider and widget are ready.
    function processPendingDoneQueue() {
        if (!token || isOperating || isLoading)
            return;
        let threadId = mutationQueue.takeDone();
        if (threadId)
            _runProviderMutation(providerApi ? providerApi.buildThreadActionRequest("done", threadId) : null, "thread_done_sync", threadId, "");
    }
    // Start one queued read mutation when the provider and widget are ready.
    function processPendingReadQueue() {
        if (!token || isOperating || isLoading)
            return;
        let threadId = mutationQueue.takeRead();
        if (threadId)
            _runProviderMutation(providerApi ? providerApi.buildThreadActionRequest("read", threadId) : null, "thread_read_sync", threadId, "");
    }
    // Remove Done records outside the configured retention period.
    function pruneDoneThreadState(retentionMs) {
        operationState.pruneDoneThreadState(retentionMs);
    }
    // Invalidate active requests and clear queued and optimistic work.
    function resetState(clearDoneState) {
        mutationService.reset();
        mutationQueue.reset();
        operationState.reset(clearDoneState);
    }
    // Restore confirmed Done records from the cache.
    function setDoneThreadState(state) {
        operationState.setDoneThreadState(state);
    }

    visible: false

    InboxOperationState {
        id: operationState
    }
    InboxMutationQueue {
        id: mutationQueue
    }
    InboxMutationService {
        id: mutationService

        isLoading: operations.isLoading
        providerApi: operations.providerApi
        token: operations.token

        onMutationFinished: (actionType, threadId, repositoryFullName, success, errorMessage) => {
            if (success)
                operations.operationApplied(actionType, threadId, repositoryFullName, []);
            else {
                operations._handleMutationFailure(actionType, threadId);
                operations.operationError(errorMessage);
            }
            Qt.callLater(operations._processPendingOperationQueues);
        }
        onOperationError: errorMessage => operations.operationError(errorMessage)
    }
}
