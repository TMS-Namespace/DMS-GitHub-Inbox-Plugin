// Widget.qml - Main GitHub Inbox widget orchestrator for DankMaterialShell
//
// This file is the top-level PluginComponent that wires together the
// extracted sub-components.  Business logic lives in the delegates:
//   - InboxFetcher        — curl-based inbox message fetching + WorkerScript
//   - AuthorFetcher       — author data queue, dedup, fetching
//   - InboxOperations     — mark read/done/unread operations
//   - AvatarPreloader     — hidden Image warm-up cache
//   - CacheCoordinator    — disk cache bridge (messages, authors, avatars)
//   - AuthorUtils         — pure helper functions (singleton)

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

    layerNamespacePlugin: Constants.pluginNamespaceId

    // =========================================================================
    //  SETTINGS-BACKED STATE
    // =========================================================================

    property string token: (pluginData.githubToken || "").trim()
    property int pollIntervalMs: GitHub.pollIntervalMs(pluginData.pollInterval)
    property int groupItemLimit: {
        var value = parseInt(pluginData.groupItemLimit || Constants.defaultGroupItemLimit)
        if (isNaN(value))
            return Constants.defaultGroupItemLimit
        return Math.max(Constants.minGroupItemLimit, Math.min(Constants.maxGroupItemLimit, value))
    }
    property int fetchPageCount: {
        var value = parseInt(pluginData.fetchPages || Constants.defaultFetchPageCount)
        if (isNaN(value))
            return Constants.defaultFetchPageCount
        return Math.max(Constants.minFetchPageCount, Math.min(Constants.maxFetchPageCount, value))
    }
    property int popupHeightUnits: {
        var rawValue = pluginData.popupHeight
        if (rawValue === undefined || rawValue === "")
            rawValue = pluginData.popupItems || Constants.defaultPopupHeightUnits
        var value = parseInt(rawValue)
        if (isNaN(value))
            return Constants.defaultPopupHeightUnits
        return Math.max(Constants.minPopupHeightUnits, Math.min(Constants.maxPopupHeightUnits, value))
    }
    property int titleLines: {
        var value = parseInt(pluginData.titleLines || Constants.defaultTitleLines)
        if (isNaN(value))
            return Constants.defaultTitleLines
        return Math.max(Constants.minTitleLines, Math.min(Constants.maxTitleLines, value))
    }
    property bool loadAuthorInfo: GitHub.pluginDataBool(pluginData.loadAuthorInfo, true)
    property bool enableNotifications: GitHub.pluginDataBool(pluginData.enableNotifications, Constants.defaultEnableNotifications)
    property int cacheTtlMinutes: {
        var value = parseInt(pluginData.cacheTtlMinutes || Constants.defaultCacheTtlMinutes)
        if (isNaN(value))
            return Constants.defaultCacheTtlMinutes
        return Math.max(Constants.minCacheTtlMinutes, Math.min(Constants.maxCacheTtlMinutes, value))
    }

    // =========================================================================
    //  RUNTIME STATE
    // =========================================================================

    property real _perfStartMs: 0

    property var inboxMessages: []
    property var messagesForView: []
    property var pendingViewMessages: []
    property int pendingViewIndex: 0
    property int unreadCount: 0
    property string errorMessage: ""
    property real lastUpdated: 0
    property var expandedReposState: ({ [Constants.expandedStateDefaultKey]: true })
    property var authorsByThread: ({})
    property var _previousThreadIds: ({})

    property url githubIconPrimary: Constants.githubFaviconUrl
    property url githubIconFallback: Qt.resolvedUrl("../Images/github-mark.svg")

    // -- Computed properties --------------------------------------------------
    property int totalCount: inboxMessages.length
    property int readCount: Math.max(0, inboxMessages.length - unreadCount)
    property string barCountText: unreadCount > 0 ? GitHub.formatCountValue(unreadCount) : ""

    property string popoutDetails: {
        if (!token)
            return "Set your GitHub classic token in Settings"
        if (errorMessage)
            return errorMessage
        if (fetcher.isLoading && inboxMessages.length === 0)
            return "Loading messages..."

        var counts = unreadCount + " unread / " + readCount + " read / " + totalCount + " total"
        return counts
    }

    // =========================================================================
    //  SUB-COMPONENTS
    // =========================================================================

    CacheCoordinator {
        id: cacheCoord
        cacheTtlMinutes: root.cacheTtlMinutes
        onCacheReady: root._onCacheReady()
        onAvatarCachedLocally: function(login, localUrl) {
            avatarPreloader.updateEntrySource(login, localUrl)
            root._propagateLocalAvatar(login, localUrl)
        }
    }

    InboxFetcher {
        id: fetcher
        token: root.token
        fetchPageCount: root.fetchPageCount
        doneThreadState: operations.doneThreadState

        onFetchBegin: function(totalCount, unreadCount) {
            root._perfLog("onFetchBegin — total=" + totalCount + " unread=" + unreadCount)
            root._saveCurrentThreadIds()
            root.inboxMessages = []
            root.messagesForView = []
            root.pendingViewMessages = []
            root.pendingViewIndex = 0
            authorFetch.resetState()
            authorFetch.prefetchPending = totalCount > 0
            root.unreadCount = unreadCount
            root.errorMessage = ""
            root.lastUpdated = Date.now()

            if (totalCount === 0)
                _finalizeFetchCycle()
        }

        onFetchChunk: function(chunk, isLast) {
            root._perfLog("onFetchChunk — size=" + chunk.length + " isLast=" + isLast)
            if (chunk.length > 0) {
                cacheCoord.resolveMessageAvatars(chunk)
                var nextMessages = root.inboxMessages.slice(0)
                for (var index = 0; index < chunk.length; index++)
                    nextMessages.push(chunk[index])
                root.inboxMessages = nextMessages
                root.messagesForView = nextMessages
                avatarPreloader.queueFromMessages(chunk)
                authorFetch.prefetchForMessages(chunk)
            }

            if (isLast) {
                root.lastUpdated = Date.now()
                cacheCoord.updateMessages(root.inboxMessages)
                root._detectAndNotifyNewMessages(root.inboxMessages)
                _tryFinalizeAuthorPrefetch()
            }
        }

        onFetchComplete: function(items, unreadCount) {
            root._perfLog("onFetchComplete — items=" + items.length + " unread=" + unreadCount)
            cacheCoord.resolveMessageAvatars(items)
            root.inboxMessages = items
            root.unreadCount = unreadCount
            root._queueViewMessages(root.inboxMessages)
            avatarPreloader.queueFromMessages(root.inboxMessages)
            authorFetch.prefetchPending = root.inboxMessages.length > 0
            authorFetch.prefetchForMessages(root.inboxMessages)
            root.errorMessage = ""
            root.lastUpdated = Date.now()
            cacheCoord.updateMessages(root.inboxMessages)
            root._detectAndNotifyNewMessages(root.inboxMessages)
            _tryFinalizeAuthorPrefetch()
        }

        onFetchError: function(errorMessage) {
            root._perfLog("onFetchError — " + errorMessage)
            root.inboxMessages = []
            root.messagesForView = []
            root.pendingViewMessages = []
            root.pendingViewIndex = 0
            viewApplyTimer.stop()
            authorFetch.resetState()
            root.unreadCount = 0
            root.errorMessage = errorMessage
            root.lastUpdated = Date.now()
            Qt.callLater(operations.processPendingDoneQueue)
        }

        onAuthorResultReceived: function(message) {
            authorFetch.handleAuthorResult(message)
        }
    }

    AuthorFetcher {
        id: authorFetch
        token: root.token
        loadAuthorInfo: root.loadAuthorInfo
        authorsByThreadRef: root.authorsByThread
        workerSendMessage: fetcher.sendWorkerMessage

        onAuthorsMerged: function(mergedAuthors, preloadAuthors, changedThreadIds) {
            // Only resolve avatar URLs for threads that actually changed
            for (var i = 0; i < changedThreadIds.length; i++) {
                var cid = changedThreadIds[i]
                if (mergedAuthors[cid])
                    cacheCoord.resolveAuthorAvatars(mergedAuthors[cid])
            }

            root.authorsByThread = mergedAuthors
            cacheCoord.bulkUpdateAuthors(mergedAuthors)

            if (preloadAuthors.length > 0)
                avatarPreloader.queueFromAuthors(preloadAuthors)
        }

        onAuthorFetchedAtChanged: function(threadId, updatedAt) {
            cacheCoord.updateAuthorFetchedAt(threadId, updatedAt)
        }

        onExpansionUrlsDiscovered: function(threadId, urls) {
            authorFetch.enqueueAuthorUrls(threadId, urls)
        }

        onPrefetchMaybeComplete: root._tryFinalizeAuthorPrefetch()
    }

    InboxOperations {
        id: operations
        token: root.token
        isLoading: fetcher.isLoading

        onOperationApplied: function(actionType, threadId, repositoryFullName) {
            var result = operations.applyResult(actionType, threadId, repositoryFullName, root.inboxMessages)
            root.inboxMessages = result.items
            root._queueViewMessages(root.inboxMessages)
            if (result.unreadChanged)
                root.unreadCount = _recalculateUnread(root.inboxMessages)
            root.errorMessage = ""
            root.lastUpdated = Date.now()
        }

        onOperationError: function(errorMessage) {
            root.errorMessage = errorMessage
        }
    }

    AvatarPreloader {
        id: avatarPreloader
    }

    Component {
        id: notifyProcessDef

        Process {
            onExited: destroy()
        }
    }

    // =========================================================================
    //  TIMERS
    // =========================================================================

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        running: root.token !== ""
        repeat: true
        onTriggered: root._fetchInbox()
    }

    Timer {
        id: viewApplyTimer
        interval: Constants.viewApplyTimerIntervalMs
        repeat: true
        onTriggered: root._applyViewChunk()
    }

    // =========================================================================
    //  ORCHESTRATION LOGIC
    // =========================================================================

    function _perfLog(label) {
        if (!Constants.debugPerformanceLogging) return
        var elapsed = (Date.now() - _perfStartMs).toFixed(0)
        console.warn("[GitHubInbox PERF] +" + elapsed + "ms  " + label)
    }

    function _fetchInbox() {
        _perfLog("_fetchInbox — called")
        if (!token || operations.isOperating)
            return
        fetcher.fetch()
        _perfLog("_fetchInbox — fetch() dispatched")
    }

    function _refreshNow() {
        if (!token) {
            errorMessage = "Set your GitHub token in Settings."
            return
        }
        _fetchInbox()
    }

    // -- Notification helpers -------------------------------------------------

    /// When an avatar is downloaded to disk, update all live data that still
    /// holds remote URLs for that login so the view switches to the local file.
    function _propagateLocalAvatar(login, localUrl) {
        if (!login || !localUrl)
            return

        // 1. Update repositoryOwnerAvatarUrl in inboxMessages
        var messagesChanged = false
        for (var mi = 0; mi < inboxMessages.length; mi++) {
            var msg = inboxMessages[mi]
            if ((msg.repositoryOwnerLogin || "") === login
                    && msg.repositoryOwnerAvatarUrl !== localUrl) {
                msg.repositoryOwnerAvatarUrl = localUrl
                messagesChanged = true
            }
        }
        if (messagesChanged) {
            // Force binding re-evaluation by reassigning the array
            inboxMessages = inboxMessages.slice(0)
            messagesForView = inboxMessages
        }

        // 2. Update author avatarUrl in authorsByThread
        var authorsChanged = false
        for (var tid in authorsByThread) {
            var authors = authorsByThread[tid]
            if (!authors)
                continue
            for (var ai = 0; ai < authors.length; ai++) {
                if ((authors[ai].login || "") === login
                        && authors[ai].avatarUrl !== localUrl) {
                    authors[ai].avatarUrl = localUrl
                    authorsChanged = true
                }
            }
        }
        if (authorsChanged) {
            var nextAuthors = {}
            for (var copyTid in authorsByThread)
                nextAuthors[copyTid] = authorsByThread[copyTid]
            authorsByThread = nextAuthors
        }
    }

    function _saveCurrentThreadIds() {
        var ids = {}
        for (var i = 0; i < inboxMessages.length; i++) {
            var tid = inboxMessages[i].threadId
            if (tid)
                ids[tid] = true
        }
        _previousThreadIds = ids
    }

    function _detectAndNotifyNewMessages(items) {
        if (!enableNotifications)
            return

        var prevIds = _previousThreadIds
        var hasPrev = false
        for (var k in prevIds) { hasPrev = true; break }
        if (!hasPrev)
            return

        var newMessages = []
        for (var i = 0; i < items.length; i++) {
            var tid = items[i].threadId
            if (tid && !prevIds[tid])
                newMessages.push(items[i])
        }

        if (newMessages.length === 0)
            return

        _sendDesktopNotification(newMessages)
    }

    function _sendDesktopNotification(newMessages) {
        var body = ""
        var maxLines = Constants.notificationMaxLines

        if (newMessages.length === 1) {
            var lines = (newMessages[0].title || "").split("\n")
            var trimmed = []
            for (var i = 0; i < Math.min(maxLines, lines.length); i++) {
                var line = lines[i].trim()
                if (line)
                    trimmed.push(line)
            }
            body = trimmed.join("\n") || "New inbox message"
        } else {
            var count = Math.min(maxLines, newMessages.length)
            var parts = []
            for (var j = 0; j < count; j++) {
                var title = (newMessages[j].title || "").split("\n")[0].trim()
                parts.push(title || "New message")
            }
            body = parts.join("\n")
            if (newMessages.length > maxLines)
                body += "\n\u2026 and " + (newMessages.length - maxLines) + " more"
        }

        var summary = newMessages.length === 1
            ? "New GitHub Inbox Message"
            : newMessages.length + " New GitHub Inbox Messages"

        var iconPath = _resolveNotificationIcon(newMessages)

        var proc = notifyProcessDef.createObject(root)
        var cmd = ["notify-send",
            "-a", Constants.notificationAppName,
            "-t", String(Constants.notificationExpireMs)]
        if (iconPath)
            cmd.push("-i", iconPath)
        cmd.push(summary, body)
        proc.command = cmd
        proc.running = true
    }

    function _resolveNotificationIcon(newMessages) {
        // If all messages are from a single repo and we have a cached avatar, use it
        var firstRepo = (newMessages[0].repositoryOwnerLogin || "").trim()
        if (firstRepo) {
            var singleRepo = true
            for (var i = 1; i < newMessages.length; i++) {
                if ((newMessages[i].repositoryOwnerLogin || "").trim() !== firstRepo) {
                    singleRepo = false
                    break
                }
            }
            if (singleRepo) {
                var avatarUrl = (newMessages[0].repositoryOwnerAvatarUrl || "").toString()
                if (avatarUrl.indexOf("file://") === 0)
                    return avatarUrl.substring(7)
            }
        }

        // Fall back to the bundled GitHub icon
        var fallback = githubIconFallback.toString()
        if (fallback.indexOf("file://") === 0)
            return fallback.substring(7)
        return ""
    }

    // -- Cache ready ----------------------------------------------------------

    // Temporary state for deferred cache-load phases
    property var _pendingCacheState: null

    function _onCacheReady() {
        _perfLog("_onCacheReady (Phase 1) — start")
        if (!token) return

        var cached = cacheCoord.loadCachedState()
        _perfLog("_onCacheReady — loadCachedState done, msgs=" + cached.messages.length)

        // Phase 1: Load messages for immediate bar-pill display
        if (cached.messages.length > 0) {
            cacheCoord.resolveMessageAvatars(cached.messages)
            inboxMessages = cached.messages
            unreadCount = _recalculateUnread(cached.messages)
            _queueViewMessages(cached.messages)
            lastUpdated = cached.timestamp
        }

        // Defer heavier work (author resolution, preloader) to separate frames
        _pendingCacheState = cached
        _perfLog("_onCacheReady (Phase 1) — end")
        Qt.callLater(_onCacheReadyPhase2)
    }

    function _onCacheReadyPhase2() {
        _perfLog("_onCacheReadyPhase2 — start")
        var cached = _pendingCacheState
        if (!cached) return

        // Phase 2: Load cached authors and resolve their avatars
        var resolvedAuthors = {}
        var cachedAuthors = cached.authorsByThread
        if (cachedAuthors && typeof cachedAuthors === "object") {
            for (var tid in cachedAuthors) {
                var authors = cachedAuthors[tid]
                if (authors && authors.length > 0) {
                    cacheCoord.resolveAuthorAvatars(authors)
                    resolvedAuthors[tid] = authors
                }
            }
            authorsByThread = resolvedAuthors
        }

        // Load cached author fetch timestamps
        var cachedFetchedAt = cached.authorFetchedAt
        if (cachedFetchedAt && typeof cachedFetchedAt === "object") {
            for (var fid in cachedFetchedAt)
                authorFetch.fetchedAtUpdatedAt[fid] = cachedFetchedAt[fid]
        }

        // Defer preloader + fetch to yet another frame
        _pendingCacheState = { messages: cached.messages, resolvedAuthors: resolvedAuthors }
        _perfLog("_onCacheReadyPhase2 — end")
        Qt.callLater(_onCacheReadyPhase3)
    }

    function _onCacheReadyPhase3() {
        _perfLog("_onCacheReadyPhase3 — start")
        var state = _pendingCacheState
        _pendingCacheState = null
        if (!state) return

        // Phase 3: Populate avatar preloader in one batch
        var messages = state.messages || []
        var resolvedAuthors = state.resolvedAuthors || {}
        var allPreloadAuthors = []
        for (var mi = 0; mi < messages.length; mi++) {
            var msg = messages[mi]
            allPreloadAuthors.push({
                login: msg.repositoryOwnerLogin || "",
                avatarUrl: msg.repositoryOwnerAvatarUrl || "",
                htmlUrl: msg.repositoryOwnerLogin
                    ? (Constants.githubWebBaseUrl + "/" + encodeURIComponent(msg.repositoryOwnerLogin))
                    : ""
            })
        }
        for (var atid in resolvedAuthors) {
            var authorList = resolvedAuthors[atid] || []
            for (var ai = 0; ai < authorList.length; ai++)
                allPreloadAuthors.push(authorList[ai])
        }
        _perfLog("_onCacheReadyPhase3 — preload authors count=" + allPreloadAuthors.length)
        if (allPreloadAuthors.length > 0)
            avatarPreloader.queueFromAuthors(allPreloadAuthors)

        _perfLog("_onCacheReadyPhase3 — end, scheduling _fetchInbox")
        // Finally, start the network fetch
        Qt.callLater(_fetchInbox)
    }

    function _tryFinalizeAuthorPrefetch() {
        if (!authorFetch.prefetchPending)
            return
        if (authorFetch.requestsInFlight > 0 || authorFetch.requestQueue.length > 0)
            return
        if (fetcher.isLoading)
            return

        _pruneAuthorCaches()
        ApiCallStats.recordRefreshComplete()
        authorFetch.prefetchPending = false

        Qt.callLater(operations.processPendingDoneQueue)
        fetcher.retryIfQueued()
    }

    function _finalizeFetchCycle() {
        ApiCallStats.recordRefreshComplete()
        fetcher.retryIfQueued()
    }

    function _pruneAuthorCaches() {
        var keep = {}
        for (var index = 0; index < inboxMessages.length; index++) {
            var threadId = inboxMessages[index].threadId
            if (threadId)
                keep[threadId] = true
        }

        var nextAuthors = {}
        for (var authorThreadId in authorsByThread) {
            if (keep[authorThreadId])
                nextAuthors[authorThreadId] = authorsByThread[authorThreadId]
        }

        var nextFetchedUrls = {}
        for (var fetchedThreadId in authorFetch.fetchedUrlsByThread) {
            if (keep[fetchedThreadId])
                nextFetchedUrls[fetchedThreadId] = authorFetch.fetchedUrlsByThread[fetchedThreadId]
        }

        var nextFetchedUpdatedAt = {}
        for (var updatedAtThreadId in authorFetch.fetchedAtUpdatedAt) {
            if (keep[updatedAtThreadId])
                nextFetchedUpdatedAt[updatedAtThreadId] = authorFetch.fetchedAtUpdatedAt[updatedAtThreadId]
        }

        authorsByThread = nextAuthors
        authorFetch.fetchedUrlsByThread = nextFetchedUrls
        authorFetch.fetchedAtUpdatedAt = nextFetchedUpdatedAt

        var keepIds = []
        for (var keepId in keep)
            keepIds.push(keepId)
        cacheCoord.pruneToThreads(keepIds)
    }

    // -- View helpers ---------------------------------------------------------

    function _queueViewMessages(items) {
        var nextItems = (items || []).slice(0)
        pendingViewMessages = nextItems
        pendingViewIndex = nextItems.length
        messagesForView = nextItems
        viewApplyTimer.stop()
    }

    function _applyViewChunk() {
        viewApplyTimer.stop()
    }

    function _recalculateUnread(items) {
        var count = 0
        for (var index = 0; index < items.length; index++) {
            if (items[index].unread)
                count++
        }
        return count
    }

    function _cloneExpandedState(state) {
        var copy = {}
        var source = state || {}
        for (var key in source)
            copy[key] = source[key]
        if (copy[Constants.expandedStateDefaultKey] === undefined)
            copy[Constants.expandedStateDefaultKey] = true
        return copy
    }

    // =========================================================================
    //  PROPERTY-CHANGE HANDLERS
    // =========================================================================

    onPollIntervalMsChanged: {
        pollTimer.interval = pollIntervalMs
        if (pollTimer.running)
            pollTimer.restart()
    }

    onTokenChanged: {
        _perfLog("onTokenChanged — token=" + (token ? "set" : "empty") + " cacheCoord.initialized=" + cacheCoord.initialized)
        if (!token) {
            inboxMessages = []
            messagesForView = []
            pendingViewMessages = []
            pendingViewIndex = 0
            viewApplyTimer.stop()
            unreadCount = 0
            errorMessage = ""
            lastUpdated = 0
            fetcher.cancel()
            authorFetch.clearAllState()
            operations.resetState()
            avatarPreloader.reset()
            authorsByThread = ({})
            expandedReposState = ({ [Constants.expandedStateDefaultKey]: true })
            _previousThreadIds = ({})
            return
        }
        if (cacheCoord.initialized)
            _fetchInbox()
        else
            cacheCoord.initialize()
    }

    onLoadAuthorInfoChanged: {
        authorFetch.resetState()

        if (!loadAuthorInfo) {
            authorsByThread = ({})
            authorFetch.clearAllState()
            avatarPreloader.reset()
            return
        }

        if (token && inboxMessages.length > 0)
            authorFetch.prefetchForMessages(inboxMessages)
    }

    onGroupItemLimitChanged: {
        if (token && cacheCoord.initialized)
            _fetchInbox()
    }

    onFetchPageCountChanged: {
        if (token && cacheCoord.initialized)
            _fetchInbox()
    }

    Component.onCompleted: {
        _perfStartMs = Date.now()
        _perfLog("Component.onCompleted — start")
        cacheCoord.handleClearCacheRequest(pluginData, pluginService)
        if (token)
            cacheCoord.initialize()
        _perfLog("Component.onCompleted — end (cache init requested)")
    }

    // =========================================================================
    //  BAR PILLS
    // =========================================================================

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            GitHubIcon {
                size: Math.max(Constants.barIconMinSizePx, root.iconSize - Constants.barIconSizeReductionPx)
                iconOpacity: Constants.githubIconBarOpacity
                sourcePrimary: root.githubIconPrimary
                sourceFallback: root.githubIconFallback
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.unreadCount > 0
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
                size: Math.max(Constants.barIconMinSizePx, root.iconSize - Constants.barIconSizeReductionPx)
                iconOpacity: Constants.githubIconBarOpacity
                sourcePrimary: root.githubIconPrimary
                sourceFallback: root.githubIconFallback
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.unreadCount > 0
                text: root.barCountText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // =========================================================================
    //  POPOUT
    // =========================================================================

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

                messages: root.messagesForView
                unreadCount: root.unreadCount
                tokenConfigured: root.token !== ""
                isLoading: fetcher.isLoading
                isOperating: operations.isOperating
                isDownloadingAvatars: cacheCoord.isDownloadingAvatars
                errorMessage: root.errorMessage
                headerOffset: popout.headerHeight + popout.detailsHeight
                titleLines: root.titleLines
                groupItemLimit: root.groupItemLimit
                expandedReposState: root.expandedReposState
                authorsByThread: root.authorsByThread
                showAuthorInfo: root.loadAuthorInfo

                onRefreshNow: root._refreshNow()
                onMarkAllRead: operations.markAllAsRead()
                onMarkRepoDone: function(repositoryFullName) {
                    operations.markRepoDone(repositoryFullName, root.inboxMessages)
                }
                onMarkThreadRead: function(threadId) { operations.markThreadAsRead(threadId) }
                onMarkThreadUnread: function(threadId) { operations.markThreadAsUnread(threadId) }
                onMarkThreadDone: function(threadId) { operations.markThreadDone(threadId) }
                onRequestThreadAuthors: function(threadId, subjectApiUrl, subjectType) {
                    if (!root.loadAuthorInfo) return
                    var notifUpdatedAt = ""
                    for (var ni = 0; ni < root.inboxMessages.length; ni++) {
                        if (root.inboxMessages[ni].threadId === threadId) {
                            notifUpdatedAt = root.inboxMessages[ni].updatedAt || ""
                            break
                        }
                    }
                    authorFetch.enqueueAuthorFetch(threadId, subjectApiUrl, subjectType, notifUpdatedAt)
                }
                onClosePopout: root.closePopout()
                onPersistExpandedRepos: function(state) {
                    root.expandedReposState = root._cloneExpandedState(state)
                }
            }
        }
    }

    popoutWidth: Math.round(Constants.popoutBaseWidthPx * Constants.popoutWidthScale)
    popoutHeight: {
        var groups = Math.max(Constants.minPopupHeightUnits, popupHeightUnits)
        var groupHeaderHeight = Constants.popoutGroupHeaderHeightPx
        var lineContribution = Math.max(1, titleLines) * Constants.popoutTitleLineHeightContributionPx
        var estimated = (groups * (groupHeaderHeight + lineContribution)) + Constants.popoutHeightBasePaddingPx
        return Math.max(Constants.popoutMinHeightPx, Math.min(Constants.popoutMaxHeightPx, estimated))
    }
}
