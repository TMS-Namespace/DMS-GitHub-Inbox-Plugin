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
    property int cacheTtlMinutes: {
        var value = parseInt(pluginData.cacheTtlMinutes || Constants.defaultCacheTtlMinutes)
        if (isNaN(value))
            return Constants.defaultCacheTtlMinutes
        return Math.max(Constants.minCacheTtlMinutes, Math.min(Constants.maxCacheTtlMinutes, value))
    }

    // =========================================================================
    //  RUNTIME STATE
    // =========================================================================

    property var inboxMessages: []
    property var messagesForView: []
    property var pendingViewMessages: []
    property int pendingViewIndex: 0
    property int unreadCount: 0
    property string errorMessage: ""
    property real lastUpdated: 0
    property var expandedReposState: ({ [Constants.expandedStateDefaultKey]: true })
    property var authorsByThread: ({})

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
        }
    }

    InboxFetcher {
        id: fetcher
        token: root.token
        fetchPageCount: root.fetchPageCount
        doneThreadState: operations.doneThreadState

        onFetchBegin: function(totalCount, unreadCount) {
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
                _tryFinalizeAuthorPrefetch()
            }
        }

        onFetchComplete: function(items, unreadCount) {
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
            _tryFinalizeAuthorPrefetch()
        }

        onFetchError: function(errorMessage) {
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

        onAuthorsMerged: function(mergedAuthors, preloadAuthors) {
            // Resolve avatar URLs from local cache before storing
            for (var resolveId in mergedAuthors)
                cacheCoord.resolveAuthorAvatars(mergedAuthors[resolveId])

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

    function _fetchInbox() {
        if (!token || operations.isOperating)
            return
        fetcher.fetch()
    }

    function _refreshNow() {
        if (!token) {
            errorMessage = "Set your GitHub token in Settings."
            return
        }
        _fetchInbox()
    }

    function _onCacheReady() {
        if (!token) return

        var cached = cacheCoord.loadCachedState()

        // Load messages for immediate display
        if (cached.messages.length > 0) {
            cacheCoord.resolveMessageAvatars(cached.messages)
            inboxMessages = cached.messages
            unreadCount = _recalculateUnread(cached.messages)
            _queueViewMessages(cached.messages)
            lastUpdated = cached.timestamp
        }

        // Load cached authors
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

        // Queue preload for all known avatars from cache
        avatarPreloader.queueFromMessages(cached.messages)
        var allAuthors = []
        for (var atid in resolvedAuthors) {
            var authorList = resolvedAuthors[atid] || []
            for (var ai = 0; ai < authorList.length; ai++)
                allAuthors.push(authorList[ai])
        }
        if (allAuthors.length > 0)
            avatarPreloader.queueFromAuthors(allAuthors)

        _fetchInbox()
    }

    function _tryFinalizeAuthorPrefetch() {
        if (!authorFetch.prefetchPending)
            return
        if (authorFetch.requestInFlight || authorFetch.requestQueue.length > 0)
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
        if (token)
            _fetchInbox()
    }

    onFetchPageCountChanged: {
        if (token)
            _fetchInbox()
    }

    Component.onCompleted: {
        cacheCoord.handleClearCacheRequest(pluginData, pluginService)
        if (token)
            cacheCoord.initialize()
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
