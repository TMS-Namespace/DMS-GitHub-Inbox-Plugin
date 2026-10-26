// Widget.qml - Main GitHub Inbox widget orchestrator for DankMaterialShell
//
// This file is the top-level PluginComponent that wires together the
// extracted sub-components.  Business logic lives in the delegates:
//   - InboxFetchService      --- inbox requests, pagination and chunk buffering
//   - AuthorBackgroundWorker --- author data queue, dedup, fetching
//   - InboxOperations     --- mark read/done/unread operations
//   - AvatarPreloader     --- hidden Image warm-up cache
//   - CacheCoordinator    --- disk cache bridge (messages, authors, avatars)
//   - AuthorUtils         --- pure helper functions (singleton)

pragma ComponentBehavior: Bound
import QtQml

import QtQuick
import "."
import qs.Common
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    property bool _apiStatsCompletionPending: false
    property real _lastDoneCacheCleanupAt: 0
    property real _lastUiStallProbeAt: 0

    // =========================================================================
    //  RUNTIME STATE
    // =========================================================================

    property real _perfStartMs: 0
    property alias authorsByThread: inboxEnrichment.authorsByThread
    property string barCountText: unreadCount > 0 ? providerApi.formatCountValue(unreadCount) : ""
    property alias clearCacheRequestFlag: preferences.clearCacheRequestFlag
    property alias enableNotifications: preferences.enableNotifications
    property string errorMessage: ""
    property var expandedDateGroupsState: ({
            [GitHubConstants.expandedStateDefaultKey]: true
        })
    property var expandedReposState: ({
            [GitHubConstants.expandedStateDefaultKey]: true
        })
    property url githubIconFallback: Qt.resolvedUrl("../../images/github-mark.svg")
    property url githubIconPrimary: GitHubConstants.githubFaviconUrl
    property alias groupItemLimit: preferences.groupItemLimit
    property alias groupingMode: preferences.groupingMode
    property var inboxMessages: []
    property bool isRefreshBusy: inboxFetch.isLoading || authorFetch.isBusy || cacheCoord.isDownloadingAvatars
    property real lastUpdated: 0
    property alias loadAuthorInfo: preferences.loadAuthorInfo
    property alias messagesForView: inboxViewState.messagesForView
    property alias participationFilter: preferences.participationFilter
    property alias pollIntervalMs: preferences.pollIntervalMs
    property string popoutDetails: {
        if (secretStore.secretStorageUnavailable)
            return secretStore.statusMessage || "Secret Service is unavailable.";
        if (!token)
            return "Set your GitHub classic token in Settings";
        if (inboxFetch.isLoading && inboxMessages.length === 0)
            return "Loading messages...";
        if (errorMessage && inboxMessages.length === 0)
            return errorMessage;

        let counts = unreadCount + " unread / " + readCount + " read / " + totalCount + " total";
        return counts;
    }
    property alias popoutHeightPixels: preferences.popoutHeight
    property bool popoutVisible: false
    property alias popupHeightUnits: preferences.popupHeightUnits
    readonly property var providerApi: GitHubManager.getProviderApi(GitHubManager.providerTypes[0])
    property int readCount: Math.max(0, inboxMessages.length - unreadCount)
    property alias readFilter: preferences.readFilter
    property alias titleLines: preferences.titleLines

    // =========================================================================
    //  SETTINGS-BACKED STATE
    // =========================================================================

    property string token: (secretStore.token || "").trim()

    // -- Computed properties --------------------------------------------------
    property int totalCount: inboxMessages.length
    property int unreadCount: 0
    property bool workerScriptsEnabled: true

    // Reconcile only the covered window and retain older cached threads outside it.
    function _applyFetchedMessages(items, unread, fetchWasComplete) {
        // GitHub's list response has no Done field. Pseudo-sync Done by treating
        // a previously cached thread as Done only after the fetcher confirms that
        // its response covers the cached window (or has reached its final page).
        // This is deliberately based on `updated_at`, not notification reason or
        // repository visibility: https://docs.github.com/en/rest/activity/notifications#list-notifications-for-the-authenticated-user
        // A returned thread clears a prior inferred entry. For plugin-originated
        // Done entries, a later `updated_at` reopens the thread; an unchanged
        // response preserves the local Done choice.
        let nextItems = inboxMessageState.mergeCachedMessageFields(items || [], inboxMessages, authorsByThread, cacheCoord, cacheCoord.initialized);
        operations.clearReturnedDoneThreadState(nextItems);
        nextItems = operations.applyPendingReadState(nextItems);
        if (fetchWasComplete) {
            let inferredDoneMessages = inboxMessageState.inferDoneMessagesFromRefresh(inboxMessages, nextItems, operations.effectiveDoneThreadState);
            if (inferredDoneMessages.length > 0) {
                PluginLogger.debug("refresh", "Inferred " + inferredDoneMessages.length + " missing threads as done after complete refresh");
            }
            if (inferredDoneMessages.length > 0)
                operations.markMessagesLocallyDone(inferredDoneMessages, "github_missing_from_complete_refresh");
        }
        nextItems = inboxMessageState.retainUncoveredMessages(inboxMessages, nextItems, fetchWasComplete);
        nextItems = inboxMessageState.filterDoneMessages(nextItems, operations.effectiveDoneThreadState);
        let nextUnread = inboxMessageState.recalculateUnread(nextItems);
        let unchanged = nextUnread === unreadCount && inboxMessageState.messagesEquivalent(inboxMessages, nextItems);
        if (unchanged) {
            _clearError();
            lastUpdated = Date.now();
            cacheCoord.updateMessages(inboxMessages, lastUpdated);
            _perfLog("_applyFetchedMessages --- unchanged, skipped UI/cache/enrichment");
            return false;
        }

        inboxMessages = nextItems;
        unreadCount = nextUnread;
        inboxViewState.queue(nextItems);
        _clearError();
        lastUpdated = Date.now();
        let newMessages = desktopNotifications.detectNewMessages(nextItems, operations.effectiveDoneThreadState);
        cacheCoord.updateMessages(nextItems, lastUpdated);
        desktopNotifications.setBaseline(nextItems);
        desktopNotifications.queue(newMessages);
        return true;
    }
    // Replace affected message and author maps so existing delegates observe new local URLs.
    function _applyLocalAvatarUpdates(updates) {
        let profileStart = Date.now();
        let result = avatarState.applyLocalAvatarUpdates(inboxMessages, messagesForView, authorsByThread, updates);
        if (result.messagesChanged)
            inboxMessages = result.messages;
        if (result.viewMessagesChanged)
            inboxViewState.updateRendered(result.viewMessages);
        if (result.authorsChanged)
            authorsByThread = result.authorsByThread;
        _profile("_applyLocalAvatarUpdates", profileStart, "updates=" + Object.keys(updates || {}).length + " messagesChanged=" + result.messagesChanged + " authorsChanged=" + result.authorsChanged);
    }
    // Run bounded Done-state retention at most once per maintenance interval.
    function _cleanupDoneCacheIfDue() {
        let now = Date.now();
        if (_lastDoneCacheCleanupAt > 0 && now - _lastDoneCacheCleanupAt < GitHubConstants.doneStateCleanupIntervalMs)
            return;
        _lastDoneCacheCleanupAt = now;
        operations.pruneDoneThreadState(GitHubConstants.doneStateRetentionMs);
        cacheCoord.updateMessages(inboxMessages);
    }
    // Clear user-visible failure state only through the shared error service.
    function _clearError() {
        errorService.clear();
        errorMessage = "";
    }
    // Invalidate runtime work before removing its backing cached records.
    function _clearRuntimeCacheState() {
        inboxMessages = [];
        inboxViewState.reset();
        inboxEnrichment.reset();
        avatarPropagation.reset();
        desktopNotifications.reset();
        _apiStatsCompletionPending = false;
        apiStatsCompletionTimer.stop();
        unreadCount = 0;
        _clearError();
        lastUpdated = 0;
        inboxFetch.cancel();
        authorFetch.clearAllState();
        operations.resetState();
        avatarPreloader.reset();
        authorsByThread = ({});
    }
    // Delegate refresh scheduling and active-work policy to its owning coordinator.
    function _fetchInbox(allowWhilePopout) {
        _perfLog("_fetchInbox --- called");
        refreshCoordinator.requestFetch(allowWhilePopout);
        _perfLog("_fetchInbox --- fetch() dispatched");
    }
    // Finish cache maintenance and queued work after the new message state is applied.
    function _finalizeFetchCycle(messagesChanged) {
        if (messagesChanged)
            inboxEnrichment.pruneAuthorCaches(inboxMessages);
        _cleanupDoneCacheIfDue();
        _scheduleApiStatsRefreshComplete();
        inboxFetch.retryIfQueued();
    }
    // Consume the saved clear flag once and reset matching runtime state.
    function _handleClearCacheRequest() {
        let flag = String(pluginData.clearCacheRequested || "").trim().toLowerCase();
        if (flag === "true" || flag === "1")
            _clearRuntimeCacheState();
        cacheCoord.handleClearCacheRequest(pluginData, pluginService);
    }
    // Restore messages and author state before applying the cache-aware refresh schedule.
    function _onCacheReady() {
        if (!token)
            return;
        let cached = cacheCoord.loadCachedState();
        operations.setDoneThreadState(cached.doneThreadState || ({}));
        let cachedMessages = inboxMessageState.filterDoneMessages(cached.messages || [], operations.effectiveDoneThreadState);
        if (cachedMessages.length > 0) {
            inboxMessages = cachedMessages;
            unreadCount = inboxMessageState.recalculateUnread(cachedMessages);
            inboxViewState.queue(cachedMessages);
            lastUpdated = cached.timestamp;
        }
        inboxEnrichment.hydrateCachedDetails(cachedMessages, cached.authorsByThread || ({}), cached.authorFetchedAt || ({}));
        refreshCoordinator.restoreSchedule(cached.timestamp, cached.pollIntervalMs);
    }
    // Keep optimistic Done removal separate from confirmed cache persistence.
    function _operationShouldUpdateMessageCache(actionType) {
        return actionType !== "thread_done" && actionType !== "threads_done" && actionType !== "repo_done";
    }

    // =========================================================================
    //  ORCHESTRATION LOGIC
    // =========================================================================

    // Route lifecycle diagnostics through the shared development logger.
    function _perfLog(label) {
        let elapsed = (Date.now() - _perfStartMs).toFixed(0);
        PluginLogger.debug("Widget", "+" + elapsed + "ms " + label);
    }
    // Record unusually long UI scheduling gaps only when diagnostics are enabled.
    function _probeUiStall() {
        let now = Date.now();
        if (_lastUiStallProbeAt > 0) {
            let gap = now - _lastUiStallProbeAt;
            if (gap >= GitHubConstants.uiStallLogThresholdMs) {
                PluginLogger.profile("Widget", "uiStallProbe", gap, "fetchLoading=" + inboxFetch.isLoading + " authorBusy=" + authorFetch.isBusy + " avatarBusy=" + cacheCoord.isDownloadingAvatars + " viewApply=" + inboxViewState.isApplying + " authorQueue=" + authorFetch.requestQueue.length + " authorInFlight=" + authorFetch.requestsInFlight);
                if (gap >= GitHubConstants.wakeRefreshRecoveryGapMs)
                    refreshCoordinator.recoverStaleBackgroundWork("wake/stall gap " + gap + "ms", true);
            }
        }
        _lastUiStallProbeAt = now;
    }
    // Measure this operation through the shared profiling gate.
    function _profile(label, startMs, details) {
        let duration = Date.now() - startMs;
        PluginLogger.profile("Widget", label, duration, details);
    }
    // -- View helpers ---------------------------------------------------------

    // Send an explicit refresh through the coordinator rather than duplicating busy-state rules.
    function _refreshNow() {
        refreshCoordinator.refreshNow();
    }
    // Keep raw diagnostics behind the error service while exposing only the friendly message.
    function _reportError(scope, userMessage, retryable) {
        errorMessage = errorService.report(scope, userMessage, "", retryable);
    }
    // Defer session completion until all refresh work has settled.
    function _scheduleApiStatsRefreshComplete() {
        _apiStatsCompletionPending = true;
        apiStatsCompletionTimer.restart();
    }
    // Finish queued prefetch accounting only after pending merges and downloads settle.
    function _tryFinalizeAuthorPrefetch() {
        if (!authorFetch.prefetchPending)
            return;
        if (authorFetch.requestsInFlight > 0 || authorFetch.requestQueue.length > 0)
            return;
        if (authorFetch.hasPendingPrefetchWork())
            return;
        if (inboxFetch.isLoading)
            return;
        inboxEnrichment.pruneAuthorCaches(inboxMessages);
        authorFetch.prefetchPending = false;
        _scheduleApiStatsRefreshComplete();

        Qt.callLater(operations.processPendingDoneQueue);
        inboxFetch.retryIfQueued();
    }
    // Keep author and avatar time within the current refresh measurement.
    function _tryRecordApiStatsRefreshComplete() {
        if (!_apiStatsCompletionPending)
            return;
        if (inboxFetch.isLoading || authorFetch.isBusy || cacheCoord.isDownloadingAvatars || inboxEnrichment.backgroundEnrichmentRunning || inboxViewState.isApplying) {
            apiStatsCompletionTimer.restart();
            return;
        }

        _apiStatsCompletionPending = false;
        if (GitHubConstants.apiCallStatsEnabled)
            ApiCallStats.recordRefreshComplete();
        desktopNotifications.flushIfReady(popoutVisible, inboxViewState.isApplying, inboxViewState.pendingCount);
    }
    // Apply resolved subject URLs and human-visible references to matching threads only.
    function _updateMessageSubjectDetails(threadId, webUrl, subjectReference) {
        let nextItems = InboxMessageDetails.withResolvedSubjectDetails(inboxMessages, threadId, webUrl, subjectReference);
        if (nextItems === inboxMessages)
            return;
        inboxMessages = nextItems;
        inboxViewState.replace(nextItems);
        cacheCoord.updateMessages(nextItems);
    }
    // Preserve the existing subject reference while resolving its browser destination.
    function _updateMessageWebUrl(threadId, webUrl) {
        _updateMessageSubjectDetails(threadId, webUrl, "");
    }

    layerNamespacePlugin: GitHubConstants.pluginNamespaceId
    popoutHeight: popoutHeightPixels
    popoutWidth: Math.round(GitHubConstants.popoutBaseWidthPx * GitHubConstants.popoutWidthScale)

    // =========================================================================
    //  BAR PILLS
    // =========================================================================

    horizontalBarPill: Component {
        InboxBarPill {
            countText: root.barCountText
            githubIconFallback: root.githubIconFallback
            githubIconPrimary: root.githubIconPrimary
            iconSize: root.iconSize
            textSize: root.textSize
            tokenConfigured: root.token !== ""
            unreadCount: root.unreadCount
        }
    }

    // =========================================================================
    //  POPOUT
    // =========================================================================

    popoutContent: Component {
        InboxPopoutContent {
            authorRequestCallback: inboxEnrichment.requestThreadAuthors
            authorsByThread: root.authorsByThread
            closePopoutCallback: function () {
                root.closePopout();
            }
            details: root.popoutDetails
            errorMessage: root.errorMessage
            expandedDateGroupsState: root.expandedDateGroupsState
            expandedReposState: root.expandedReposState
            groupItemLimit: root.groupItemLimit
            groupingMode: root.groupingMode
            inboxHeight: root.popoutHeight
            isAuthorFetching: authorFetch.isBusy
            isDownloadingAvatars: cacheCoord.isDownloadingAvatars
            isLoading: inboxFetch.isLoading
            isOperating: operations.isBusy
            lastUpdated: root.lastUpdated
            messages: root.messagesForView
            openSettingsCallback: function () {
                root.closePopout();
                PopoutService.openSettingsWithTab(SettingsTabs.pluginPrefix + GitHubConstants.pluginNamespaceId);
            }
            operationService: operations
            participationFilter: root.participationFilter
            persistExpandedDateGroupsCallback: function (state) {
                root.expandedDateGroupsState = inboxMessageState.cloneExpandedState(state);
            }
            persistExpandedReposCallback: function (state) {
                root.expandedReposState = inboxMessageState.cloneExpandedState(state);
            }
            popupOpen: root.popoutVisible
            preferencesService: preferences
            readFilter: root.readFilter
            refreshCallback: function () {
                root._refreshNow();
            }
            showAuthorInfo: root.loadAuthorInfo
            titleLines: root.titleLines
            tokenConfigured: root.token !== ""
            unreadCount: root.unreadCount
            visibilityChangedCallback: function (visible) {
                root.popoutVisible = visible;
            }
        }
    }
    verticalBarPill: Component {
        InboxBarPill {
            countText: root.barCountText
            githubIconFallback: root.githubIconFallback
            githubIconPrimary: root.githubIconPrimary
            iconSize: root.iconSize
            textSize: root.textSize
            tokenConfigured: root.token !== ""
            unreadCount: root.unreadCount
            vertical: true
        }
    }

    Component.onCompleted: {
        _perfStartMs = Date.now();
        _perfLog("Component.onCompleted --- start");
        if (!providerApi) {
            _reportError("provider", GitHubManager.loadErrors.join(" ") || "The GitHub provider could not be loaded.", false);
            return;
        }
        _handleClearCacheRequest();
        if (token)
            cacheCoord.initialize();
        _perfLog("Component.onCompleted --- end (cache init requested)");
    }
    onClearCacheRequestFlagChanged: {
        _handleClearCacheRequest();
    }
    onGroupItemLimitChanged: {
        if (token && cacheCoord.initialized)
            _fetchInbox();
    }
    onIsRefreshBusyChanged: refreshCoordinator.noteRefreshBusyChanged(isRefreshBusy)
    onLoadAuthorInfoChanged: {
        authorFetch.resetState();

        if (!loadAuthorInfo) {
            authorsByThread = ({});
            authorFetch.clearAllState();
            avatarPreloader.reset();
            inboxEnrichment.cancelBackgroundEnrichment();
            return;
        }

        if (token && inboxMessages.length > 0)
            inboxEnrichment.scheduleBackgroundEnrichment(inboxMessages);
    }

    // =========================================================================
    //  PROPERTY-CHANGE HANDLERS
    // =========================================================================

    onPopoutVisibleChanged: {
        if (popoutVisible) {
            return;
        }
        if (!refreshCoordinator.resumeAfterPopoutClose())
            return;
        Qt.callLater(_fetchInbox);
    }
    onTokenChanged: {
        _perfLog("onTokenChanged --- token=" + (token ? "set" : "empty") + " cacheCoord.initialized=" + cacheCoord.initialized);
        if (!token) {
            inboxMessages = [];
            inboxViewState.reset();
            inboxEnrichment.reset();
            unreadCount = 0;
            _clearError();
            lastUpdated = 0;
            inboxFetch.cancel();
            authorFetch.clearAllState();
            operations.resetState(false);
            avatarPreloader.reset();
            authorsByThread = ({});
            expandedReposState = ({
                    [GitHubConstants.expandedStateDefaultKey]: true
                });
            expandedDateGroupsState = ({
                    [GitHubConstants.expandedStateDefaultKey]: true
                });
            desktopNotifications.reset();
            return;
        }
        if (cacheCoord.initialized)
            _fetchInbox();
        else
            cacheCoord.initialize();
    }

    // =========================================================================
    //  SUB-COMPONENTS
    // =========================================================================

    InboxPreferencesService {
        id: preferences

        pluginData: root.pluginData
        pluginService: root.pluginService
        providerApi: root.providerApi
    }
    InboxMessageState {
        id: inboxMessageState

        constants: GitHubConstants
    }
    AvatarState {
        id: avatarState
    }
    AvatarPropagationService {
        id: avatarPropagation

        onBatchReady: function (updates) {
            root._applyLocalAvatarUpdates(updates);
        }
    }
    InboxViewState {
        id: inboxViewState

        popoutVisible: root.popoutVisible
        sourceMessages: root.inboxMessages

        onSettled: desktopNotifications.flushIfReady(root.popoutVisible, isApplying, pendingCount)
    }
    InboxEnrichmentService {
        id: inboxEnrichment

        authorWorker: authorFetch
        avatarPreloader: avatarPreloader
        cacheCoordinator: cacheCoord
        fetchBusy: inboxFetch.isLoading
        loadAuthorInfo: root.loadAuthorInfo
        messageState: inboxMessageState
        messages: root.inboxMessages
        popoutApplying: inboxViewState.isApplying
        resourceRepository: resourceRepo
        tokenAvailable: root.token !== ""
    }
    ErrorService {
        id: errorService
    }
    DesktopNotificationService {
        id: desktopNotifications

        cacheCoordinator: cacheCoord
        fallbackIcon: root.githubIconFallback
        messageState: inboxMessageState
        notificationsEnabled: root.enableNotifications
    }
    CacheCoordinator {
        id: cacheCoord

        cacheWorkersEnabled: root.workerScriptsEnabled
        pollIntervalMs: root.pollIntervalMs
        providerApi: root.providerApi

        onCacheFailure: function (message) {
            root._reportError("cache", message, true);
        }
        onCacheReady: root._onCacheReady()
    }
    ResourceRepository {
        id: resourceRepo

        cacheCoordinator: cacheCoord

        onAvatarResourcesReady: function (updates) {
            for (let login in updates) {
                avatarPreloader.updateEntrySource(login, updates[login]);
                avatarPropagation.queue(login, updates[login]);
            }
        }
    }
    SecretStore {
        id: secretStore

        fatalOnUnavailable: true
        pluginService: root.pluginService

        onActivationRefused: function (message) {
            root._reportError("activation", message, false);
        }
    }
    InboxFetchService {
        id: inboxFetch

        parserWorkerEnabled: root.workerScriptsEnabled
        providerApi: root.providerApi
        targetOldestVisibleUpdatedAtMs: inboxMessageState.oldestMessageUpdatedAtMs(root.inboxMessages)
        token: root.token

        onAuthorResultReceived: function (message) {
            authorFetch.handleAuthorResult(message);
        }
        onFetchBegan: function (totalCount, unreadCount) {
            root._perfLog("onFetchBegin --- total=" + totalCount + " unread=" + unreadCount);
            desktopNotifications.setBaseline(root.inboxMessages);
            inboxEnrichment.cancelBackgroundEnrichment();
            authorFetch.resetState();
            authorFetch.prefetchPending = false;
            root.lastUpdated = Date.now();
        }
        onFetchFailed: function (errorMessage, wasManual) {
            root._perfLog("onFetchError");
            desktopNotifications.clearPending();
            authorFetch.resetState();
            root._reportError("inbox", errorMessage, true);
            root.lastUpdated = Date.now();
            desktopNotifications.notifyFetchError(errorMessage, wasManual);
            root._scheduleApiStatsRefreshComplete();
            Qt.callLater(operations.processPendingDoneQueue);
        }
        onFetchResultReady: function (items, unreadCount, complete) {
            root._perfLog("onFetchComplete --- items=" + items.length + " unread=" + unreadCount);
            let changed = root._applyFetchedMessages(items, unreadCount, complete);
            authorFetch.prefetchPending = false;
            inboxEnrichment.scheduleBackgroundEnrichment(root.inboxMessages);
            root._finalizeFetchCycle(changed);
        }
    }
    AuthorBackgroundWorker {
        id: authorFetch

        authorsByThreadRef: root.authorsByThread
        loadAuthorInfo: root.loadAuthorInfo
        token: root.token
        workerSendMessage: inboxFetch.sendWorkerMessage

        onAuthorFetchedAtChanged: function (threadId, updatedAt) {
            cacheCoord.updateAuthorFetchedAt(threadId, updatedAt);
        }
        onAuthorsMerged: function (mergedAuthors, preloadAuthors, changedThreadIds) {
            // Only resolve avatar URLs for threads that actually changed
            for (let i = 0; i < changedThreadIds.length; i++) {
                let changedThreadId = changedThreadIds[i];
                if (mergedAuthors[changedThreadId])
                    resourceRepo.requestAuthorAvatars(mergedAuthors[changedThreadId]);
            }

            let changedAuthorsForCache = {};
            for (let cacheIndex = 0; cacheIndex < changedThreadIds.length; cacheIndex++) {
                let cacheThreadId = changedThreadIds[cacheIndex];
                changedAuthorsForCache[cacheThreadId] = mergedAuthors[cacheThreadId] || [];
            }

            root.authorsByThread = mergedAuthors;
            cacheCoord.updateChangedAuthors(changedAuthorsForCache);

            if (preloadAuthors.length > 0)
                avatarPreloader.queueFromAuthors(preloadAuthors);
        }
        onExpansionUrlsDiscovered: function (threadId, urls) {
            authorFetch.enqueueAuthorUrls(threadId, urls);
        }
        onPrefetchMaybeComplete: root._tryFinalizeAuthorPrefetch()
        onSubjectWebUrlResolved: function (threadId, webUrl, subjectReference) {
            root._updateMessageSubjectDetails(threadId, webUrl, subjectReference);
        }
    }
    InboxOperations {
        id: operations

        isLoading: inboxFetch.isLoading
        providerApi: root.providerApi
        token: root.token

        onDoneThreadStateChanged: {
            if (cacheCoord.initialized)
                cacheCoord.updateDoneThreadState(doneThreadState);
        }
        onIsBusyChanged: {
            refreshCoordinator.noteOperationBusyChanged(isBusy);
        }
        onOperationApplied: function (actionType, threadId, repositoryFullName, threadIds) {
            let result = operations.applyResult(actionType, threadId, repositoryFullName, root.inboxMessages, threadIds || []);
            let itemsChanged = result.items !== root.inboxMessages;
            if (itemsChanged) {
                root.inboxMessages = result.items;
                inboxViewState.replace(root.inboxMessages);
                if (root._operationShouldUpdateMessageCache(actionType))
                    cacheCoord.updateMessages(root.inboxMessages);
            }
            if (itemsChanged || result.unreadChanged)
                root.unreadCount = inboxMessageState.recalculateUnread(root.inboxMessages);
            root._clearError();
            root.lastUpdated = Date.now();
        }
        onOperationError: function (errorMessage) {
            root._reportError("operation", errorMessage, true);
        }
    }
    InboxRefreshCoordinator {
        id: refreshCoordinator

        authorWorker: authorFetch
        cacheCoordinator: cacheCoord
        enrichmentService: inboxEnrichment
        fetchService: inboxFetch
        isRefreshBusy: root.isRefreshBusy
        operations: operations
        pollIntervalMs: root.pollIntervalMs
        popoutVisible: root.popoutVisible
        token: root.token

        onMissingTokenRequested: root._reportError("inbox", "Set your GitHub token in Settings.", false)
        onStaleWorkRecovered: {
            root._apiStatsCompletionPending = false;
            apiStatsCompletionTimer.stop();
        }
    }
    AvatarPreloader {
        id: avatarPreloader
    }
    // =========================================================================
    //  TIMERS
    // =========================================================================

    Timer {
        id: uiStallProbeTimer

        interval: GitHubConstants.profileLoggingEnabled ? GitHubConstants.uiStallProbeIntervalMs : 5000
        repeat: true
        running: root.token !== ""

        onTriggered: root._probeUiStall()
    }
    Timer {
        id: apiStatsCompletionTimer

        interval: 250
        repeat: false

        onTriggered: root._tryRecordApiStatsRefreshComplete()
    }
}
