// NotificationMutator.qml - Handles GitHub notification mutation operations
//
// Encapsulates mark-as-read, mark-as-unread, mark-done, repo-read, and
// mark-all-read operations. Applies optimistic local state updates and
// queues thread-done sync requests.

import QtQuick
import Quickshell.Io

Item {
    id: mutator
    visible: false

    // -- Configuration --------------------------------------------------------
    property string token: ""

    // -- State ----------------------------------------------------------------
    property bool isMutating: false
    property bool isLoading: false    // bound from outside — blocks mutations
    property var doneThreadState: ({})
    property var pendingThreadDoneQueue: []

    // -- Signals --------------------------------------------------------------
    signal mutationApplied(string actionType, string threadId, string repositoryFullName)
    signal mutationError(string errorMessage)
    signal stateUpdated()

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    function markThreadAsRead(threadId) {
        if (!threadId) return
        _runMutation(
            "PATCH",
            Constants.githubThreadApiPrefix + threadId,
            "thread_read", threadId, "", ""
        )
    }

    function markThreadAsUnread(threadId) {
        if (!threadId) return
        _runMutation(
            "PATCH",
            Constants.githubThreadApiPrefix + threadId,
            "thread_unread", threadId, "", "{\"read\":false}"
        )
    }

    function markThreadDone(threadId) {
        if (!threadId) return
        _runMutation(
            "DELETE",
            Constants.githubThreadApiPrefix + threadId,
            "thread_done", threadId, "", ""
        )
    }

    function markRepoDone(repositoryFullName, notifications) {
        if (!repositoryFullName) return

        var doneCopy = _cloneMap(doneThreadState)
        var threadIds = []

        for (var index = 0; index < notifications.length; index++) {
            var item = notifications[index]
            if (item.repository === repositoryFullName && item.threadId) {
                doneCopy[item.threadId] = true
                threadIds.push(item.threadId)
            }
        }

        if (threadIds.length === 0) return

        doneThreadState = doneCopy
        mutationApplied("repo_done", "", repositoryFullName)
        _queueThreadDoneSync(threadIds)
    }

    function markRepoAsRead(repositoryFullName) {
        if (!repositoryFullName) return

        var parts = repositoryFullName.split("/")
        if (parts.length !== 2) return

        var owner = encodeURIComponent(parts[0])
        var repo = encodeURIComponent(parts[1])
        _runMutation(
            "PUT",
            Constants.githubApiReposPrefix + owner + "/" + repo + "/notifications",
            "repo_read", "", repositoryFullName, ""
        )
    }

    function markAllAsRead() {
        _runMutation(
            "PUT",
            Constants.githubNotificationsApiUrl,
            "all_read", "", "", ""
        )
    }

    /// Apply mutation result to a notifications list and return updated state.
    function applyResult(actionType, threadId, repositoryFullName, notifications) {
        var updated = []
        var doneCopy = _cloneMap(doneThreadState)

        if (actionType === "thread_done_sync")
            return { items: notifications, unreadChanged: false }

        if (actionType === "all_read") {
            for (var allIndex = 0; allIndex < notifications.length; allIndex++)
                updated.push(_markAsReadItem(notifications[allIndex]))
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "repo_read") {
            for (var repoIndex = 0; repoIndex < notifications.length; repoIndex++) {
                var repoItem = notifications[repoIndex]
                if (repoItem.repository === repositoryFullName)
                    updated.push(_markAsReadItem(repoItem))
                else
                    updated.push(repoItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "repo_done") {
            for (var repoDoneIndex = 0; repoDoneIndex < notifications.length; repoDoneIndex++) {
                var repoDoneItem = notifications[repoDoneIndex]
                if (repoDoneItem.repository === repositoryFullName && repoDoneItem.threadId
                        && doneCopy[repoDoneItem.threadId])
                    continue
                updated.push(repoDoneItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "thread_done") {
            doneCopy[threadId] = true
            doneThreadState = doneCopy
            for (var doneIndex = 0; doneIndex < notifications.length; doneIndex++) {
                var doneItem = notifications[doneIndex]
                if (doneItem.threadId !== threadId)
                    updated.push(doneItem)
            }
            return { items: updated, unreadChanged: true }
        }

        if (actionType === "thread_unread") {
            if (doneCopy[threadId]) {
                delete doneCopy[threadId]
                doneThreadState = doneCopy
            }
            for (var unreadIndex = 0; unreadIndex < notifications.length; unreadIndex++) {
                var unreadItem = notifications[unreadIndex]
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

        // thread_read
        if (doneCopy[threadId]) {
            delete doneCopy[threadId]
            doneThreadState = doneCopy
        }
        for (var index = 0; index < notifications.length; index++) {
            var item = notifications[index]
            if (item.threadId === threadId)
                updated.push(_markAsReadItem(item))
            else
                updated.push(item)
        }
        return { items: updated, unreadChanged: true }
    }

    function processPendingDoneQueue() {
        if (!token || isMutating || isLoading)
            return
        if (pendingThreadDoneQueue.length === 0)
            return

        var nextQueue = pendingThreadDoneQueue.slice(0)
        var threadId = nextQueue.shift()
        pendingThreadDoneQueue = nextQueue

        _runMutation(
            "DELETE",
            Constants.githubThreadApiPrefix + threadId,
            "thread_done_sync", threadId, "", ""
        )
    }

    function resetState() {
        isMutating = false
        pendingThreadDoneQueue = []
        doneThreadState = ({})
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    function _runMutation(method, url, actionType, threadId, repositoryFullName, payloadJson) {
        if (!token || isMutating || isLoading)
            return

        isMutating = true

        var process = mutationComponentDef.createObject(mutator, {
            actionType: actionType || "thread_read",
            threadId: threadId || "",
            repositoryFullName: repositoryFullName || ""
        })

        var cmd = [
            "curl", "-sS",
            "-o", "/dev/null",
            "-w", Constants.curlStatusCodeFormat,
            "--connect-timeout", Constants.curlConnectTimeoutSeconds,
            "--max-time", Constants.curlMaxTimeSeconds,
            "-X", method,
            "-H", "Accept: " + Constants.httpAcceptHeader,
            "-H", "X-GitHub-Api-Version: " + Constants.githubApiVersionHeader,
            "-H", "Authorization: token " + token,
            url
        ]
        if (payloadJson)
            cmd.splice(cmd.length - 1, 0, "-H", "Content-Type: application/json", "-d", payloadJson)

        ApiCallStats.recordCalls(1)
        process.command = cmd
        process.running = true
    }

    function _queueThreadDoneSync(threadIds) {
        if (!threadIds || threadIds.length === 0) return

        var nextQueue = pendingThreadDoneQueue.slice(0)
        var seen = {}
        for (var existingIndex = 0; existingIndex < nextQueue.length; existingIndex++)
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

    // =========================================================================
    //  PROCESS COMPONENT
    // =========================================================================

    Component {
        id: mutationComponentDef

        Process {
            property string _buffer: ""
            property string actionType: "thread_read"
            property string threadId: ""
            property string repositoryFullName: ""

            stdout: SplitParser {
                onRead: line => _buffer += line
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[GitHubInbox] mutate:", line)
                }
            }

            onExited: exitCode => {
                mutator.isMutating = false

                if (exitCode !== 0) {
                    mutator.mutationError("Action failed. Check token permissions.")
                    destroy()
                    return
                }

                var statusCode = parseInt((_buffer || "").trim())
                if (!isNaN(statusCode)
                        && statusCode >= Constants.httpSuccessMin
                        && statusCode < Constants.httpSuccessMax) {
                    mutator.mutationApplied(actionType, threadId, repositoryFullName)
                } else {
                    mutator.mutationError("Action failed (HTTP "
                                          + (isNaN(statusCode) ? "?" : statusCode) + ").")
                }

                Qt.callLater(mutator.processPendingDoneQueue)
                destroy()
            }
        }
    }
}
