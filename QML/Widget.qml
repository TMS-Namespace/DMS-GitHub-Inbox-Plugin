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
    property string groupingMode: _normalizeGroupingMode(pluginData.groupingMode || "repo")
    property string clearCacheRequestFlag: pluginData.clearCacheRequested || ""

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
    property var expandedDateGroupsState: ({ [GitHubConstants.expandedStateDefaultKey]: true })
    property var authorsByThread: ({})
    property real _latestLocalMessageUpdatedAtMs: 0
    property var _pendingLocalAvatarUpdates: ({})
    property int _pendingLocalAvatarUpdateCount: 0
    property var _pendingNotificationMessages: []
    property bool _apiStatsCompletionPending: false
    property var _pendingStartupAuthorMessages: []
    property var _pendingStartupAuthorAvatarLists: []
    property int _pendingStartupAuthorAvatarIndex: 0
    property bool _startupAuthorPrefetchQueued: false
    property var _pendingEnrichmentMessages: []
    property real _lastUiStallProbeAt: 0
    property real _refreshBusySinceMs: 0
    property real _operationBusySinceMs: 0
    property bool _activeFetchWasManual: false
    property string _lastErrorNotificationText: ""
    property real _lastErrorNotificationAt: 0
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
        if (secretStore.secretStorageUnavailable)
            return secretStore.statusMessage || "Secret Service is unavailable."
        if (!token)
            return "Set your GitHub classic token in Settings"
        if (fetcher.isLoading && inboxMessages.length === 0)
            return "Loading messages..."
        if (errorMessage && inboxMessages.length === 0)
            return errorMessage

        var counts = unreadCount + " unread / " + readCount + " read / " + totalCount + " total"
        return counts
    }

    function _normalizeGroupingMode(value) {
        return String(value || "") === "date" ? "date" : "repo"
    }

    function setGroupingMode(value) {
        var nextMode = _normalizeGroupingMode(value)
        if (groupingMode === nextMode)
            return

        groupingMode = nextMode
        if (pluginService)
            pluginService.savePluginData(GitHubConstants.pluginNamespaceId, "groupingMode", nextMode)
    }

    // =========================================================================
    //  SUB-COMPONENTS
    // =========================================================================

    CacheCoordinator {
        id: cacheCoord
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
        fatalOnUnavailable: true

        onActivationRefused: function(message) {
            throw new Error(message)
        }
    }

    InboxBackgroundWorker {
        id: fetcher
        token: root.token
        fetchPageCount: root.fetchPageCount
        doneThreadState: operations.effectiveDoneThreadState

        onFetchBegin: function(totalCount, unreadCount) {
            root._perfLog("onFetchBegin — total=" + totalCount + " unread=" + unreadCount)
            root._saveLatestLocalMessageUpdatedAt()
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
                for (var index = 0; index < chunk.length; index++)
                    root._pendingFetchedMessages.push(chunk[index])
            }

            if (isLast) {
                var changed = root._applyFetchedMessages(root._pendingFetchedMessages,
                                                         root._pendingFetchedUnreadCount)
                root._scheduleBackgroundEnrichment(root.inboxMessages)
                _finalizeFetchCycle(changed)
            }
        }

        onFetchComplete: function(items, unreadCount) {
            root._perfLog("onFetchComplete — items=" + items.length + " unread=" + unreadCount)
            root._pendingFetchedMessages = items
            root._pendingFetchedUnreadCount = unreadCount
            var changed = root._applyFetchedMessages(items, unreadCount)
            authorFetch.prefetchPending = false
            root._scheduleBackgroundEnrichment(root.inboxMessages)
            _finalizeFetchCycle(changed)
        }

        onFetchError: function(errorMessage) {
            root._perfLog("onFetchError — " + errorMessage)
            root._pendingFetchedMessages = []
            root._pendingFetchedUnreadCount = 0
            root._pendingNotificationMessages = []
            authorFetch.resetState()
            root.errorMessage = errorMessage
            root.lastUpdated = Date.now()
            root._notifyBackgroundFetchError(errorMessage)
            root._activeFetchWasManual = false
            root._scheduleApiStatsRefreshComplete()
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

        onSubjectWebUrlResolved: function(threadId, webUrl, subjectReference) {
            root._updateMessageSubjectDetails(threadId, webUrl, subjectReference)
        }

        onPrefetchMaybeComplete: root._tryFinalizeAuthorPrefetch()
    }

    InboxOperations {
        id: operations
        token: root.token
        isLoading: fetcher.isLoading

        onIsBusyChanged: {
            root._operationBusySinceMs = isBusy ? Date.now() : 0
        }

        onOperationApplied: function(actionType, threadId, repositoryFullName, threadIds) {
            var result = operations.applyResult(actionType, threadId, repositoryFullName,
                                                root.inboxMessages, threadIds || [])
            var itemsChanged = result.items !== root.inboxMessages
            if (itemsChanged) {
                root.inboxMessages = result.items
                root._replaceViewMessages(root.inboxMessages)
                if (_operationShouldUpdateMessageCache(actionType))
                    cacheCoord.updateMessages(root.inboxMessages)
            }
            if (itemsChanged || result.unreadChanged)
                root.unreadCount = _recalculateUnread(root.inboxMessages)
            root.errorMessage = ""
            root.lastUpdated = Date.now()
        }

        onDoneThreadStateChanged: {
            if (cacheCoord.initialized)
                cacheCoord.updateDoneThreadState(doneThreadState)
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
        interval: GitHubConstants.profileLoggingEnabled ? GitHubConstants.uiStallProbeIntervalMs : 5000
        running: root.token !== ""
        repeat: true
        onTriggered: root._probeUiStall()
    }

    Timer {
        id: apiStatsCompletionTimer
        interval: 250
        repeat: false
        onTriggered: root._tryRecordApiStatsRefreshComplete()
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

    function _busyDurationMs(isBusy, sinceMs) {
        if (!isBusy)
            return 0
        if (sinceMs > 0)
            return Math.max(0, Date.now() - sinceMs)
        return GitHubConstants.refreshBusyStaleMs + 1
    }

    function _refreshBusyDetails() {
        return "fetchLoading=" + fetcher.isLoading
               + " authorBusy=" + authorFetch.isBusy
               + " avatarBusy=" + cacheCoord.isDownloadingAvatars
               + " operationsBusy=" + operations.isBusy
               + " authorQueue=" + authorFetch.requestQueue.length
               + " authorInFlight=" + authorFetch.requestsInFlight
    }

    function _recoverStaleBackgroundWork(reason, force) {
        if (!root.isRefreshBusy && !operations.isBusy)
            return false

        var refreshBusyMs = _busyDurationMs(root.isRefreshBusy, _refreshBusySinceMs)
        var operationBusyMs = _busyDurationMs(operations.isBusy, _operationBusySinceMs)
        var stale = !!force
                    || refreshBusyMs >= GitHubConstants.refreshBusyStaleMs
                    || operationBusyMs >= GitHubConstants.refreshBusyStaleMs
        if (!stale)
            return false

        console.warn("[GitHubInbox] Recovering stale background work after "
                     + reason + " refreshBusyMs=" + refreshBusyMs
                     + " operationBusyMs=" + operationBusyMs
                     + " " + _refreshBusyDetails())

        fetcher.cancel()
        authorFetch.resetState()
        cacheCoord.resetAvatarDownloads()
        operations.resetState(false)
        backgroundEnrichmentTimer.stop()
        startupMissingInfoTimer.stop()
        _pendingEnrichmentMessages = []
        _pendingStartupAuthorMessages = []
        _pendingStartupAuthorAvatarLists = []
        _pendingStartupAuthorAvatarIndex = 0
        _startupAuthorPrefetchQueued = false
        _apiStatsCompletionPending = false
        apiStatsCompletionTimer.stop()
        _refreshBusySinceMs = 0
        _operationBusySinceMs = 0
        return true
    }

    function _probeUiStall() {
        var now = Date.now()
        if (_lastUiStallProbeAt > 0) {
            var gap = now - _lastUiStallProbeAt
            if (gap >= GitHubConstants.uiStallLogThresholdMs) {
                if (GitHubConstants.profileLoggingEnabled) {
                    console.warn("[GitHubInbox PROFILE] Widget.uiStallProbe gap="
                                 + gap + "ms fetchLoading=" + fetcher.isLoading
                                 + " authorBusy=" + authorFetch.isBusy
                                 + " avatarBusy=" + cacheCoord.isDownloadingAvatars
                                 + " viewApply=" + viewApplyTimer.running
                                 + " authorQueue=" + authorFetch.requestQueue.length
                                 + " authorInFlight=" + authorFetch.requestsInFlight)
                }
                if (gap >= GitHubConstants.wakeRefreshRecoveryGapMs)
                    _recoverStaleBackgroundWork("wake/stall gap " + gap + "ms", true)
            }
        }
        _lastUiStallProbeAt = now
    }

    function _fetchInbox(allowWhilePopout) {
        _perfLog("_fetchInbox — called")
        _recoverStaleBackgroundWork("refresh guard", false)
        if (!token)
            return
        if (operations.isBusy || root.isRefreshBusy) {
            if (GitHubConstants.profileLoggingEnabled)
                console.warn("[GitHubInbox] Refresh skipped because work is still busy: "
                             + _refreshBusyDetails())
            return
        }
        if (root.popoutVisible && !allowWhilePopout) {
            root._refreshAfterPopoutClose = true
            if (GitHubConstants.profileLoggingEnabled)
                console.warn("[GitHubInbox] Refresh deferred until popup closes")
            return
        }
        _activeFetchWasManual = !!allowWhilePopout
        fetcher.fetch()
        _perfLog("_fetchInbox — fetch() dispatched")
    }

    function _refreshNow() {
        if (!token) {
            errorMessage = "Set your GitHub token in Settings."
            return
        }
        _recoverStaleBackgroundWork("manual refresh", false)
        _fetchInbox(true)
    }

    function _scheduleBackgroundEnrichment(items) {
        _pendingEnrichmentMessages = _filterMessagesNeedingEnrichment(items || [])
        if (!token || _pendingEnrichmentMessages.length === 0)
            return
        backgroundEnrichmentTimer.restart()
    }

    function _filterMessagesNeedingEnrichment(items) {
        var result = []
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            if (!item || !item.threadId)
                continue

            var needsAvatar = !!item.repositoryOwnerLogin
                              && String(item.repositoryOwnerAvatarUrl || "").indexOf("file://") !== 0
            var knownAuthors = authorsByThread[item.threadId] || []
            var needsMissingAuthors = loadAuthorInfo && knownAuthors.length === 0
            var needsAuthor = loadAuthorInfo
                              && (needsMissingAuthors
                                  || (authorFetch.fetchedAtUpdatedAt[item.threadId] || "") !== (item.updatedAt || "")
                                  || authorFetch.requiresSubjectWebUrlResolution(item)
                                  || authorFetch.requiresSubjectReferenceResolution(item)
                                  || !authorFetch.hasFetchedAuthorDetailsForMessage(item))
            if (needsAvatar || needsAuthor)
                result.push(item)
        }
        return result
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

        var updateCount = 0
        for (var updateLogin in updates)
            updateCount++

        var messagesChanged = false
        for (var mi = 0; mi < inboxMessages.length; mi++) {
            var msg = inboxMessages[mi]
            var messageLogin = msg.repositoryOwnerLogin || ""
            var messageLocalUrl = updates[messageLogin]
            if (messageLocalUrl && msg.repositoryOwnerAvatarUrl !== messageLocalUrl) {
                msg.repositoryOwnerAvatarUrl = messageLocalUrl
                messagesChanged = true
            } else if (messageLocalUrl
                       && msg.repositoryOwnerAvatarUrl === messageLocalUrl
                       && String(messageLocalUrl).indexOf("file://") === 0) {
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
                } else if (authorLocalUrl
                           && authors[ai].avatarUrl === authorLocalUrl
                           && String(authorLocalUrl).indexOf("file://") === 0) {
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
                 "updates=" + updateCount
                 + " messagesChanged=" + messagesChanged + " authorsChanged=" + authorsChanged)
    }

    function _queueLocalAvatarPropagation(login, localUrl) {
        if (!login || !localUrl)
            return

        if (!_pendingLocalAvatarUpdates.hasOwnProperty(login))
            _pendingLocalAvatarUpdateCount++
        _pendingLocalAvatarUpdates[login] = localUrl
        localAvatarApplyTimer.restart()
    }

    function _applyLocalAvatarPropagations() {
        var pending = _pendingLocalAvatarUpdates
        _pendingLocalAvatarUpdates = ({})
        _pendingLocalAvatarUpdateCount = 0

        var batch = {}
        var remaining = {}
        var processed = 0
        var remainingCount = 0

        for (var login in pending) {
            if (processed >= GitHubConstants.localAvatarPropagationBatchSize) {
                remaining[login] = pending[login]
                remainingCount++
                continue
            }
            batch[login] = pending[login]
            processed++
        }

        _propagateLocalAvatarBatch(batch)

        var merged = {}
        for (var remainingLogin in remaining)
            merged[remainingLogin] = remaining[remainingLogin]
        var mergedCount = remainingCount
        for (var queuedLogin in _pendingLocalAvatarUpdates) {
            if (!merged.hasOwnProperty(queuedLogin))
                mergedCount++
            merged[queuedLogin] = _pendingLocalAvatarUpdates[queuedLogin]
        }

        _pendingLocalAvatarUpdates = merged
        _pendingLocalAvatarUpdateCount = mergedCount
        if (mergedCount > 0)
            localAvatarApplyTimer.restart()
    }

    function _saveLatestLocalMessageUpdatedAt() {
        _latestLocalMessageUpdatedAtMs = _latestMessageUpdatedAtMs(inboxMessages)
    }

    function _detectAndNotifyNewMessages(items) {
        if (!enableNotifications)
            return []

        var latestLocalMessageUpdatedAtMs = _latestLocalMessageUpdatedAtMs || 0
        if (latestLocalMessageUpdatedAtMs <= 0)
            return []

        var newMessages = []
        var candidateItems = _filterDoneMessages(items || [])
        for (var i = 0; i < candidateItems.length; i++) {
            var item = candidateItems[i]
            if (!item || !item.threadId || !item.unread)
                continue
            var updatedAtMs = item.updatedAtMs || Date.parse(item.updatedAt || "") || 0
            if (updatedAtMs > latestLocalMessageUpdatedAtMs)
                newMessages.push(item)
        }

        if (newMessages.length === 0)
            return []

        return newMessages
    }

    function _queueDesktopNotifications(newMessages) {
        if (!newMessages || newMessages.length === 0)
            return

        _pendingNotificationMessages = newMessages
    }

    function _flushPendingDesktopNotificationsIfReady() {
        if (_pendingNotificationMessages.length === 0)
            return
        if (popoutVisible && (viewApplyTimer.running || pendingViewMessages.length > 0))
            return

        var messagesToNotify = _pendingNotificationMessages
        _pendingNotificationMessages = []
        _sendDesktopNotification(messagesToNotify)
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

    function _notifyBackgroundFetchError(message) {
        if (_activeFetchWasManual)
            return

        var text = String(message || "GitHub refresh failed.").trim()
        if (!text)
            return

        var now = Date.now()
        if (text === _lastErrorNotificationText
                && now - _lastErrorNotificationAt < GitHubConstants.errorNotificationRepeatMs)
            return

        _lastErrorNotificationText = text
        _lastErrorNotificationAt = now

        var proc = notifyProcessDef.createObject(root)
        proc.command = [
            "notify-send",
            "-a", GitHubConstants.notificationAppName,
            "-u", "normal",
            "-t", String(GitHubConstants.notificationExpireMs),
            "GitHub Inbox refresh failed",
            text
        ]
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
        operations.setDoneThreadState(cached.doneThreadState || ({}))
        var cachedMessages = _filterDoneMessages(cached.messages || [])

        // Phase 1: Load messages for immediate bar-pill display
        if (cachedMessages.length > 0) {
            inboxMessages = cachedMessages
            unreadCount = _recalculateUnread(cachedMessages)
            _queueViewMessages(cachedMessages)
            lastUpdated = cached.timestamp
        }

        // Defer heavier work (author resolution, preloader) to separate frames
        _pendingCacheState = {
            messages: cachedMessages,
            authorsByThread: cached.authorsByThread || ({}),
            authorFetchedAt: cached.authorFetchedAt || ({}),
            timestamp: cached.timestamp || 0
        }
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
        _sanitizeCachedAuthors(cached.messages || [], resolvedAuthors, nextFetchedAt)
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
        _startupAuthorPrefetchQueued = false

        _perfLog("_scheduleStartupMissingInfoScan — messages=" + cachedMessages.length
                 + " missingAuthorFetches=" + Object.keys(missingAuthorFetchThreadIds).length
                 + " authorAvatarLists=" + authorLists.length)

        if (cachedMessages.length > 0 || authorLists.length > 0)
            startupMissingInfoTimer.restart()
    }

    function _fallbackAuthorForMessage(message) {
        return null
    }

    function _sanitizeCachedAuthors(messages, resolvedAuthors, fetchedAt) {
        var messagesByThread = {}
        for (var index = 0; index < messages.length; index++) {
            var message = messages[index]
            if (message && message.threadId)
                messagesByThread[message.threadId] = message
        }

        var changedAuthorsForCache = {}
        for (var threadId in resolvedAuthors) {
            var sourceMessage = messagesByThread[threadId]
            if (!sourceMessage)
                continue

            var repositoryOwner = String(sourceMessage.repositoryOwnerLogin || "").trim().toLowerCase()
            if (!repositoryOwner)
                continue

            var authors = resolvedAuthors[threadId] || []
            var normalizedAuthors = _normalizeCachedAuthorsForMessage(sourceMessage, authors)
            var changed = normalizedAuthors.length !== authors.length
            if (authors.length === 0
                    && (fetchedAt[threadId] || "") === (sourceMessage.updatedAt || ""))
                changed = true
            for (var authorIndex = 0; authorIndex < authors.length; authorIndex++) {
                var authorLogin = String((authors[authorIndex] && authors[authorIndex].login) || "").trim().toLowerCase()
                if (authorLogin === repositoryOwner) {
                    changed = true
                    break
                }
            }

            if (!changed)
                continue

            resolvedAuthors[threadId] = normalizedAuthors
            fetchedAt[threadId] = ""
            changedAuthorsForCache[threadId] = resolvedAuthors[threadId]
            cacheCoord.updateAuthorFetchedAt(threadId, "")
        }

        if (Object.keys(changedAuthorsForCache).length > 0)
            cacheCoord.updateChangedAuthors(changedAuthorsForCache)
    }

    function _isCiSubjectType(subjectType) {
        var normalizedType = String(subjectType || "").toLowerCase()
        return normalizedType === "checksuite"
               || normalizedType === "checkrun"
               || normalizedType === "workflowrun"
    }

    function _normalizeCachedAuthorsForMessage(message, authors) {
        var repositoryOwner = String(message.repositoryOwnerLogin || "").trim().toLowerCase()
        var normalizedType = String(message.subjectType || "").toLowerCase()
        var normalizedReason = String(message.reason || "").toLowerCase()
        var filtered = []

        for (var index = 0; index < authors.length; index++) {
            var author = authors[index]
            var authorLogin = String((author && author.login) || "").trim().toLowerCase()
            if (authorLogin && authorLogin === repositoryOwner)
                continue
            if ((normalizedType === "pullrequest" || normalizedType === "issue")
                    && _isGitHubActionsAuthor(author))
                continue
            filtered.push(author)
        }

        if (_isCiSubjectType(message.subjectType) && filtered.length > 1)
            return filtered.slice(0, 1)

        if ((normalizedType === "pullrequest" || normalizedType === "issue")
                && normalizedReason === "comment"
                && filtered.length > 1)
            return filtered.slice(0, 1)

        if (normalizedType === "pullrequest"
                && normalizedReason === "author"
                && filtered.length > GitHubConstants.maxAuthorsDisplayedPerMessage)
            return filtered.slice(0, GitHubConstants.maxAuthorsDisplayedPerMessage)

        return filtered
    }

    function _isGitHubActionsAuthor(author) {
        var login = String((author && author.login) || "").trim().toLowerCase()
        var htmlUrl = String((author && (author.htmlUrl || author.html_url)) || "").trim().toLowerCase()
        return login === "github-actions"
               || login === "github-actions[bot]"
               || htmlUrl === GitHubConstants.githubWebBaseUrl + "/apps/github-actions"
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

        if (!_startupAuthorPrefetchQueued
                && loadAuthorInfo
                && _pendingStartupAuthorMessages.length > 0) {
            authorFetch.prefetchMissingForMessages(_pendingStartupAuthorMessages, authorsByThread)
            _startupAuthorPrefetchQueued = true
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
        authorFetch.prefetchPending = false
        _scheduleApiStatsRefreshComplete()

        Qt.callLater(operations.processPendingDoneQueue)
        fetcher.retryIfQueued()
    }

    function _finalizeFetchCycle(messagesChanged) {
        if (messagesChanged)
            _pruneAuthorCaches()
        _activeFetchWasManual = false
        _scheduleApiStatsRefreshComplete()
        fetcher.retryIfQueued()
    }

    function _applyFetchedMessages(items, unread) {
        var nextItems = _mergeCachedMessageFields(items || [])
        nextItems = _filterDoneMessages(nextItems)
        var nextUnread = _recalculateUnread(nextItems)
        var unchanged = nextUnread === unreadCount
                        && _messagesEquivalent(inboxMessages, nextItems)
        if (unchanged) {
            errorMessage = ""
            lastUpdated = Date.now()
            _perfLog("_applyFetchedMessages — unchanged, skipped UI/cache/enrichment")
            return false
        }

        inboxMessages = nextItems
        unreadCount = nextUnread
        _queueViewMessages(nextItems)
        errorMessage = ""
        lastUpdated = Date.now()
        var newMessages = _detectAndNotifyNewMessages(nextItems)
        cacheCoord.updateMessages(nextItems)
        _latestLocalMessageUpdatedAtMs = _latestMessageUpdatedAtMs(nextItems)
        _queueDesktopNotifications(newMessages)
        return true
    }

    function _scheduleApiStatsRefreshComplete() {
        _apiStatsCompletionPending = true
        apiStatsCompletionTimer.restart()
    }

    function _tryRecordApiStatsRefreshComplete() {
        if (!_apiStatsCompletionPending)
            return

        if (fetcher.isLoading
                || authorFetch.isBusy
                || cacheCoord.isDownloadingAvatars
                || backgroundEnrichmentTimer.running
                || viewApplyTimer.running) {
            apiStatsCompletionTimer.restart()
            return
        }

        _apiStatsCompletionPending = false
        if (GitHubConstants.apiCallStatsEnabled)
            ApiCallStats.recordRefreshComplete()
        _flushPendingDesktopNotificationsIfReady()
    }

    function _mergeCachedMessageFields(items) {
        var existingByThread = {}
        var localAvatarsByLogin = _collectKnownLocalAvatarsByLogin()
        for (var existingIndex = 0; existingIndex < inboxMessages.length; existingIndex++) {
            var existing = inboxMessages[existingIndex]
            if (existing && existing.threadId) {
                existingByThread[existing.threadId] = existing
                _rememberKnownLocalAvatar(localAvatarsByLogin,
                                          existing.repositoryOwnerLogin,
                                          existing.repositoryOwnerAvatarUrl)
            }
        }

        var merged = []
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            if (!item || !item.threadId) {
                merged.push(item)
                continue
            }

            var cached = existingByThread[item.threadId]
            if (!cached || (cached.updatedAt || "") !== (item.updatedAt || "")) {
                merged.push(_applyKnownLocalRepoAvatar(item, localAvatarsByLogin))
                continue
            }

            var copy = item
            if (cached.webUrlResolved && cached.webUrl && cached.webUrl !== item.webUrl) {
                copy = _cloneMessageForMerge(copy)
                copy.webUrl = cached.webUrl
                copy.webUrlResolved = true
            } else if (cached.webUrlResolved && !item.webUrlResolved) {
                copy = _cloneMessageForMerge(copy)
                copy.webUrlResolved = true
            }

            var cachedSubjectReference = String(cached.subjectReference || "")
            if (cachedSubjectReference && cachedSubjectReference !== (item.subjectReference || "")) {
                copy = _cloneMessageForMerge(copy)
                copy.subjectReference = cachedSubjectReference
            }

            var cachedRepoAvatar = String(cached.repositoryOwnerAvatarUrl || "")
            if (cachedRepoAvatar.indexOf("file://") === 0
                    && cachedRepoAvatar !== item.repositoryOwnerAvatarUrl) {
                copy = _cloneMessageForMerge(copy)
                copy.repositoryOwnerAvatarUrl = cachedRepoAvatar
            }

            copy = _applyKnownLocalRepoAvatar(copy, localAvatarsByLogin)
            merged.push(copy)
        }
        return merged
    }

    function _collectKnownLocalAvatarsByLogin() {
        var localAvatarsByLogin = {}

        for (var tid in authorsByThread) {
            var authors = authorsByThread[tid] || []
            for (var ai = 0; ai < authors.length; ai++) {
                _rememberKnownLocalAvatar(localAvatarsByLogin,
                                          authors[ai].login,
                                          authors[ai].avatarUrl)
            }
        }

        return localAvatarsByLogin
    }

    function _rememberKnownLocalAvatar(localAvatarsByLogin, login, avatarUrl) {
        var normalizedLogin = String(login || "").trim()
        var normalizedAvatarUrl = String(avatarUrl || "").trim()
        if (!normalizedLogin || normalizedAvatarUrl.indexOf("file://") !== 0)
            return
        if (!localAvatarsByLogin.hasOwnProperty(normalizedLogin))
            localAvatarsByLogin[normalizedLogin] = normalizedAvatarUrl
    }

    function _applyKnownLocalRepoAvatar(item, localAvatarsByLogin) {
        if (!item)
            return item

        var login = String(item.repositoryOwnerLogin || "").trim()
        var localAvatarUrl = login ? (localAvatarsByLogin[login] || "") : ""
        if (!localAvatarUrl && login && cacheCoord.initialized) {
            localAvatarUrl = cacheCoord.cachedLocalAvatarUrl(login)
            if (localAvatarUrl)
                localAvatarsByLogin[login] = localAvatarUrl
        }
        if (!localAvatarUrl || localAvatarUrl === item.repositoryOwnerAvatarUrl)
            return item

        var copy = _cloneMessageForMerge(item)
        copy.repositoryOwnerAvatarUrl = localAvatarUrl
        return copy
    }

    function _filterDoneMessages(items) {
        var state = operations.effectiveDoneThreadState || ({})
        var source = items || []
        var filtered = []
        for (var index = 0; index < source.length; index++) {
            var item = source[index]
            if (item && item.threadId && state[item.threadId])
                continue
            filtered.push(item)
        }
        return filtered
    }

    function _latestMessageUpdatedAtMs(items) {
        var latest = 0
        var source = items || []
        for (var index = 0; index < source.length; index++) {
            var item = source[index]
            if (!item)
                continue
            var updatedAtMs = item.updatedAtMs || Date.parse(item.updatedAt || "") || 0
            if (updatedAtMs > latest)
                latest = updatedAtMs
        }
        return latest
    }

    function _operationShouldUpdateMessageCache(actionType) {
        return actionType !== "thread_done"
               && actionType !== "threads_done"
               && actionType !== "repo_done"
    }

    function _cloneMessageForMerge(item) {
        var copy = {}
        for (var key in item)
            copy[key] = item[key]
        return copy
    }

    function _messagesEquivalent(left, right) {
        if (!left || !right || left.length !== right.length)
            return false

        for (var index = 0; index < left.length; index++) {
            if (!_messageEquivalent(left[index], right[index]))
                return false
        }
        return true
    }

    function _messageEquivalent(left, right) {
        if (!left || !right)
            return left === right

        return (left.threadId || "") === (right.threadId || "")
               && (!!left.unread === !!right.unread)
               && (left.reason || "") === (right.reason || "")
               && (!!left.participated === !!right.participated)
               && (left.updatedAt || "") === (right.updatedAt || "")
               && (left.updatedAtMs || 0) === (right.updatedAtMs || 0)
               && (left.repository || "") === (right.repository || "")
               && (left.repositoryUrl || "") === (right.repositoryUrl || "")
               && (left.repositoryOwnerLogin || "") === (right.repositoryOwnerLogin || "")
               && (left.repositoryOwnerAvatarUrl || "") === (right.repositoryOwnerAvatarUrl || "")
               && (left.subjectType || "") === (right.subjectType || "")
               && (left.title || "") === (right.title || "")
               && (left.subjectApiUrl || "") === (right.subjectApiUrl || "")
               && (left.subjectReference || "") === (right.subjectReference || "")
               && (left.webUrl || "") === (right.webUrl || "")
               && (!!left.webUrlResolved === !!right.webUrlResolved)
    }

    function _updateMessageWebUrl(threadId, webUrl) {
        _updateMessageSubjectDetails(threadId, webUrl, "")
    }

    function _updateMessageSubjectDetails(threadId, webUrl, subjectReference) {
        if (!threadId)
            return

        var changed = false
        var nextItems = []
        var normalizedSubjectReference = String(subjectReference || "").trim().replace(/^#/, "")
        for (var index = 0; index < inboxMessages.length; index++) {
            var item = inboxMessages[index]
            var shouldUpdateWebUrl = item && item.threadId === threadId && webUrl
                    && (item.webUrl !== webUrl || !item.webUrlResolved)
            var shouldUpdateReference = item && item.threadId === threadId
                    && normalizedSubjectReference
                    && item.subjectReference !== normalizedSubjectReference
            if (shouldUpdateWebUrl || shouldUpdateReference) {
                var copy = {}
                for (var key in item)
                    copy[key] = item[key]
                if (shouldUpdateWebUrl) {
                    copy.webUrl = webUrl
                    copy.webUrlResolved = true
                }
                if (shouldUpdateReference)
                    copy.subjectReference = normalizedSubjectReference
                nextItems.push(copy)
                changed = true
            } else {
                nextItems.push(item)
            }
        }

        if (!changed)
            return

        inboxMessages = nextItems
        _replaceViewMessages(nextItems)
        cacheCoord.updateMessages(nextItems)
    }

    function _clearRuntimeCacheState() {
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
        _pendingLocalAvatarUpdates = ({})
        _pendingLocalAvatarUpdateCount = 0
        _pendingNotificationMessages = []
        _apiStatsCompletionPending = false
        apiStatsCompletionTimer.stop()
        unreadCount = 0
        errorMessage = ""
        lastUpdated = 0
        fetcher.cancel()
        authorFetch.clearAllState()
        operations.resetState()
        avatarPreloader.reset()
        authorsByThread = ({})
        _latestLocalMessageUpdatedAtMs = 0
    }

    function _handleClearCacheRequest() {
        var flag = String(pluginData.clearCacheRequested || "").trim().toLowerCase()
        if (flag === "true" || flag === "1")
            _clearRuntimeCacheState()
        cacheCoord.handleClearCacheRequest(pluginData, pluginService)
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
        if (!popoutVisible) {
            pendingViewMessages = []
            pendingViewIndex = 0
            viewApplyTimer.stop()
            _profile("_queueViewMessages", profileStart,
                     "deferredUntilPopoutOpen items=" + ((items || []).length))
            return
        }

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
        if (!popoutVisible) {
            pendingViewMessages = []
            pendingViewIndex = 0
            viewApplyTimer.stop()
            _profile("_replaceViewMessages", profileStart,
                     "deferredUntilPopoutOpen items=" + ((items || []).length))
            return
        }

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
        if (!popoutVisible) {
            _profile("_appendViewMessages", profileStart,
                     "deferredUntilPopoutOpen items=" + items.length)
            return
        }

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
        if (!viewApplyTimer.running)
            _flushPendingDesktopNotificationsIfReady()
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
            operations.resetState(false)
            avatarPreloader.reset()
            authorsByThread = ({})
            expandedReposState = ({ [GitHubConstants.expandedStateDefaultKey]: true })
            expandedDateGroupsState = ({ [GitHubConstants.expandedStateDefaultKey]: true })
            _latestLocalMessageUpdatedAtMs = 0
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

    onIsRefreshBusyChanged: {
        _refreshBusySinceMs = isRefreshBusy ? Date.now() : 0
    }

    onPopoutVisibleChanged: {
        if (popoutVisible) {
            _replaceViewMessages(inboxMessages)
            return
        }
        if (!_refreshAfterPopoutClose)
            return
        _refreshAfterPopoutClose = false
        Qt.callLater(_fetchInbox)
    }

    Component.onCompleted: {
        _perfStartMs = Date.now()
        _perfLog("Component.onCompleted — start")
        _handleClearCacheRequest()
        if (token)
            cacheCoord.initialize()
        _perfLog("Component.onCompleted — end (cache init requested)")
    }

    onClearCacheRequestFlagChanged: {
        _handleClearCacheRequest()
    }

    // =========================================================================
    //  BAR PILLS
    // =========================================================================

    horizontalBarPill: Component {
        Item {
            visible: root.token !== ""
            implicitWidth: visible ? pillRow.implicitWidth : 0
            implicitHeight: visible ? pillRow.implicitHeight : 0

            Row {
                id: pillRow
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
    }

    verticalBarPill: Component {
        Item {
            visible: root.token !== ""
            implicitWidth: visible ? pillColumn.implicitWidth : 0
            implicitHeight: visible ? pillColumn.implicitHeight : 0

            Column {
                id: pillColumn
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
    }

    // =========================================================================
    //  POPOUT
    // =========================================================================

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "GitHub Inbox"
            detailsText: ""
            showCloseButton: false

            Component.onCompleted: root.popoutVisible = true
            Component.onDestruction: root.popoutVisible = false

            Item {
                id: popoutDetailsRow
                width: parent.width
                height: GitHubConstants.popoutFilterSegmentHeightPx + Theme.spacingS

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: groupingControl.visible ? groupingControl.left : parent.right
                    anchors.rightMargin: groupingControl.visible ? Theme.spacingS : Theme.spacingS
                    anchors.verticalCenter: groupingControl.visible ? groupingControl.verticalCenter : parent.verticalCenter
                    text: root.popoutDetails
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                }

                Row {
                    id: groupingControl
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.top: parent.top
                    spacing: Theme.spacingXS
                    height: GitHubConstants.popoutFilterSegmentHeightPx
                    visible: root.token !== ""

                    StyledText {
                        id: groupingLabel
                        text: "Group By"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: GitHubConstants.popoutFilterSegmentMinWidthPx
                        height: GitHubConstants.popoutFilterSegmentHeightPx
                        radius: Theme.cornerRadius
                        color: Theme.nestedSurface
                        border.width: 1
                        border.color: Theme.outlineMedium

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            cursorShape: Qt.PointingHandCursor
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 0
                            spacing: 1

                            Repeater {
                                model: [
                                    { label: "Repo", value: "repo" },
                                    { label: "Date", value: "date" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    width: (parent.width - 1) / 2
                                    height: parent.height
                                    radius: Theme.cornerRadius
                                    color: root.groupingMode === modelData.value
                                           ? Theme.withAlpha(Theme.primary, GitHubConstants.popoutFilterActiveTintOpacity)
                                           : "transparent"

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setGroupingMode(modelData.value)
                                    }

                                    StyledText {
                                        anchors.fill: parent
                                        anchors.leftMargin: 2
                                        anchors.rightMargin: 2
                                        text: modelData.label
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: root.groupingMode === modelData.value ? Font.DemiBold : Font.Normal
                                        color: root.groupingMode === modelData.value ? Theme.primary : Theme.surfaceVariantText
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            PopoutPanel {
                width: parent.width
                implicitHeight: root.popoutHeight
                                - popout.headerHeight
                                - popoutDetailsRow.height
                                - Theme.spacingXL

                messages: root.messagesForView
                unreadCount: root.unreadCount
                tokenConfigured: root.token !== ""
                isLoading: fetcher.isLoading
                isAuthorFetching: authorFetch.isBusy
                isOperating: operations.isBusy
                isDownloadingAvatars: cacheCoord.isDownloadingAvatars
                errorMessage: root.errorMessage
                headerOffset: popout.headerHeight + popoutDetailsRow.height
                headerHoverHeight: popout.headerHeight
                headerHoverBottomInset: popoutDetailsRow.height
                titleLines: root.titleLines
                groupItemLimit: root.groupItemLimit
                expandedReposState: root.expandedReposState
                expandedDateGroupsState: root.expandedDateGroupsState
                authorsByThread: root.authorsByThread
                showAuthorInfo: root.loadAuthorInfo
                groupingMode: root.groupingMode

                onRefreshNow: root._refreshNow()
                onMarkAllRead: operations.markAllAsRead()
                onMarkRepoRead: function(items) {
                    operations.markThreadsAsRead(items)
                }
                onMarkRepoDone: function(items) {
                    operations.markThreadsDone(items)
                }
                onMarkDateGroupRead: function(items) {
                    operations.markThreadsAsRead(items)
                }
                onMarkDateGroupDone: function(items) {
                    operations.markThreadsDone(items)
                }
                onMarkThreadRead: function(threadId) { operations.markThreadAsRead(threadId) }
                onMarkThreadUnread: function(threadId) { operations.markThreadAsUnread(threadId) }
                onMarkThreadDone: function(threadId) { operations.markThreadDone(threadId) }
                onRequestThreadAuthors: function(threadId, subjectApiUrl, subjectType) {
                    if (!root.loadAuthorInfo) return
                    var notifUpdatedAt = ""
                    var resolvedSubjectApiUrl = subjectApiUrl || ""
                    var resolvedSubjectType = subjectType || ""
                    var resolvedSubjectTitle = ""
                    for (var ni = 0; ni < root.inboxMessages.length; ni++) {
                        if (root.inboxMessages[ni].threadId === threadId) {
                            notifUpdatedAt = root.inboxMessages[ni].updatedAt || ""
                            resolvedSubjectTitle = root.inboxMessages[ni].title || ""
                            if (!resolvedSubjectApiUrl)
                                resolvedSubjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(root.inboxMessages[ni])
                            if (!resolvedSubjectType)
                                resolvedSubjectType = root.inboxMessages[ni].subjectType || ""
                            break
                        }
                    }
                    authorFetch.enqueueAuthorFetch(threadId, resolvedSubjectApiUrl, resolvedSubjectType, notifUpdatedAt, false, null, resolvedSubjectTitle)
                }
                onClosePopout: root.closePopout()
                onPersistExpandedRepos: function(state) {
                    root.expandedReposState = root._cloneExpandedState(state)
                }
                onPersistExpandedDateGroups: function(state) {
                    root.expandedDateGroupsState = root._cloneExpandedState(state)
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
