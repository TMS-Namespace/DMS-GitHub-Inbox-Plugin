// InboxOperationState.qml - owns optimistic read/Done snapshots and confirmed Done state.

import QtQuick
import "../../JS/Helpers/InboxOperationRules.js" as InboxOperationRules
import "../../JS/Storage/CacheSerialization.js" as CacheSerialization

QtObject {
    id: state

    property var doneThreadState: ({})
    readonly property var effectiveDoneThreadState: _mergeDoneStates(doneThreadState, pendingDoneThreadState)
    property var pendingDoneMessagesByThread: ({})
    property var pendingDoneThreadState: ({})
    property var pendingReadMessagesByThread: ({})

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

    // Record the Done source, message activity timestamp and local save time.
    function _doneStateEntryForThread(threadId, source, item) {
        let pendingMessage = item || pendingDoneMessagesByThread[threadId] || ({});
        return {
            source: String(source || "local"),
            updatedAt: pendingMessage.updatedAt || "",
            savedAt: Date.now()
        };
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

    // Save message copies before optimistic Done removal so failed requests can restore them.
    function _stashPendingDoneMessages(threadIds, messages) {
        let idSet = InboxOperationRules.threadIdSet(threadIds || []);
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
        let idSet = InboxOperationRules.threadIdSet(threadIds || []);
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
        let doneCopy = _cloneMap(doneThreadState);
        let pendingCopy = _cloneMap(pendingDoneThreadState);

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

        if (actionType === "repo_done" || actionType === "threads_done")
            _stashPendingDoneMessages(threadIds, messages);
        else if (actionType === "thread_done")
            _stashPendingDoneMessages([threadId], messages);
        else if (actionType === "thread_read_pending")
            _stashPendingReadMessages([threadId], messages);

        return InboxOperationRules.applyMessageAction(actionType, threadId, repositoryFullName, messages, threadIds);
    }

    // Inferred Done entries reopen whenever returned; locally marked entries reopen on newer activity.
    // GitHub's list response does not expose a Done flag:
    // https://docs.github.com/en/rest/activity/notifications#list-notifications-for-the-authenticated-user
    function clearReturnedDoneThreadState(messages) {
        let next = InboxOperationRules.reconcileReturnedDone(doneThreadState, messages);
        if (next !== doneThreadState)
            doneThreadState = next;
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

    // Remove Done records older than the retention cutoff, preserving records with unknown dates.
    function pruneDoneThreadState(retentionMs) {
        let maxAge = Math.max(0, parseInt(retentionMs || 0));
        if (maxAge <= 0)
            return;
        let next = InboxOperationRules.pruneDoneState(doneThreadState, Date.now() - maxAge);
        if (next !== doneThreadState)
            doneThreadState = next;
    }

    // Clear rollback snapshots and optionally retain confirmed Done entries.
    function reset(clearDoneState) {
        pendingDoneThreadState = ({});
        pendingDoneMessagesByThread = ({});
        pendingReadMessagesByThread = ({});
        if (clearDoneState === undefined || clearDoneState)
            doneThreadState = ({});
    }

    // Restore confirmed Done records through the shared format migration.
    function setDoneThreadState(state) {
        doneThreadState = _normalizeDoneThreadState(state);
    }
}
