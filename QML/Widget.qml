// Widget.qml - Main GitHub Inbox widget for DankMaterialShell

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "../JS/GitHubHelpers.js" as GitHub

PluginComponent {
    id: root

    layerNamespacePlugin: "github-inbox"

    // -- Settings-backed state ------------------------------------------------
    property string token: (pluginData.githubToken || "").trim()
    property int pollIntervalMs: GitHub.pollIntervalMs(pluginData.pollInterval)
    property int groupItemLimit: {
        var value = parseInt(pluginData.groupItemLimit || "25")
        if (isNaN(value))
            return 25
        return Math.max(1, Math.min(25, value))
    }
    property int fetchPageCount: {
        var value = parseInt(pluginData.fetchPages || "3")
        if (isNaN(value))
            return 3
        return Math.max(1, Math.min(10, value))
    }
    property int popupItems: {
        var value = parseInt(pluginData.popupItems || "5")
        if (isNaN(value))
            return 5
        return Math.max(1, Math.min(50, value))
    }
    property int titleLines: {
        var value = parseInt(pluginData.titleLines || "2")
        if (isNaN(value))
            return 2
        return Math.max(1, Math.min(6, value))
    }

    // -- Runtime state --------------------------------------------------------
    property var notifications: []
    property var notificationsForView: []
    property var pendingViewNotifications: []
    property int pendingViewIndex: 0
    property int unreadCount: 0
    property bool isLoading: false
    property bool isMutating: false
    property bool fetchQueued: false
    property string errorMessage: ""
    property real lastUpdated: 0
    property var doneThreadState: ({})
    property string fetchSplitToken: "__GH_PARTICIPATING_SPLIT__"
    property int parseRequestSeq: 0
    property int viewApplyChunkSize: 20
    property var expandedReposState: ({ "__defaultExpanded": true })

    property url githubIconPrimary: "https://github.com/favicon.ico"
    property url githubIconFallback: Qt.resolvedUrl("../Images/github-mark.svg")

    property int totalCount: notifications.length
    property int readCount: Math.max(0, notifications.length - unreadCount)
    property int shownCount: notificationsForView.length

    property string barCountText: GitHub.formatBarCount(unreadCount, totalCount, true)

    property string popoutDetails: {
        if (!token)
            return "Set your GitHub classic token in Settings"
        if (errorMessage)
            return errorMessage
        if (isLoading && notifications.length === 0)
            return "Loading notifications..."

        var counts = unreadCount + " unread / " + readCount + " read / " + totalCount + " total"
        var summary = counts + " - showing " + shownCount
        if (lastUpdated > 0)
            summary += " - updated " + GitHub.relativeTimeFromIso(new Date(lastUpdated).toISOString())
        return summary
    }

    // -- Polling --------------------------------------------------------------
    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        running: root.token !== ""
        repeat: true
        onTriggered: root.fetchNotifications()
    }

    Timer {
        id: viewApplyTimer
        interval: 8
        repeat: true
        onTriggered: root.applyViewChunk()
    }

    function queueViewNotifications(items) {
        var nextItems = (items || []).slice(0)
        pendingViewNotifications = nextItems
        pendingViewIndex = nextItems.length
        notificationsForView = nextItems
        viewApplyTimer.stop()
    }

    function applyViewChunk() {
        viewApplyTimer.stop()
    }

    function cloneExpandedState(state) {
        var copy = {}
        var source = state || {}
        for (var key in source)
            copy[key] = source[key]
        if (copy.__defaultExpanded === undefined)
            copy.__defaultExpanded = true
        return copy
    }

    onPollIntervalMsChanged: {
        pollTimer.interval = pollIntervalMs
        if (pollTimer.running)
            pollTimer.restart()
    }

    onTokenChanged: {
        if (!token) {
            notifications = []
            notificationsForView = []
            pendingViewNotifications = []
            pendingViewIndex = 0
            viewApplyTimer.stop()
            unreadCount = 0
            errorMessage = ""
            lastUpdated = 0
            fetchQueued = false
            parseRequestSeq = parseRequestSeq + 1
            isLoading = false
            expandedReposState = ({ "__defaultExpanded": true })
            return
        }
        fetchNotifications()
    }

    onGroupItemLimitChanged: {
        if (token)
            fetchNotifications()
    }

    onFetchPageCountChanged: {
        if (token)
            fetchNotifications()
    }

    Component.onCompleted: {
        if (token)
            fetchNotifications()
    }

    WorkerScript {
        id: parseWorker
        source: Qt.resolvedUrl("../JS/NotificationParserWorker.js")

        onMessage: function(message) {
            if (message.seq !== root.parseRequestSeq)
                return

            if (message.error) {
                root.isLoading = false
                root.notifications = []
                root.notificationsForView = []
                root.pendingViewNotifications = []
                root.pendingViewIndex = 0
                viewApplyTimer.stop()
                root.unreadCount = 0
                root.errorMessage = message.error
                root.lastUpdated = Date.now()
                if (root.fetchQueued) {
                    root.fetchQueued = false
                    Qt.callLater(root.fetchNotifications)
                }
                return
            }

            if (message.phase === "begin") {
                root.notifications = []
                root.notificationsForView = []
                root.pendingViewNotifications = []
                root.pendingViewIndex = 0
                root.unreadCount = parseInt(message.unreadCount || 0)
                root.errorMessage = ""
                root.lastUpdated = Date.now()
                root.isLoading = true

                if (parseInt(message.totalCount || 0) === 0) {
                    root.isLoading = false
                    if (root.fetchQueued) {
                        root.fetchQueued = false
                        Qt.callLater(root.fetchNotifications)
                    }
                }
                return
            }

            if (message.phase === "chunk") {
                var chunk = message.items || []
                if (chunk.length > 0) {
                    var nextNotifications = root.notifications.slice(0)
                    for (var index = 0; index < chunk.length; index++)
                        nextNotifications.push(chunk[index])
                    root.notifications = nextNotifications
                    root.notificationsForView = nextNotifications
                }

                if (message.isLast) {
                    root.isLoading = false
                    root.lastUpdated = Date.now()
                    if (root.fetchQueued) {
                        root.fetchQueued = false
                        Qt.callLater(root.fetchNotifications)
                    }
                }
                return
            }

            root.isLoading = false
            root.notifications = message.items || []
            root.unreadCount = parseInt(message.unreadCount || 0)
            root.queueViewNotifications(root.notifications)
            root.errorMessage = ""
            root.lastUpdated = Date.now()

            if (root.fetchQueued) {
                root.fetchQueued = false
                Qt.callLater(root.fetchNotifications)
            }
        }
    }

    // -- Process-based API calls ----------------------------------------------
    Component {
        id: fetchComponent

        Process {
            property var _chunks: []

            stdout: SplitParser {
                onRead: line => _chunks.push(line)
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[GitHubInbox] fetch:", line)
                }
            }

            onExited: exitCode => {
                if (exitCode !== 0) {
                    root.isLoading = false
                    root.errorMessage = "Request failed. Check token or network."
                    if (root.fetchQueued) {
                        root.fetchQueued = false
                        Qt.callLater(root.fetchNotifications)
                    }
                    destroy()
                    return
                }

                var nextSeq = root.parseRequestSeq + 1
                root.parseRequestSeq = nextSeq
                parseWorker.sendMessage({
                    seq: nextSeq,
                    payloadText: _chunks.join("\n") + "\n",
                    separator: root.fetchSplitToken,
                    allSegmentCount: root.fetchPageCount,
                    doneThreadState: root.doneThreadState,
                    chunkSize: 80
                })

                destroy()
            }
        }
    }

    Component {
        id: mutationComponent

        Process {
            property string _buffer: ""
            property string actionType: "thread_read"   // thread_read | thread_done | repo_read | all_read
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
                root.isMutating = false

                if (exitCode !== 0) {
                    root.errorMessage = "Action failed. Check token permissions."
                    destroy()
                    return
                }

                var statusCode = parseInt((_buffer || "").trim())
                if (!isNaN(statusCode) && statusCode >= 200 && statusCode < 300) {
                    root.applyMutationResult(actionType, threadId, repositoryFullName)
                    root.errorMessage = ""
                    root.lastUpdated = Date.now()
                } else {
                    root.errorMessage = "Action failed (HTTP " + (isNaN(statusCode) ? "?" : statusCode) + ")."
                }

                destroy()
            }
        }
    }

    function fetchNotifications() {
        if (!token || isMutating)
            return

        if (isLoading) {
            fetchQueued = true
            return
        }

        isLoading = true
        errorMessage = ""

        // Canonical data source from GitHub:
        // - full inbox (all=true)
        // - participation subset (all=true&participating=true)
        // We derive participation locally from the subset to avoid ambiguous participating=false behavior.
        var apiPageSize = 50
        var pages = Math.max(1, fetchPageCount)
        var baseQuery = "per_page=" + apiPageSize + "&all=true"
        var allBaseUrl = "https://api.github.com/notifications?" + baseQuery
        var participatingBaseUrl = allBaseUrl + "&participating=true"
        var command = ["curl"]

        function appendRequest(url) {
            if (command.length > 1)
                command.push("--next")
            command.push(
                "-sS",
                "--connect-timeout", "10",
                "--max-time", "20",
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2022-11-28",
                "-H", "Authorization: token " + token,
                "-w", "\n" + root.fetchSplitToken + "\n",
                url
            )
        }

        for (var page = 1; page <= pages; page++)
            appendRequest(allBaseUrl + "&page=" + page)

        for (var partPage = 1; partPage <= pages; partPage++)
            appendRequest(participatingBaseUrl + "&page=" + partPage)

        var process = fetchComponent.createObject(root)
        process.command = command
        process.running = true
    }

    function runMutation(method, url, actionType, threadId, repositoryFullName, payloadJson) {
        if (!token || isMutating || isLoading)
            return

        isMutating = true

        var process = mutationComponent.createObject(root, {
            actionType: actionType || "thread_read",
            threadId: threadId || "",
            repositoryFullName: repositoryFullName || ""
        })
        process.command = [
            "curl",
            "-sS",
            "-o", "/dev/null",
            "-w", "%{http_code}",
            "--connect-timeout", "10",
            "--max-time", "20",
            "-X", method,
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            "-H", "Authorization: token " + token,
            url
        ]
        if (payloadJson) {
            process.command.splice(process.command.length - 1, 0, "-H", "Content-Type: application/json", "-d", payloadJson)
        }
        process.running = true
    }

    function refreshNow() {
        if (!token) {
            errorMessage = "Set your GitHub token in Settings."
            return
        }
        fetchNotifications()
    }

    function _markAsReadItem(item) {
        var copy = {}
        for (var key in item)
            copy[key] = item[key]
        copy.unread = false
        return copy
    }

    function applyMutationResult(actionType, threadId, repositoryFullName) {
        var updated = []
        var doneCopy = {}
        for (var doneKey in doneThreadState) doneCopy[doneKey] = doneThreadState[doneKey]

        if (actionType === "all_read") {
            for (var allIndex = 0; allIndex < notifications.length; allIndex++)
                updated.push(_markAsReadItem(notifications[allIndex]))
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = 0
            return
        }

        if (actionType === "repo_read") {
            for (var repoIndex = 0; repoIndex < notifications.length; repoIndex++) {
                var repoItem = notifications[repoIndex]
                if (repoItem.repository === repositoryFullName) {
                    updated.push(_markAsReadItem(repoItem))
                    continue
                }
                updated.push(repoItem)
            }
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = recalculateUnread(updated)
            return
        }

        if (actionType === "thread_done") {
            doneCopy[threadId] = true
            doneThreadState = doneCopy
            for (var doneIndex = 0; doneIndex < notifications.length; doneIndex++) {
                var doneItem = notifications[doneIndex]
                if (doneItem.threadId !== threadId)
                    updated.push(doneItem)
            }
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = recalculateUnread(updated)
            return
        }

        if (actionType === "thread_unread") {
            if (doneCopy[threadId]) {
                delete doneCopy[threadId]
                doneThreadState = doneCopy
            }
            for (var unreadIndex = 0; unreadIndex < notifications.length; unreadIndex++) {
                var unreadItem = notifications[unreadIndex]
                if (unreadItem.threadId === threadId) {
                    var unreadCopy = {}
                    for (var unreadKey in unreadItem)
                        unreadCopy[unreadKey] = unreadItem[unreadKey]
                    unreadCopy.unread = true
                    updated.push(unreadCopy)
                    continue
                }
                updated.push(unreadItem)
            }
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = recalculateUnread(updated)
            return
        }

        // actionType === "thread_read"
        if (doneCopy[threadId]) {
            delete doneCopy[threadId]
            doneThreadState = doneCopy
        }
        for (var index = 0; index < notifications.length; index++) {
            var item = notifications[index]
            if (item.threadId === threadId) {
                var readCopy = _markAsReadItem(item)
                updated.push(readCopy)
                continue
            }
            updated.push(item)
        }

        notifications = updated
        queueViewNotifications(notifications)
        unreadCount = recalculateUnread(updated)
    }

    function recalculateUnread(items) {
        var count = 0
        for (var index = 0; index < items.length; index++) {
            if (items[index].unread)
                count++
        }
        return count
    }

    function markThreadAsRead(threadId) {
        if (!threadId)
            return
        runMutation(
            "PATCH",
            "https://api.github.com/notifications/threads/" + threadId,
            "thread_read",
            threadId,
            "",
            ""
        )
    }

    function markThreadAsUnread(threadId) {
        if (!threadId)
            return
        runMutation(
            "PATCH",
            "https://api.github.com/notifications/threads/" + threadId,
            "thread_unread",
            threadId,
            "",
            "{\"read\":false}"
        )
    }

    function markThreadDone(threadId) {
        if (!threadId)
            return
        runMutation(
            "DELETE",
            "https://api.github.com/notifications/threads/" + threadId,
            "thread_done",
            threadId,
            "",
            ""
        )
    }

    function markRepoAsRead(repositoryFullName) {
        if (!repositoryFullName)
            return

        var parts = repositoryFullName.split("/")
        if (parts.length !== 2)
            return

        var owner = encodeURIComponent(parts[0])
        var repo = encodeURIComponent(parts[1])
        runMutation(
            "PUT",
            "https://api.github.com/repos/" + owner + "/" + repo + "/notifications",
            "repo_read",
            "",
            repositoryFullName,
            ""
        )
    }

    function markAllAsRead() {
        runMutation(
            "PUT",
            "https://api.github.com/notifications",
            "all_read",
            "",
            "",
            ""
        )
    }

    // =======================================================================
    //  BAR PILLS
    // =======================================================================

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            GitHubIcon {
                size: Math.max(12, root.iconSize - 4)
                iconOpacity: 0.74
                sourcePrimary: root.githubIconPrimary
                sourceFallback: root.githubIconFallback
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.barCountText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            GitHubIcon {
                size: Math.max(12, root.iconSize - 4)
                iconOpacity: 0.74
                sourcePrimary: root.githubIconPrimary
                sourceFallback: root.githubIconFallback
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.barCountText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // =======================================================================
    //  POPOUT
    // =======================================================================

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "GitHub Inbox"
            detailsText: root.popoutDetails
            showCloseButton: false

            PopoutPanel {
                width: parent.width
                implicitHeight: root.popoutHeight
                                - popout.headerHeight
                                - popout.detailsHeight
                                - Theme.spacingXL

                notifications: root.notificationsForView
                unreadCount: root.unreadCount
                tokenConfigured: root.token !== ""
                isLoading: root.isLoading
                isMutating: root.isMutating
                errorMessage: root.errorMessage
                headerOffset: popout.headerHeight + popout.detailsHeight
                titleLines: root.titleLines
                groupItemLimit: root.groupItemLimit
                expandedReposState: root.expandedReposState

                onRefreshNow: root.refreshNow()
                onMarkAllRead: root.markAllAsRead()
                onMarkRepoRead: function(repositoryFullName) { root.markRepoAsRead(repositoryFullName) }
                onMarkThreadRead: function(threadId) { root.markThreadAsRead(threadId) }
                onMarkThreadUnread: function(threadId) { root.markThreadAsUnread(threadId) }
                onMarkThreadDone: function(threadId) { root.markThreadDone(threadId) }
                onClosePopout: root.closePopout()
                onPersistExpandedRepos: function(state) { root.expandedReposState = root.cloneExpandedState(state) }
            }
        }
    }

    popoutWidth: 560
    popoutHeight: {
        var items = Math.max(1, popupItems)
        var rowHeight = 40 + titleLines * 16
        var estimatedRepoHeaders = Math.max(1, Math.ceil(items / 3))
        var estimated = (items * rowHeight) + (estimatedRepoHeaders * 30) + 130
        return Math.max(240, Math.min(1000, estimated))
    }
}
