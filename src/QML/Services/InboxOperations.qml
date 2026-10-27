// InboxOperations.qml - Handles GitHub inbox message operations
//
// Encapsulates mark-as-read, mark-as-unread, mark-done, repo-read, and
// mark-all-read operations. Applies optimistic local state updates and
// queues thread-done sync requests.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../JS/Storage/CacheSerialization.js" as CacheSerialization
import ".."

Item {
    id: operations

    property var doneThreadState: ({})
    readonly property var effectiveDoneThreadState: _mergeDoneStates(doneThreadState, pendingDoneThreadState)
    readonly property bool isBusy: isOperating || pendingThreadDoneIndex < pendingThreadDoneQueue.length || pendingThreadReadIndex < pendingThreadReadQueue.length
    property bool isLoading: false    // bound from outside --- blocks operations

    // -- State ----------------------------------------------------------------
    property bool isOperating: false
    property int operationGeneration: 0
    property var pendingDoneMessagesByThread: ({})
    property var pendingDoneThreadState: ({})
    property var pendingReadMessagesByThread: ({})
    property int pendingThreadDoneIndex: 0
    property var pendingThreadDoneQueue: []
    property int pendingThreadReadIndex: 0
    property var pendingThreadReadQueue: []
    property var providerApi: null

    // -- Configuration --------------------------------------------------------
    property string token: ""

    // -- Signals --------------------------------------------------------------
    signal operationApplied(string actionType, string threadId, string repositoryFullName, var threadIds)
    signal operationError(string errorMessage)
    signal stateUpdated

    // Deduplicate optimistic Done identities until their remote mutations finish.
    function _addPendingDoneThreadIds(threadIds) {
        let pendingCopy = _cloneMap(pendingDoneThreadState);
        let changed = false;
        let ids = threadIds || [];
        for (let index = 0; index < ids.length; index++) {
            let threadId = ids[index];
            if (!threadId || doneThreadState[threadId] || pendingCopy[threadId])
                continue;
            pendingCopy[threadId] = true;
            changed = true;
        }
        if (changed)
            pendingDoneThreadState = pendingCopy;
    }
    // Require a token and idle fetch/mutation queues before accepting a public action.
    function _canStartPublicOperation() {
        return token !== "" && !isLoading && !isBusy;
    }
    // Copy a message before an optimistic mutation changes its visible fields.
    function _cloneItem(item) {
        let copy = {};
        for (let key in item)
            copy[key] = item[key];
        return copy;
    }
    // Replace map identity so QML bindings can observe an update.
    function _cloneMap(source) {
        let copy = {};
        for (let key in source)
            copy[key] = source[key];
        return copy;
    }
    // Collect distinct message thread IDs, optionally restricting them to unread messages.
    function _collectThreadIds(messages, unreadOnly) {
        let result = [];
        let seen = {};
        let items = messages || [];
        for (let index = 0; index < items.length; index++) {
            let item = items[index];
            if (!item || !item.threadId || seen[item.threadId])
                continue;
            if (unreadOnly && !item.unread)
                continue;
            seen[item.threadId] = true;
            result.push(item.threadId);
        }
        return result;
    }
    // Release consumed Done-queue entries when the queue is exhausted or its prefix grows.
    function _compactDoneQueueIfNeeded() {
        if (pendingThreadDoneIndex === 0)
            return;
        if (pendingThreadDoneIndex >= pendingThreadDoneQueue.length) {
            pendingThreadDoneQueue = [];
            pendingThreadDoneIndex = 0;
            return;
        }
        if (pendingThreadDoneIndex >= 32) {
            pendingThreadDoneQueue = pendingThreadDoneQueue.slice(pendingThreadDoneIndex);
            pendingThreadDoneIndex = 0;
        }
    }
    // Release consumed read-queue entries when the queue is exhausted or its prefix grows.
    function _compactReadQueueIfNeeded() {
        if (pendingThreadReadIndex === 0)
            return;
        if (pendingThreadReadIndex >= pendingThreadReadQueue.length) {
            pendingThreadReadQueue = [];
            pendingThreadReadIndex = 0;
            return;
        }
        if (pendingThreadReadIndex >= 32) {
            pendingThreadReadQueue = pendingThreadReadQueue.slice(pendingThreadReadIndex);
            pendingThreadReadIndex = 0;
        }
    }
    // Record the Done source, message activity timestamp and local save time.
    function _doneStateEntryForThread(threadId, source, item) {
        let pendingMessage = item || pendingDoneMessagesByThread[threadId] || ({});
        return {
            source: String(source || "local"),
            updatedAt: pendingMessage.updatedAt || "",
            savedAt: Date.now()
        };
    }
    // Use the message activity time for retention, falling back to the Done record's save time.
    function _doneStateTimestampMs(entry) {
        if (!entry || typeof entry !== "object")
            return 0;
        let updatedAtMs = Date.parse(entry.updatedAt || "") || 0;
        if (updatedAtMs > 0)
            return updatedAtMs;
        let savedAtMs = parseInt(entry.savedAt || 0);
        return isNaN(savedAtMs) ? 0 : savedAtMs;
    }
    // Emit rollback actions for failed optimistic read or Done requests.
    function _handleMutationFailure(actionType, threadId) {
        if (actionType === "thread_done_sync" && threadId)
            operationApplied("thread_done_revert", threadId, "", []);
        if (actionType === "thread_read_sync" && threadId)
            operationApplied("thread_read_revert", threadId, "", []);
    }
    // Return a message copy with its unread flag cleared.
    function _markAsReadItem(item) {
        let copy = _cloneItem(item);
        copy.unread = false;
        return copy;
    }
    // Overlay pending Done IDs on confirmed Done records for immediate hiding.
    function _mergeDoneStates(confirmed, pending) {
        let merged = _cloneMap(confirmed || ({}));
        for (let key in pending) {
            if (pending[key])
                merged[key] = true;
        }
        return merged;
    }
    // Convert restored Done records through the shared cache-format migration.
    function _normalizeDoneThreadState(source) {
        return CacheSerialization.normalizeDoneThreadState(source);
    }
    // Give queued read requests priority over Done requests while keeping mutations serial.
    function _processPendingOperationQueues() {
        processPendingReadQueue();
        if (!isOperating)
            processPendingDoneQueue();
    }
    // Enqueue distinct Done thread IDs and attempt the next remote mutation.
    function _queueThreadDoneSync(threadIds) {
        if (!threadIds || threadIds.length === 0)
            return;
        _compactDoneQueueIfNeeded();
        let nextQueue = pendingThreadDoneQueue;
        let seen = {};
        for (let existingIndex = pendingThreadDoneIndex; existingIndex < nextQueue.length; existingIndex++)
            seen[nextQueue[existingIndex]] = true;

        for (let index = 0; index < threadIds.length; index++) {
            let threadId = threadIds[index];
            if (!threadId || seen[threadId])
                continue;
            seen[threadId] = true;
            nextQueue.push(threadId);
        }

        pendingThreadDoneQueue = nextQueue;
        processPendingDoneQueue();
    }
    // Enqueue distinct read thread IDs and attempt the next remote mutation.
    function _queueThreadReadSync(threadIds) {
        if (!threadIds || threadIds.length === 0)
            return;
        _compactReadQueueIfNeeded();
        let nextQueue = pendingThreadReadQueue;
        let seen = {};
        for (let existingIndex = pendingThreadReadIndex; existingIndex < nextQueue.length; existingIndex++)
            seen[nextQueue[existingIndex]] = true;

        for (let index = 0; index < threadIds.length; index++) {
            let threadId = threadIds[index];
            if (!threadId || seen[threadId])
                continue;
            seen[threadId] = true;
            nextQueue.push(threadId);
        }

        pendingThreadReadQueue = nextQueue;
        processPendingReadQueue();
    }
    // Forget a saved rollback copy after the thread's Done request settles.
    function _removePendingDoneMessage(threadId) {
        if (!threadId || !pendingDoneMessagesByThread[threadId])
            return;
        let next = _cloneMap(pendingDoneMessagesByThread);
        delete next[threadId];
        pendingDoneMessagesByThread = next;
    }
    // Forget a saved rollback copy after the thread's read request settles.
    function _removePendingReadMessage(threadId) {
        if (!threadId || !pendingReadMessagesByThread[threadId])
            return;
        let next = _cloneMap(pendingReadMessagesByThread);
        delete next[threadId];
        pendingReadMessagesByThread = next;
    }
    // Reinsert the saved message after a failed Done request unless it is already present.
    function _restorePendingDoneMessage(threadId, messages) {
        let stored = pendingDoneMessagesByThread[threadId];
        _removePendingDoneMessage(threadId);
        if (!stored)
            return {
                items: messages,
                unreadChanged: false
            };

        let source = messages || [];
        for (let index = 0; index < source.length; index++) {
            if (source[index] && source[index].threadId === threadId)
                return {
                    items: messages,
                    unreadChanged: false
                };
        }

        let restored = source.slice(0);
        restored.push(stored);
        restored.sort(function (left, right) {
            let leftTime = left.updatedAtMs || 0;
            let rightTime = right.updatedAtMs || 0;
            return rightTime - leftTime;
        });
        return {
            items: restored,
            unreadChanged: true
        };
    }
    // Mark a thread unread again after a failed read request if a rollback copy was saved.
    function _restorePendingReadMessage(threadId, messages) {
        let stored = pendingReadMessagesByThread[threadId];
        _removePendingReadMessage(threadId);
        if (!stored)
            return {
                items: messages,
                unreadChanged: false
            };

        let source = messages || [];
        let updated = [];
        let changed = false;
        for (let index = 0; index < source.length; index++) {
            let item = source[index];
            if (item && item.threadId === threadId) {
                let copy = _cloneItem(item);
                copy.unread = true;
                updated.push(copy);
                changed = true;
            } else {
                updated.push(item);
            }
        }

        return changed ? {
            items: updated,
            unreadChanged: true
        } : {
            items: messages,
            unreadChanged: false
        };
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    // Put the secret header on stdin rather than exposing it in process arguments.
    function _runMutation(method, url, actionType, threadId, repositoryFullName, payloadJson) {
        if (!token || isOperating || isLoading)
            return;
        isOperating = true;

        let process = operationComponentDef.createObject(operations, {
            requestToken: token,
            actionType: actionType || "thread_read",
            threadId: threadId || "",
            repositoryFullName: repositoryFullName || "",
            generation: operationGeneration
        });

        ApiCallStats.recordCalls(1);
        process.command = buildMutationCommand(method, url, payloadJson);
        process.running = true;
    }
    // Retain mutation context while keeping request construction behind the provider facade.
    function _runProviderMutation(request, actionType, threadId, repositoryFullName) {
        if (!request) {
            operationError("The GitHub provider rejected this inbox operation.");
            PluginLogger.error("provider", "Rejected an invalid inbox mutation request");
            return;
        }
        _runMutation(request.method, request.url, actionType, threadId, repositoryFullName, request.payloadJson);
    }
    // Save message copies before optimistic Done removal so failed requests can restore them.
    function _stashPendingDoneMessages(threadIds, messages) {
        let idSet = _threadIdSet(threadIds || []);
        let next = _cloneMap(pendingDoneMessagesByThread);
        let changed = false;
        let items = messages || [];
        for (let index = 0; index < items.length; index++) {
            let item = items[index];
            if (!item || !item.threadId || !idSet[item.threadId] || next[item.threadId])
                continue;
            next[item.threadId] = _cloneItem(item);
            changed = true;
        }
        if (changed)
            pendingDoneMessagesByThread = next;
    }
    // Save unread message copies before optimistic read changes so failed requests can restore them.
    function _stashPendingReadMessages(threadIds, messages) {
        let idSet = _threadIdSet(threadIds || []);
        let next = _cloneMap(pendingReadMessagesByThread);
        let changed = false;
        let items = messages || [];
        for (let index = 0; index < items.length; index++) {
            let item = items[index];
            if (!item || !item.threadId || !idSet[item.threadId] || next[item.threadId])
                continue;
            if (!item.unread)
                continue;
            next[item.threadId] = _cloneItem(item);
            changed = true;
        }
        if (changed)
            pendingReadMessagesByThread = next;
    }
    // Build a membership map from nonempty thread IDs.
    function _threadIdSet(threadIds) {
        let result = {};
        let ids = threadIds || [];
        for (let index = 0; index < ids.length; index++) {
            if (ids[index])
                result[ids[index]] = true;
        }
        return result;
    }
    // Keep pending optimistic read flags when fresh messages arrive before requests complete.
    function applyPendingReadState(messages) {
        let hasPending = false;
        for (let pendingId in pendingReadMessagesByThread) {
            hasPending = true;
            break;
        }
        if (!hasPending)
            return messages;

        let source = messages || [];
        let updated = [];
        let changed = false;
        for (let index = 0; index < source.length; index++) {
            let item = source[index];
            if (item && item.threadId && pendingReadMessagesByThread[item.threadId] && item.unread) {
                updated.push(_markAsReadItem(item));
                changed = true;
            } else {
                updated.push(item);
            }
        }
        return changed ? updated : messages;
    }

    /// Apply operation result to a messages list and return updated state.
    function applyResult(actionType, threadId, repositoryFullName, messages, threadIds) {
        let updated = [];
        let doneCopy = _cloneMap(doneThreadState);
        let pendingCopy = _cloneMap(pendingDoneThreadState);
        let threadIdSet = _threadIdSet(threadIds || []);

        if (actionType === "thread_done_sync") {
            if (threadId) {
                doneCopy[threadId] = _doneStateEntryForThread(threadId, "local");
                delete pendingCopy[threadId];
                doneThreadState = doneCopy;
                pendingDoneThreadState = pendingCopy;
                _removePendingDoneMessage(threadId);
            }
            return {
                items: messages,
                unreadChanged: false
            };
        }

        if (actionType === "thread_done_revert") {
            delete pendingCopy[threadId];
            pendingDoneThreadState = pendingCopy;
            return _restorePendingDoneMessage(threadId, messages);
        }

        if (actionType === "thread_read_sync") {
            _removePendingReadMessage(threadId);
            return {
                items: messages,
                unreadChanged: false
            };
        }

        if (actionType === "thread_read_revert")
            return _restorePendingReadMessage(threadId, messages);

        if (actionType === "all_read") {
            for (let allIndex = 0; allIndex < messages.length; allIndex++)
                updated.push(_markAsReadItem(messages[allIndex]));
            return {
                items: updated,
                unreadChanged: true
            };
        }

        if (actionType === "repo_read") {
            for (let repoIndex = 0; repoIndex < messages.length; repoIndex++) {
                let repoItem = messages[repoIndex];
                if (repoItem.repository === repositoryFullName)
                    updated.push(_markAsReadItem(repoItem));
                else
                    updated.push(repoItem);
            }
            return {
                items: updated,
                unreadChanged: true
            };
        }

        if (actionType === "repo_done") {
            _stashPendingDoneMessages(threadIds, messages);
            for (let repoDoneIndex = 0; repoDoneIndex < messages.length; repoDoneIndex++) {
                let repoDoneItem = messages[repoDoneIndex];
                if (repoDoneItem.repository === repositoryFullName && repoDoneItem.threadId && threadIdSet[repoDoneItem.threadId])
                    continue;
                updated.push(repoDoneItem);
            }
            return {
                items: updated,
                unreadChanged: true
            };
        }

        if (actionType === "threads_read") {
            for (let readIndex = 0; readIndex < messages.length; readIndex++) {
                let readItem = messages[readIndex];
                if (readItem.threadId && threadIdSet[readItem.threadId])
                    updated.push(_markAsReadItem(readItem));
                else
                    updated.push(readItem);
            }
            return {
                items: updated,
                unreadChanged: true
            };
        }

        if (actionType === "threads_done") {
            _stashPendingDoneMessages(threadIds, messages);
            for (let batchDoneIndex = 0; batchDoneIndex < messages.length; batchDoneIndex++) {
                let batchDoneItem = messages[batchDoneIndex];
                if (batchDoneItem.threadId && threadIdSet[batchDoneItem.threadId])
                    continue;
                updated.push(batchDoneItem);
            }
            return {
                items: updated,
                unreadChanged: true
            };
        }

        if (actionType === "thread_done") {
            _stashPendingDoneMessages([threadId], messages);
            for (let doneIndex = 0; doneIndex < messages.length; doneIndex++) {
                let doneItem = messages[doneIndex];
                if (doneItem.threadId !== threadId)
                    updated.push(doneItem);
            }
            return {
                items: updated,
                unreadChanged: true
            };
        }

        if (actionType === "thread_unread") {
            for (let unreadIndex = 0; unreadIndex < messages.length; unreadIndex++) {
                let unreadItem = messages[unreadIndex];
                if (unreadItem.threadId === threadId) {
                    let unreadCopy = _cloneItem(unreadItem);
                    unreadCopy.unread = true;
                    updated.push(unreadCopy);
                } else {
                    updated.push(unreadItem);
                }
            }
            return {
                items: updated,
                unreadChanged: true
            };
        }

        if (actionType === "thread_read_pending")
            _stashPendingReadMessages([threadId], messages);

        // thread_read, thread_read_pending
        for (let index = 0; index < messages.length; index++) {
            let item = messages[index];
            if (item.threadId === threadId)
                updated.push(_markAsReadItem(item));
            else
                updated.push(item);
        }
        return {
            items: updated,
            unreadChanged: true
        };
    }
    // Build a curl mutation with optional JSON and an authorization header supplied on stdin.
    function buildMutationCommand(method, url, payloadJson) {
        // Dux v2's dms dl is GET-only and has no stdin/header-file input.
        // Mutations need PATCH/PUT/DELETE and curl -H @- to keep the token out of argv.
        let command = ["bash", "-c", "exec \"$@\" -H @-", "github-inbox-mutation", "curl", "-sS", "-o", "/dev/null", "-w", GitHubConstants.curlStatusCodeFormat, "--connect-timeout", GitHubConstants.curlConnectTimeoutSeconds, "--max-time", GitHubConstants.curlMaxTimeSeconds, "-X", method, "-H", "Accept: " + GitHubConstants.httpAcceptHeader, "-H", "X-GitHub-Api-Version: " + GitHubConstants.githubApiVersionHeader];
        command = command.concat(providerApi.buildCurlRetryArguments());
        if (payloadJson)
            command.push("-H", "Content-Type: application/json", "-d", payloadJson);
        command.push(url);
        return command;
    }

    // GitHub's notifications response does not expose a Done flag. A DELETE
    // performed by this plugin is retained locally, but GitHub can reopen that
    // thread when later activity arrives. Clear local Done only when the returned
    // thread's `updated_at` is newer than the timestamp saved at Done time.
    // Inferred entries may always be cleared when returned. API reference:
    // https://docs.github.com/en/rest/activity/notifications#list-notifications-for-the-authenticated-user
    function clearReturnedDoneThreadState(messages) {
        let source = messages || [];
        if (source.length === 0)
            return;
        let doneCopy = _cloneMap(doneThreadState);
        let changed = false;
        for (let index = 0; index < source.length; index++) {
            let message = source[index] || ({});
            let threadId = String(message.threadId || "").trim();
            let entry = doneCopy[threadId];
            if (!threadId || !entry || typeof entry !== "object")
                continue;
            let doneSource = String(entry.source || "");
            if (doneSource === "github_missing_from_complete_refresh") {
                delete doneCopy[threadId];
                changed = true;
                continue;
            }

            if (doneSource !== "local")
                continue;
            let returnedUpdatedAtMs = message.updatedAtMs || Date.parse(message.updatedAt || "") || 0;
            let doneUpdatedAtMs = Date.parse(entry.updatedAt || "") || 0;
            let doneSavedAtMs = parseInt(entry.savedAt || 0);
            let doneBoundaryMs = doneUpdatedAtMs || doneSavedAtMs;
            if (returnedUpdatedAtMs > 0 && doneBoundaryMs > 0 && returnedUpdatedAtMs > doneBoundaryMs) {
                delete doneCopy[threadId];
                changed = true;
            }
        }
        if (changed)
            doneThreadState = doneCopy;
    }
    // Request GitHub's all-read action when no fetch or mutation is active.
    function markAllAsRead() {
        if (!_canStartPublicOperation())
            return;
        _runProviderMutation(providerApi ? providerApi.buildMarkAllReadRequest() : null, "all_read", "", "");
    }
    // Store local Done records with the supplied source and clear matching pending state.
    function markMessagesLocallyDone(messages, source) {
        let doneCopy = _cloneMap(doneThreadState);
        let pendingCopy = _cloneMap(pendingDoneThreadState);
        let changed = false;
        let items = messages || [];
        let stateSource = String(source || "local");
        for (let index = 0; index < items.length; index++) {
            let item = items[index] || ({});
            let threadId = String(item.threadId || "").trim();
            if (!threadId || doneCopy[threadId])
                continue;
            doneCopy[threadId] = _doneStateEntryForThread(threadId, stateSource, item);
            delete pendingCopy[threadId];
            _removePendingDoneMessage(threadId);
            changed = true;
        }
        if (!changed)
            return;
        doneThreadState = doneCopy;
        pendingDoneThreadState = pendingCopy;
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

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

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
    // Create local Done records from thread IDs when no message details are supplied.
    function markThreadIdsLocallyDone(threadIds, source) {
        let messages = [];
        let ids = threadIds || [];
        for (let idIndex = 0; idIndex < ids.length; idIndex++)
            messages.push({
                threadId: ids[idIndex]
            });
        markMessagesLocallyDone(messages, source);
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
        let threadIds = _collectThreadIds(messages, true);
        if (threadIds.length === 0)
            return;
        operationApplied("threads_read", "", "", threadIds);
        _queueThreadReadSync(threadIds);
    }
    // Hide distinct threads in the supplied message set and queue remote Done requests.
    function markThreadsDone(messages) {
        if (!_canStartPublicOperation())
            return;
        let threadIds = _collectThreadIds(messages, false);
        if (threadIds.length === 0)
            return;
        operationApplied("threads_done", "", "", threadIds);
        _addPendingDoneThreadIds(threadIds);
        _queueThreadDoneSync(threadIds);
    }
    // Start the next Done request only when authentication is available and fetch/mutation work is idle.
    function processPendingDoneQueue() {
        if (!token || isOperating || isLoading)
            return;
        if (pendingThreadDoneIndex >= pendingThreadDoneQueue.length)
            return;
        let threadId = pendingThreadDoneQueue[pendingThreadDoneIndex];
        pendingThreadDoneIndex++;
        _compactDoneQueueIfNeeded();

        _runProviderMutation(providerApi ? providerApi.buildThreadActionRequest("done", threadId) : null, "thread_done_sync", threadId, "");
    }
    // Start the next read request only when authentication is available and fetch/mutation work is idle.
    function processPendingReadQueue() {
        if (!token || isOperating || isLoading)
            return;
        if (pendingThreadReadIndex >= pendingThreadReadQueue.length)
            return;
        let threadId = pendingThreadReadQueue[pendingThreadReadIndex];
        pendingThreadReadIndex++;
        _compactReadQueueIfNeeded();

        _runProviderMutation(providerApi ? providerApi.buildThreadActionRequest("read", threadId) : null, "thread_read_sync", threadId, "");
    }
    // Remove Done records older than the retention cutoff, preserving records with unknown dates.
    function pruneDoneThreadState(retentionMs) {
        let maxAge = Math.max(0, parseInt(retentionMs || 0));
        if (maxAge <= 0)
            return;
        let cutoff = Date.now() - maxAge;
        let next = {};
        let changed = false;
        for (let threadId in doneThreadState) {
            let entry = doneThreadState[threadId];
            let timestamp = _doneStateTimestampMs(entry);
            if (timestamp > 0 && timestamp < cutoff) {
                changed = true;
                continue;
            }
            next[threadId] = entry;
        }
        if (changed)
            doneThreadState = next;
    }
    // Invalidate in-flight mutations and clear pending queues, optionally retaining confirmed Done records.
    function resetState(clearDoneState) {
        operationGeneration = operationGeneration + 1;
        isOperating = false;
        pendingThreadDoneQueue = [];
        pendingThreadReadQueue = [];
        pendingDoneThreadState = ({});
        pendingDoneMessagesByThread = ({});
        pendingReadMessagesByThread = ({});
        pendingThreadDoneIndex = 0;
        pendingThreadReadIndex = 0;
        if (clearDoneState === undefined || clearDoneState)
            doneThreadState = ({});
    }
    // Restore confirmed Done records through the shared format migration.
    function setDoneThreadState(state) {
        doneThreadState = _normalizeDoneThreadState(state);
    }

    visible: false

    // =========================================================================
    //  PROCESS COMPONENT
    // =========================================================================

    Component {
        id: operationComponentDef

        Process {
            property string _buffer: ""
            property string actionType: "thread_read"
            property int generation: 0
            property string repositoryFullName: ""
            property string requestToken: ""
            property string threadId: ""

            stdinEnabled: true

            stdout: SplitParser {
                onRead: line => _buffer += line
            }

            onExited: exitCode => {
                if (generation !== operations.operationGeneration) {
                    destroy();
                    return;
                }

                if (exitCode !== 0)
                    PluginLogger.error("operate", "GitHub inbox operation failed with exit code " + exitCode);

                operations.isOperating = false;

                if (exitCode !== 0) {
                    operations._handleMutationFailure(actionType, threadId);
                    operations.operationError("Action failed. Check token permissions.");
                    Qt.callLater(operations._processPendingOperationQueues);
                    destroy();
                    return;
                }

                let statusCode = parseInt((_buffer || "").trim());
                if (!isNaN(statusCode) && statusCode >= GitHubConstants.httpSuccessMin && statusCode < GitHubConstants.httpSuccessMax) {
                    operations.operationApplied(actionType, threadId, repositoryFullName, []);
                } else {
                    operations._handleMutationFailure(actionType, threadId);
                    operations.operationError("Action failed (HTTP " + (isNaN(statusCode) ? "?" : statusCode) + ").");
                }

                Qt.callLater(operations._processPendingOperationQueues);
                destroy();
            }
            onStarted: {
                write("Authorization: token " + requestToken + "\n");
                stdinEnabled = false;
                requestToken = "";
            }
        }
    }
}
