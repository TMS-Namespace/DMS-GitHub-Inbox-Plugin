// InboxOperationRules.js - pure thread selection and message transformations for inbox actions.

.pragma library

// Build a membership map from nonempty thread IDs.
function threadIdSet(threadIds) {
    var result = {};
    var ids = threadIds || [];
    for (var index = 0; index < ids.length; index++) {
        if (ids[index]) result[ids[index]] = true;
    }
    return result;
}

// Select each thread once, optionally restricting the result to unread messages.
function collectThreadIds(messages, unreadOnly) {
    var result = [];
    var seen = {};
    var items = messages || [];
    for (var index = 0; index < items.length; index++) {
        var item = items[index];
        if (!item || !item.threadId || seen[item.threadId] || (unreadOnly && !item.unread)) continue;
        seen[item.threadId] = true;
        result.push(item.threadId);
    }
    return result;
}

// Copy a message before changing its read state.
function withUnread(item, unread) {
    var copy = {};
    for (var key in item) copy[key] = item[key];
    copy.unread = unread;
    return copy;
}

// Return a new Done map only when a returned thread invalidates its local Done record.
function reconcileReturnedDone(doneState, messages) {
    var result = null;
    var source = doneState || {};
    var items = messages || [];
    for (var index = 0; index < items.length; index++) {
        var message = items[index] || {};
        var threadId = String(message.threadId || "").trim();
        var entry = (result || source)[threadId];
        if (!threadId || !entry || typeof entry !== "object") continue;
        var reopened = entry.source === "github_missing_from_complete_refresh";
        if (entry.source === "local") {
            var returnedTime = message.updatedAtMs || Date.parse(message.updatedAt || "") || 0;
            var boundary = Date.parse(entry.updatedAt || "") || parseInt(entry.savedAt || 0);
            reopened = returnedTime > 0 && boundary > 0 && returnedTime > boundary;
        }
        if (!reopened) continue;
        if (!result) result = Object.assign({}, source);
        delete result[threadId];
    }
    return result || source;
}

// Remove dated Done records older than the cutoff while retaining records with no usable timestamp.
function pruneDoneState(doneState, cutoff) {
    var source = doneState || {};
    var result = null;
    for (var threadId in source) {
        var entry = source[threadId];
        if (!entry || typeof entry !== "object") continue;
        var updatedTime = Date.parse(entry.updatedAt || "") || 0;
        var timestamp = updatedTime > 0 ? updatedTime : parseInt(entry.savedAt || 0) || 0;
        if (timestamp <= 0 || timestamp >= cutoff) continue;
        if (!result) result = Object.assign({}, source);
        delete result[threadId];
    }
    return result || source;
}

// Apply a successful or optimistic action without mutating the caller's messages.
function applyMessageAction(actionType, threadId, repositoryFullName, messages, threadIds) {
    var selected = threadIdSet(threadIds);
    var updated = [];
    for (var index = 0; index < messages.length; index++) {
        var item = messages[index];
        if (
            actionType === "repo_done" &&
            item.repository === repositoryFullName &&
            item.threadId &&
            selected[item.threadId]
        )
            continue;
        if (actionType === "threads_done" && item.threadId && selected[item.threadId]) continue;
        if (actionType === "thread_done" && item.threadId === threadId) continue;
        if (
            actionType === "all_read" ||
            (actionType === "repo_read" && item.repository === repositoryFullName) ||
            (actionType === "threads_read" && item.threadId && selected[item.threadId])
        ) {
            updated.push(withUnread(item, false));
        } else if (actionType === "thread_unread" && item.threadId === threadId) {
            updated.push(withUnread(item, true));
        } else if (
            actionType !== "repo_done" &&
            actionType !== "threads_done" &&
            actionType !== "thread_done" &&
            actionType !== "all_read" &&
            actionType !== "repo_read" &&
            actionType !== "threads_read" &&
            actionType !== "thread_unread" &&
            item.threadId === threadId
        ) {
            updated.push(withUnread(item, false));
        } else {
            updated.push(item);
        }
    }
    return { items: updated, unreadChanged: true };
}
