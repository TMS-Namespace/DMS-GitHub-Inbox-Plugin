// Widget.qml - Main GitHub Inbox widget orchestrator for DankMaterialShell
//
// This file is the top-level PluginComponent that wires together the
// extracted sub-components.  Business logic lives in the delegates:
//   - InboxBackgroundWorker  — curl-based inbox message fetching + WorkerScript
//   - AuthorBackgroundWorker — author data queue, dedup, fetching
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
import "."
import "../JS/GitHubHelpers.js" as GitHub

PluginComponent {
    id: root

    layerNamespacePlugin: GitHubConstants.pluginNamespaceId

    // =========================================================================
    //  SETTINGS-BACKED STATE
    // =========================================================================

    property string token: (secretStore.token || "").trim()
    property int pollIntervalMs: GitHub.pollIntervalMs(pluginData.pollInterval)
    property int groupItemLimit: {
        var value = parseInt(pluginData.groupItemLimit || GitHubConstants.defaultGroupItemLimit)
        if (isNaN(value))
            return GitHubConstants.defaultGroupItemLimit
        return Math.max(GitHubConstants.minGroupItemLimit, Math.min(GitHubConstants.maxGroupItemLimit, value))
    }
    property int fetchPageCount: {
        var value = parseInt(pluginData.fetchPages || GitHubConstants.defaultFetchPageCount)
        if (isNaN(value))
            return GitHubConstants.defaultFetchPageCount
        return Math.max(GitHubConstants.minFetchPageCount, Math.min(GitHubConstants.maxFetchPageCount, value))
    }
    property int popupHeightUnits: {
        var rawValue = pluginData.popupHeight
        if (rawValue === undefined || rawValue === "")
            rawValue = pluginData.popupItems || GitHubConstants.defaultPopupHeightUnits
        var value = parseInt(rawValue)
        if (isNaN(value))
            return GitHubConstants.defaultPopupHeightUnits
        return Math.max(GitHubConstants.minPopupHeightUnits, Math.min(GitHubConstants.maxPopupHeightUnits, value))
    }
    property int titleLines: {
        var value = parseInt(pluginData.titleLines || GitHubConstants.defaultTitleLines)
        if (isNaN(value))
            return GitHubConstants.defaultTitleLines
        return Math.max(GitHubConstants.minTitleLines, Math.min(GitHubConstants.maxTitleLines, value))
    }
    property bool loadAuthorInfo: GitHub.pluginDataBool(pluginData.loadAuthorInfo, true)
    property bool enableNotifications: GitHub.pluginDataBool(pluginData.enableNotifications, GitHubConstants.defaultEnableNotifications)
    property int cacheTtlMinutes: {
        var value = parseInt(pluginData.cacheTtlMinutes || GitHubConstants.defaultCacheTtlMinutes)
        if (isNaN(value))
            return GitHubConstants.defaultCacheTtlMinutes
        return Math.max(GitHubConstants.minCacheTtlMinutes, Math.min(GitHubConstants.maxCacheTtlMinutes, value))
    }

    // =========================================================================
    //  RUNTIME STATE
    // =========================================================================

    property real _perfStartMs: 0

    property var inboxMessages: []
    property var messagesForView: []
    property var pendingViewMessages: []
    property int pendingViewIndex: 0
    property var _pendingFetchedMessages: []
    property int _pendingFetchedUnreadCount: 0
    property int unreadCount: 0
    property string errorMessage: ""
    property real lastUpdated: 0
    property var expandedReposState: ({ [GitHubConstants.expandedStateDefaultKey]: true })
    property var authorsByThread: ({})
    property var _previousThreadIds: ({})
    property var _pendingLocalAvatarUpdates: ({})
    property var _pendingStartupAuthorMessages: []
    property var _pendingStartupAuthorAvatarLists: []
    property int _pendingStartupAuthorAvatarIndex: 0
    property bool _startupAuthorPrefetchQueued: false
    property var _pendingEnrichmentMessages: []
    property real _lastUiStallProbeAt: 0
    property bool isRefreshBusy: fetcher.isLoading || authorFetch.isBusy || cacheCoord.isDownloadingAvatars
    property bool popoutVisible: false
    property bool _refreshAfterPopoutClose: false

    property url githubIconPrimary: GitHubConstants.githubFaviconUrl
    property url githubIconFallback: Qt.resolvedUrl("../Images/github-mark.svg")

    // -- Computed properties --------------------------------------------------
    property int totalCount: inboxMessages.length
    property int readCount: Math.max(0, inboxMessages.length - unreadCount)
    property string barCountText: unreadCount > 0 ? GitHub.formatCountValue(unreadCount) : ""

    property string popoutDetails: {
        if (!token)
            return "Set your GitHub classic token in Settings"
        if (fetcher.isLoading && inboxMessages.length === 0)
            return "Loading messages..."
        if (errorMessage && inboxMessages.length === 0)
            return errorMessage

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
    }

    ResourceRepository {
        id: resourceRepo
        cacheCoordinator: cacheCoord

        onAvatarResourcesReady: function(updates) {
            for (var login in updates) {
                avatarPreloader.updateEntrySource(login, updates[login])
                root._queueLocalAvatarPropagation(login, updates[login])
            }
        }
    }

    SecretStore {
        id: secretStore
        pluginService: root.pluginService
        legacyPlainTextToken: root.pluginData.githubToken || ""
    }

    InboxBackgroundWorker {
        id: fetcher
        token: root.token
        fetchPageCount: root.fetchPageCount
        doneThreadState: operations.doneThreadState

        onFetchBegin: function(totalCount, unreadCount) {
            root._perfLog("onFetchBegin — total=" + totalCount + " unread=" + unreadCount)
            root._saveCurrentThreadIds()
            root._pendingFetchedMessages = []
            root._pendingFetchedUnreadCount = unreadCount
            root._pendingEnrichmentMessages = []
            backgroundEnrichmentTimer.stop()
            authorFetch.resetState()
            authorFetch.prefetchPending = false
            root.lastUpdated = Date.now()

        }

        onFetchChunk: function(chunk, isLast) {
            root._perfLog("onFetchChunk — size=" + chunk.length + " isLast=" + isLast)
            if (chunk.length > 0) {
                var nextMessages = root._pendingFetchedMessages.slice(0)
                for (var index = 0; index < chunk.length; index++)
                    nextMessages.push(chunk[index])
                root._pendingFetchedMessages = nextMessages
            }

            if (isLast) {
                root._applyFetchedMessages(root._pendingFetchedMessages, root._pendingFetchedUnreadCount)
                root._scheduleBackgroundEnrichment(root._pendingFetchedMessages)
                _finalizeFetchCycle()
            }
        }

        onFetchComplete: function(items, unreadCount) {
            root._perfLog("onFetchComplete — items=" + items.length + " unread=" + unreadCount)
            root._pendingFetchedMessages = items
            root._pendingFetchedUnreadCount = unreadCount
            root._applyFetchedMessages(items, unreadCount)
            authorFetch.prefetchPending = false
            root._scheduleBackgroundEnrichment(root.inboxMessages)
            _finalizeFetchCycle()
        }

        onFetchError: function(errorMessage) {
            root._perfLog("onFetchError — " + errorMessage)
            root._pendingFetchedMessages = []
            root._pendingFetchedUnreadCount = 0
            authorFetch.resetState()
            root.errorMessage = errorMessage
            root.lastUpdated = Date.now()
            Qt.callLater(operations.processPendingDoneQueue)
        }

        onAuthorResultReceived: function(message) {
            authorFetch.handleAuthorResult(message)
        }
    }

    AuthorBackgroundWorker {
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
                    resourceRepo.requestAuthorAvatars(mergedAuthors[cid])
            }

            var changedAuthorsForCache = {}
            for (var cacheIndex = 0; cacheIndex < changedThreadIds.length; cacheIndex++) {
                var cacheThreadId = changedThreadIds[cacheIndex]
                changedAuthorsForCache[cacheThreadId] = mergedAuthors[cacheThreadId] || []
            }

            root.authorsByThread = mergedAuthors
            cacheCoord.updateChangedAuthors(changedAuthorsForCache)

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
            if (result.items !== root.inboxMessages) {
                root.inboxMessages = result.items
                root._replaceViewMessages(root.inboxMessages)
            }
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
        interval: GitHubConstants.viewApplyTimerIntervalMs
        repeat: true
        onTriggered: root._applyViewChunk()
    }

    Timer {
        id: localAvatarApplyTimer
        interval: GitHubConstants.localAvatarPropagationDelayMs
        repeat: false
        onTriggered: root._applyLocalAvatarPropagations()
    }

    Timer {
        id: startupMissingInfoTimer
        interval: GitHubConstants.startupMissingInfoScanIntervalMs
        repeat: true
        onTriggered: root._processStartupMissingInfoBatch()
    }

    Timer {
        id: backgroundEnrichmentTimer
        interval: GitHubConstants.backgroundEnrichmentDelayMs
        repeat: false
        onTriggered: root._runBackgroundEnrichment()
    }

    Timer {
        id: uiStallProbeTimer
        interval: GitHubConstants.uiStallProbeIntervalMs
        running: GitHubConstants.profileLoggingEnabled
        repeat: true
        onTriggered: root._probeUiStall()
    }

    // =========================================================================
    //  ORCHESTRATION LOGIC
    // =========================================================================

    function _perfLog(label) {
        if (!GitHubConstants.debugPerformanceLogging) return
        var elapsed = (Date.now() - _perfStartMs).toFixed(0)
        console.warn("[GitHubInbox PERF] +" + elapsed + "ms  " + label)
    }

    function _profile(label, startMs, details) {
        if (!GitHubConstants.profileLoggingEnabled)
            return
        var duration = Date.now() - startMs
        if (!GitHubConstants.profileLogAllOperations
                && duration < GitHubConstants.profileSlowOperationThresholdMs)
            return
        var suffix = details ? (" — " + details) : ""
        console.warn("[GitHubInbox PROFILE] Widget." + label
                     + " took " + duration + "ms" + suffix)
    }

    function _probeUiStall() {
        if (!GitHubConstants.profileLoggingEnabled)
            return

        var now = Date.now()
        if (_lastUiStallProbeAt > 0) {
            var gap = now - _lastUiStallProbeAt
            if (gap >= GitHubConstants.uiStallLogThresholdMs) {
                console.warn("[GitHubInbox PROFILE] Widget.uiStallProbe gap="
                             + gap + "ms fetchLoading=" + fetcher.isLoading
                             + " authorBusy=" + authorFetch.isBusy
                             + " avatarBusy=" + cacheCoord.isDownloadingAvatars
                             + " viewApply=" + viewApplyTimer.running
                             + " authorQueue=" + authorFetch.requestQueue.length
                             + " authorInFlight=" + authorFetch.requestsInFlight)
            }
        }
        _lastUiStallProbeAt = now
    }

    function _fetchInbox() {
        _perfLog("_fetchInbox — called")
        if (!token || operations.isOperating || root.isRefreshBusy)
            return
        if (root.popoutVisible) {
            root._refreshAfterPopoutClose = true
            return
        }
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

    function _scheduleBackgroundEnrichment(items) {
        _pendingEnrichmentMessages = (items || []).slice(0)
        if (!token || _pendingEnrichmentMessages.length === 0)
            return
        backgroundEnrichmentTimer.restart()
    }

    function _runBackgroundEnrichment() {
        var profileStart = Date.now()
        if (!token || _pendingEnrichmentMessages.length === 0)
            return

        if (fetcher.isLoading || viewApplyTimer.running) {
            backgroundEnrichmentTimer.restart()
            return
        }

        var items = _pendingEnrichmentMessages
        _pendingEnrichmentMessages = []

        resourceRepo.requestMessageAvatars(items)
        avatarPreloader.queueFromMessages(items)
        if (loadAuthorInfo)
            authorFetch.prefetchForMessages(items)

        _profile("_runBackgroundEnrichment", profileStart, "items=" + items.length)
    }

    // -- Notification helpers -------------------------------------------------

    /// When an avatar is downloaded to disk, update all live data that still
    /// holds remote URLs for that login so the view switches to the local file.
    function _propagateLocalAvatar(login, localUrl) {
        if (!login || !localUrl)
            return
        var updates = {}
        updates[login] = localUrl
        _propagateLocalAvatarBatch(updates)
    }

    function _propagateLocalAvatarBatch(updates) {
        var profileStart = Date.now()
        if (!updates)
            return

        var messagesChanged = false
        for (var mi = 0; mi < inboxMessages.length; mi++) {
            var msg = inboxMessages[mi]
            var messageLogin = msg.repositoryOwnerLogin || ""
            var messageLocalUrl = updates[messageLogin]
            if (messageLocalUrl && msg.repositoryOwnerAvatarUrl !== messageLocalUrl) {
                msg.repositoryOwnerAvatarUrl = messageLocalUrl
                messagesChanged = true
            }
        }
        if (messagesChanged) {
            inboxMessages = inboxMessages.slice(0)
            messagesForView = messagesForView.slice(0)
        }

        var authorsChanged = false
        for (var tid in authorsByThread) {
            var authors = authorsByThread[tid]
            if (!authors)
                continue
            for (var ai = 0; ai < authors.length; ai++) {
                var authorLogin = authors[ai].login || ""
                var authorLocalUrl = updates[authorLogin]
                if (authorLocalUrl && authors[ai].avatarUrl !== authorLocalUrl) {
                    authors[ai].avatarUrl = authorLocalUrl
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
        _profile("_propagateLocalAvatarBatch", profileStart,
                 "updates=" + Object.keys(updates).length
                 + " messagesChanged=" + messagesChanged + " authorsChanged=" + authorsChanged)
    }

    function _queueLocalAvatarPropagation(login, localUrl) {
        if (!login || !localUrl)
            return

        var pending = {}
        for (var key in _pendingLocalAvatarUpdates)
            pending[key] = _pendingLocalAvatarUpdates[key]
        pending[login] = localUrl
        _pendingLocalAvatarUpdates = pending
        localAvatarApplyTimer.restart()
    }

    function _applyLocalAvatarPropagations() {
        var pending = _pendingLocalAvatarUpdates
        var batch = {}
        var remaining = {}
        var processed = 0

        for (var login in pending) {
            if (processed >= GitHubConstants.localAvatarPropagationBatchSize) {
                remaining[login] = pending[login]
                continue
            }
            batch[login] = pending[login]
            processed++
        }

        _propagateLocalAvatarBatch(batch)
        _pendingLocalAvatarUpdates = remaining
        if (Object.keys(remaining).length > 0)
            localAvatarApplyTimer.restart()
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
        var maxLines = GitHubConstants.notificationMaxLines

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
            "-a", GitHubConstants.notificationAppName,
            "-t", String(GitHubConstants.notificationExpireMs)]
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
                if (authors && typeof authors.length === "number")
                    resolvedAuthors[tid] = authors
            }
            authorsByThread = resolvedAuthors
        }

        // Load cached author fetch timestamps
        var cachedFetchedAt = cached.authorFetchedAt
        var nextFetchedAt = {}
        if (cachedFetchedAt && typeof cachedFetchedAt === "object") {
            for (var fid in cachedFetchedAt)
                nextFetchedAt[fid] = cachedFetchedAt[fid]
        }
        authorFetch.fetchedAtUpdatedAt = nextFetchedAt

        var fallbackAuthorUpdates = {}
        var cachedMessages = cached.messages || []
        for (var mi = 0; mi < cachedMessages.length; mi++) {
            var message = cachedMessages[mi]
            var threadId = message.threadId || ""
            if (!threadId)
                continue

            var knownAuthors = resolvedAuthors[threadId] || []
            if (knownAuthors.length > 0)
                continue
            if ((nextFetchedAt[threadId] || "") !== (message.updatedAt || ""))
                continue

            var fallbackAuthor = _fallbackAuthorForMessage(message)
            if (!fallbackAuthor)
                continue
            resolvedAuthors[threadId] = [fallbackAuthor]
            fallbackAuthorUpdates[threadId] = [fallbackAuthor]
        }
        authorsByThread = resolvedAuthors
        if (Object.keys(fallbackAuthorUpdates).length > 0)
            cacheCoord.updateChangedAuthors(fallbackAuthorUpdates)

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
            if (allPreloadAuthors.length >= GitHubConstants.avatarPreloadTotalCacheLimit)
                break
            var msg = messages[mi]
            allPreloadAuthors.push({
                login: msg.repositoryOwnerLogin || "",
                avatarUrl: msg.repositoryOwnerAvatarUrl || "",
                htmlUrl: msg.repositoryOwnerLogin
                    ? (GitHubConstants.githubWebBaseUrl + "/" + encodeURIComponent(msg.repositoryOwnerLogin))
                    : ""
            })
        }
        for (var atid in resolvedAuthors) {
            if (allPreloadAuthors.length >= GitHubConstants.avatarPreloadTotalCacheLimit)
                break
            var authorList = resolvedAuthors[atid] || []
            for (var ai = 0; ai < authorList.length; ai++) {
                if (allPreloadAuthors.length >= GitHubConstants.avatarPreloadTotalCacheLimit)
                    break
                allPreloadAuthors.push(authorList[ai])
            }
        }
        _perfLog("_onCacheReadyPhase3 — preload authors count=" + allPreloadAuthors.length)
        if (allPreloadAuthors.length > 0)
            avatarPreloader.queueFromAuthors(allPreloadAuthors)

        _scheduleStartupMissingInfoScan(messages, resolvedAuthors)

        _perfLog("_onCacheReadyPhase3 — end, scheduling _fetchInbox")
        // Finally, start the network fetch
        Qt.callLater(_fetchInbox)
    }

    function _scheduleStartupMissingInfoScan(messages, resolvedAuthors) {
        if (!token)
            return

        var cachedMessages = messages || []
        var cachedAuthors = resolvedAuthors || ({})
        var missingAuthorFetchThreadIds = {}
        var nextFetchedAt = {}

        for (var existingId in authorFetch.fetchedAtUpdatedAt)
            nextFetchedAt[existingId] = authorFetch.fetchedAtUpdatedAt[existingId]

        for (var mi = 0; mi < cachedMessages.length; mi++) {
            var message = cachedMessages[mi]
            var threadId = message.threadId || ""
            if (!threadId)
                continue

            var fetchedAt = nextFetchedAt[threadId] || ""
            if (fetchedAt !== (message.updatedAt || ""))
                missingAuthorFetchThreadIds[threadId] = true
        }

        authorFetch.fetchedAtUpdatedAt = nextFetchedAt

        var authorLists = []
        for (var authorThreadId in cachedAuthors) {
            var authorList = cachedAuthors[authorThreadId] || []
            if (authorList.length > 0)
                authorLists.push(authorList)
        }

        _pendingStartupAuthorMessages = cachedMessages.slice(0)
        _pendingStartupAuthorAvatarLists = authorLists
        _pendingStartupAuthorAvatarIndex = 0
        _startupAuthorPrefetchQueued = true

        _perfLog("_scheduleStartupMissingInfoScan — messages=" + cachedMessages.length
                 + " missingAuthorFetches=" + Object.keys(missingAuthorFetchThreadIds).length
                 + " authorAvatarLists=" + authorLists.length)

        if (cachedMessages.length > 0 || authorLists.length > 0)
            startupMissingInfoTimer.restart()
    }

    function _fallbackAuthorForMessage(message) {
        if (!message)
            return null

        var login = String(message.repositoryOwnerLogin || "").trim()
        if (!login)
            return null

        return {
            login: login,
            avatarUrl: String(message.repositoryOwnerAvatarUrl || "").trim()
                       || (GitHubConstants.githubAvatarsBaseUrl + "/" + encodeURIComponent(login)
                           + "?size=" + GitHubConstants.avatarDefaultSizePx),
            htmlUrl: GitHubConstants.githubWebBaseUrl + "/" + encodeURIComponent(login)
        }
    }

    function _processStartupMissingInfoBatch() {
        var profileStart = Date.now()
        if (!token) {
            startupMissingInfoTimer.stop()
            return
        }

        if (fetcher.isLoading || viewApplyTimer.running) {
            _profile("_processStartupMissingInfoBatch", profileStart, "deferredDuringStartup")
            return
        }

        var batchSize = Math.max(1, GitHubConstants.startupMissingInfoScanBatchSize)
        var processed = 0
        while (processed < batchSize
               && _pendingStartupAuthorAvatarIndex < _pendingStartupAuthorAvatarLists.length) {
            resourceRepo.requestAuthorAvatars(_pendingStartupAuthorAvatarLists[_pendingStartupAuthorAvatarIndex])
            _pendingStartupAuthorAvatarIndex++
            processed++
        }

        var authorRecoveryDone = _startupAuthorPrefetchQueued
                                 || _pendingStartupAuthorMessages.length === 0
                                 || !loadAuthorInfo
        if (_pendingStartupAuthorAvatarIndex >= _pendingStartupAuthorAvatarLists.length
                && authorRecoveryDone) {
            startupMissingInfoTimer.stop()
            _pendingStartupAuthorMessages = []
            _pendingStartupAuthorAvatarLists = []
            _pendingStartupAuthorAvatarIndex = 0
        }
        _profile("_processStartupMissingInfoBatch", profileStart,
                 "processedAvatars=" + processed
                 + " remainingAvatarLists=" + Math.max(0, _pendingStartupAuthorAvatarLists.length - _pendingStartupAuthorAvatarIndex)
                 + " authorRecoveryQueued=" + _startupAuthorPrefetchQueued)
    }

    function _tryFinalizeAuthorPrefetch() {
        if (!authorFetch.prefetchPending)
            return
        if (authorFetch.requestsInFlight > 0 || authorFetch.requestQueue.length > 0)
            return
        if (authorFetch.hasPendingPrefetchWork())
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
        _pruneAuthorCaches()
        ApiCallStats.recordRefreshComplete()
        fetcher.retryIfQueued()
    }

    function _applyFetchedMessages(items, unread) {
        var nextItems = items || []
        inboxMessages = nextItems
        unreadCount = Math.max(0, unread || 0)
        _queueViewMessages(nextItems)
        errorMessage = ""
        lastUpdated = Date.now()
        cacheCoord.updateMessages(nextItems)
        _detectAndNotifyNewMessages(nextItems)
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
        var profileStart = Date.now()
        pendingViewMessages = (items || []).slice(0)
        pendingViewIndex = 0
        messagesForView = []
        if (pendingViewMessages.length > 0)
            viewApplyTimer.restart()
        else
            viewApplyTimer.stop()
        _profile("_queueViewMessages", profileStart, "items=" + pendingViewMessages.length)
    }

    function _replaceViewMessages(items) {
        var profileStart = Date.now()
        pendingViewMessages = []
        pendingViewIndex = 0
        viewApplyTimer.stop()
        messagesForView = (items || []).slice(0)
        _profile("_replaceViewMessages", profileStart, "items=" + messagesForView.length)
    }

    function _appendViewMessages(items) {
        var profileStart = Date.now()
        if (!items || items.length === 0)
            return

        var nextPending = pendingViewMessages.slice(0)
        for (var index = 0; index < items.length; index++)
            nextPending.push(items[index])
        pendingViewMessages = nextPending

        if (!viewApplyTimer.running)
            viewApplyTimer.restart()
        _profile("_appendViewMessages", profileStart, "items=" + items.length + " pending=" + pendingViewMessages.length)
    }

    function _applyViewChunk() {
        var profileStart = Date.now()
        if (pendingViewMessages.length === 0) {
            viewApplyTimer.stop()
            return
        }

        var limit = Math.max(1, GitHubConstants.viewApplyChunkSize)
        var count = Math.min(limit, pendingViewMessages.length)
        var nextView = messagesForView.slice(0)

        for (var index = 0; index < count; index++)
            nextView.push(pendingViewMessages[index])

        messagesForView = nextView
        pendingViewIndex += count
        pendingViewMessages = pendingViewMessages.slice(count)

        if (pendingViewMessages.length === 0)
            viewApplyTimer.stop()
        _profile("_applyViewChunk", profileStart,
                 "count=" + count + " visible=" + messagesForView.length
                 + " remaining=" + pendingViewMessages.length)
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
        if (copy[GitHubConstants.expandedStateDefaultKey] === undefined)
            copy[GitHubConstants.expandedStateDefaultKey] = true
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
            _pendingFetchedMessages = []
            _pendingFetchedUnreadCount = 0
            pendingViewMessages = []
            pendingViewIndex = 0
            viewApplyTimer.stop()
            startupMissingInfoTimer.stop()
            backgroundEnrichmentTimer.stop()
            _pendingEnrichmentMessages = []
            unreadCount = 0
            errorMessage = ""
            lastUpdated = 0
            fetcher.cancel()
            authorFetch.clearAllState()
            operations.resetState()
            avatarPreloader.reset()
            authorsByThread = ({})
            expandedReposState = ({ [GitHubConstants.expandedStateDefaultKey]: true })
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
            backgroundEnrichmentTimer.stop()
            return
        }

        if (token && inboxMessages.length > 0)
            _scheduleBackgroundEnrichment(inboxMessages)
    }

    onGroupItemLimitChanged: {
        if (token && cacheCoord.initialized)
            _fetchInbox()
    }

    onFetchPageCountChanged: {
        if (token && cacheCoord.initialized)
            _fetchInbox()
    }

    onPopoutVisibleChanged: {
        if (popoutVisible || !_refreshAfterPopoutClose)
            return
        _refreshAfterPopoutClose = false
        Qt.callLater(_fetchInbox)
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
                size: Math.max(GitHubConstants.barIconMinSizePx, root.iconSize - GitHubConstants.barIconSizeReductionPx)
                iconOpacity: GitHubConstants.githubIconBarOpacity
                iconColor: Theme.surfaceText
                followThemeColor: true
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
                size: Math.max(GitHubConstants.barIconMinSizePx, root.iconSize - GitHubConstants.barIconSizeReductionPx)
                iconOpacity: GitHubConstants.githubIconBarOpacity
                iconColor: Theme.surfaceText
                followThemeColor: true
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

            Component.onCompleted: root.popoutVisible = true
            Component.onDestruction: root.popoutVisible = false

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
                isAuthorFetching: authorFetch.isBusy
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
                    var resolvedSubjectApiUrl = subjectApiUrl || ""
                    var resolvedSubjectType = subjectType || ""
                    for (var ni = 0; ni < root.inboxMessages.length; ni++) {
                        if (root.inboxMessages[ni].threadId === threadId) {
                            notifUpdatedAt = root.inboxMessages[ni].updatedAt || ""
                            if (!resolvedSubjectApiUrl)
                                resolvedSubjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(root.inboxMessages[ni])
                            if (!resolvedSubjectType)
                                resolvedSubjectType = root.inboxMessages[ni].subjectType || ""
                            break
                        }
                    }
                    authorFetch.enqueueAuthorFetch(threadId, resolvedSubjectApiUrl, resolvedSubjectType, notifUpdatedAt, true)
                }
                onClosePopout: root.closePopout()
                onPersistExpandedRepos: function(state) {
                    root.expandedReposState = root._cloneExpandedState(state)
                }
            }
        }
    }

    popoutWidth: Math.round(GitHubConstants.popoutBaseWidthPx * GitHubConstants.popoutWidthScale)
    popoutHeight: {
        var groups = Math.max(GitHubConstants.minPopupHeightUnits, popupHeightUnits)
        var groupHeaderHeight = GitHubConstants.popoutGroupHeaderHeightPx
        var lineContribution = Math.max(1, titleLines) * GitHubConstants.popoutTitleLineHeightContributionPx
        var estimated = (groups * (groupHeaderHeight + lineContribution)) + GitHubConstants.popoutHeightBasePaddingPx
        return Math.max(GitHubConstants.popoutMinHeightPx, Math.min(GitHubConstants.popoutMaxHeightPx, estimated))
    }
}
