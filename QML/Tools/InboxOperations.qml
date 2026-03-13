// InboxOperations.qml - Handles GitHub inbox message operations
//
// Encapsulates mark-as-read, mark-as-unread, mark-done, repo-read, and
// mark-all-read operations. Applies optimistic local state updates and
// queues thread-done sync requests.

import QtQuick
import Quickshell.Io

Item {
    id: operations
    visible: false

    // -- Configuration --------------------------------------------------------
    property string token: ""

    // -- State ----------------------------------------------------------------
    property bool isOperating: false
    property bool isLoading: false    // bound from outside — blocks operations
    property var doneThreadState: ({})
    property var pendingThreadDoneQueue: []

    // -- Signals --------------------------------------------------------------
    signal operationApplied(string actionType, string threadId, string repositoryFullName)
    signal operationError(string errorMessage)
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

    function markRepoDone(repositoryFullName, messages) {
        if (!repositoryFullName) return

        var doneCopy = _cloneMap(doneThreadState)
        var threadIds = []

        for (var index = 0; index < messages.length; index++) {
            var item = messages[index]
            if (item.repository === repositoryFullName && item.threadId) {
                doneCopy[item.threadId] = true
                threadIds.push(item.threadId)
            }
        }

        if (threadIds.length === 0) return

        doneThreadState = doneCopy
        operationApplied("repo_done", "", repositoryFullName)
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
            Constants.githubInboxApiUrl,
            "all_read", "", "", ""
        )
    }

    /// Apply operation result to a messages list and return updated state.
    function applyResult(actionType, threadId, repositoryFullName, messages) {
        var updated = []
        var doneCopy = _cloneMap(doneThreadState)

        if (actionType === "thread_done_sync")
            return { items: messages, unreadChanged: false }

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
            for (var repoDoneIndex = 0; repoDoneIndex < messages.length; repoDoneIndex++) {
                var repoDoneItem = messages[repoDoneIndex]
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
            for (var doneIndex = 0; doneIndex < messages.length; doneIndex++) {
                var doneItem = messages[doneIndex]
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

        // thread_read
        if (doneCopy[threadId]) {
            delete doneCopy[threadId]
            doneThreadState = doneCopy
        }
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
        isOperating = false
        pendingThreadDoneQueue = []
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
        id: operationComponentDef

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
                        console.warn("[GitHubInbox] operate:", line)
                }
            }

            onExited: exitCode => {
                operations.isOperating = false

                if (exitCode !== 0) {
                    operations.operationError("Action failed. Check token permissions.")
                    destroy()
                    return
                }

                var statusCode = parseInt((_buffer || "").trim())
                if (!isNaN(statusCode)
                        && statusCode >= Constants.httpSuccessMin
                        && statusCode < Constants.httpSuccessMax) {
                    operations.operationApplied(actionType, threadId, repositoryFullName)
                } else {
                    operations.operationError("Action failed (HTTP "
                                          + (isNaN(statusCode) ? "?" : statusCode) + ").")
                }

                Qt.callLater(operations.processPendingDoneQueue)
                destroy()
            }
        }
    }
}
