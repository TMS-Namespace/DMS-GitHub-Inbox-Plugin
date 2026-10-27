// InboxEnrichmentService.qml - restores cached authors and schedules avatar enrichment.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: service

    property var authorWorker: null
    property var authorsByThread: ({})
    property var avatarPreloader: null
    readonly property bool backgroundEnrichmentRunning: backgroundEnrichmentTimer.running
    property var cacheCoordinator: null
    property bool fetchBusy: false
    property bool loadAuthorInfo: true
    property var messageState: null
    property var messages: []
    property var pendingCacheState: null
    property var pendingEnrichmentMessages: []
    property int pendingStartupAuthorAvatarIndex: 0
    property var pendingStartupAuthorAvatarLists: []
    property var pendingStartupAuthorMessages: []
    property bool popoutApplying: false
    property var resourceRepository: null
    property bool startupAuthorPrefetchQueued: false
    property bool tokenAvailable: false

    // Stop the delayed enrichment pass and discard its pending messages.
    function cancelBackgroundEnrichment() {
        backgroundEnrichmentTimer.stop();
        pendingEnrichmentMessages = [];
    }
    // Stop startup scans and clear their pending messages and avatar lists.
    function cancelPendingScans() {
        startupMissingInfoTimer.stop();
        pendingStartupAuthorMessages = [];
        pendingStartupAuthorAvatarLists = [];
        pendingStartupAuthorAvatarIndex = 0;
        startupAuthorPrefetchQueued = false;
    }
    // Select missing details without refetching already usable local resources.
    function filterMessagesNeedingEnrichment(items) {
        let result = [];
        let source = items || [];
        for (let index = 0; index < source.length; index++) {
            let item = source[index];
            if (!item || !item.threadId)
                continue;
            let needsAvatar = !!item.repositoryOwnerLogin && String(item.repositoryOwnerAvatarUrl || "").indexOf("file://") !== 0;
            let knownAuthors = authorsByThread[item.threadId] || [];
            let needsMissingAuthors = loadAuthorInfo && knownAuthors.length === 0;
            let needsAuthor = loadAuthorInfo && (needsMissingAuthors || !authorWorker.fetchedAtMatches(authorWorker.fetchedAtUpdatedAt[item.threadId], item.updatedAt) || authorWorker.requiresSubjectWebUrlResolution(item) || authorWorker.requiresSubjectReferenceResolution(item) || !authorWorker.hasFetchedAuthorDetailsForMessage(item));
            if (needsAvatar || needsAuthor)
                result.push(item);
        }
        return result;
    }
    // Stage cached data for deferred restoration without retaining visual controls.
    function hydrateCachedDetails(messages, cachedAuthors, cachedFetchedAt) {
        pendingCacheState = {
            authorsByThread: cachedAuthors || ({}),
            authorFetchedAt: cachedFetchedAt || ({}),
            messages: messages || []
        };
        Qt.callLater(prepareCachedAuthors);
    }
    // Warm a bounded set of local resources after cached author metadata is restored.
    function prepareAvatarPreload() {
        let cached = pendingCacheState;
        pendingCacheState = null;
        if (!cached)
            return;

        let preloadAuthors = [];
        let sourceMessages = cached.messages || [];
        for (let index = 0; index < sourceMessages.length && preloadAuthors.length < GitHubConstants.avatarPreloadTotalCacheLimit; index++) {
            let message = sourceMessages[index];
            preloadAuthors.push({
                login: message.repositoryOwnerLogin || "",
                avatarUrl: message.repositoryOwnerAvatarUrl || "",
                htmlUrl: message.repositoryOwnerLogin ? GitHubConstants.githubWebBaseUrl + "/" + encodeURIComponent(message.repositoryOwnerLogin) : ""
            });
        }
        for (let threadId in cached.resolvedAuthors) {
            if (preloadAuthors.length >= GitHubConstants.avatarPreloadTotalCacheLimit)
                break;
            let authors = cached.resolvedAuthors[threadId] || [];
            for (let index = 0; index < authors.length && preloadAuthors.length < GitHubConstants.avatarPreloadTotalCacheLimit; index++)
                preloadAuthors.push(authors[index]);
        }
        if (preloadAuthors.length > 0)
            avatarPreloader.queueFromAuthors(preloadAuthors);
        scheduleStartupScan(sourceMessages, cached.resolvedAuthors);
    }
    // Restore current author records before scheduling avatar and missing-detail work.
    function prepareCachedAuthors() {
        let cached = pendingCacheState;
        if (!cached)
            return;

        let resolvedAuthors = {};
        for (let threadId in cached.authorsByThread) {
            let authors = cached.authorsByThread[threadId];
            if (authors && typeof authors.length === "number")
                resolvedAuthors[threadId] = authors;
        }

        let fetchedAt = {};
        for (let threadId in cached.authorFetchedAt)
            fetchedAt[threadId] = cached.authorFetchedAt[threadId];
        sanitizeCachedAuthors(cached.messages, resolvedAuthors, fetchedAt);
        authorWorker.fetchedAtUpdatedAt = fetchedAt;
        authorsByThread = resolvedAuthors;
        pendingCacheState = {
            messages: cached.messages,
            resolvedAuthors: resolvedAuthors
        };
        Qt.callLater(prepareAvatarPreload);
    }
    // Spread cache hydration across bounded batches instead of blocking popup creation.
    function processStartupBatch() {
        if (!tokenAvailable) {
            startupMissingInfoTimer.stop();
            return;
        }
        if (fetchBusy || popoutApplying)
            return;

        let batchSize = Math.max(1, GitHubConstants.startupMissingInfoScanBatchSize);
        let processed = 0;
        while (processed < batchSize && pendingStartupAuthorAvatarIndex < pendingStartupAuthorAvatarLists.length) {
            resourceRepository.requestAuthorAvatars(pendingStartupAuthorAvatarLists[pendingStartupAuthorAvatarIndex]);
            pendingStartupAuthorAvatarIndex++;
            processed++;
        }
        if (!startupAuthorPrefetchQueued && loadAuthorInfo && pendingStartupAuthorMessages.length > 0) {
            authorWorker.prefetchMissingForMessages(pendingStartupAuthorMessages, authorsByThread);
            startupAuthorPrefetchQueued = true;
        }
        let authorRecoveryDone = startupAuthorPrefetchQueued || pendingStartupAuthorMessages.length === 0 || !loadAuthorInfo;
        if (pendingStartupAuthorAvatarIndex >= pendingStartupAuthorAvatarLists.length && authorRecoveryDone)
            cancelPendingScans();
    }
    // Drop author metadata only for threads that no longer belong to the retained inbox.
    function pruneAuthorCaches(currentMessages) {
        let keep = {};
        let source = currentMessages || [];
        for (let index = 0; index < source.length; index++) {
            let threadId = source[index].threadId;
            if (threadId)
                keep[threadId] = true;
        }
        let nextAuthors = {};
        for (let threadId in authorsByThread)
            if (keep[threadId])
                nextAuthors[threadId] = authorsByThread[threadId];
        authorsByThread = nextAuthors;

        let nextFetchedUrls = {};
        for (let threadId in authorWorker.fetchedUrlsByThread)
            if (keep[threadId])
                nextFetchedUrls[threadId] = authorWorker.fetchedUrlsByThread[threadId];
        authorWorker.fetchedUrlsByThread = nextFetchedUrls;

        let nextFetchedAt = {};
        for (let threadId in authorWorker.fetchedAtUpdatedAt)
            if (keep[threadId])
                nextFetchedAt[threadId] = authorWorker.fetchedAtUpdatedAt[threadId];
        authorWorker.fetchedAtUpdatedAt = nextFetchedAt;
        let keepIds = Object.keys(keep);
        cacheCoordinator.pruneToThreads(keepIds);
    }

    // Resolve the selected notification's context before dispatching an explicit author request.
    function requestThreadAuthors(threadId, subjectApiUrl, subjectType) {
        if (!loadAuthorInfo || !authorWorker)
            return;
        let updatedAt = "";
        let resolvedUrl = subjectApiUrl || "";
        let resolvedType = subjectType || "";
        let title = "";
        for (let message of messages) {
            if (!message || message.threadId !== threadId)
                continue;
            updatedAt = message.updatedAt || "";
            title = message.title || "";
            if (!resolvedUrl)
                resolvedUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(message);
            if (!resolvedType)
                resolvedType = message.subjectType || "";
            break;
        }
        authorWorker.enqueueAuthorFetch(threadId, resolvedUrl, resolvedType, updatedAt, false, null, title);
    }
    // Discard staged cache restoration, stop enrichment scans and clear runtime authors.
    function reset() {
        pendingCacheState = null;
        cancelBackgroundEnrichment();
        cancelPendingScans();
        authorsByThread = ({});
    }
    // Start only the deferred enrichment work still relevant to the current messages.
    function runBackgroundEnrichment() {
        if (!tokenAvailable || pendingEnrichmentMessages.length === 0)
            return;
        if (fetchBusy || popoutApplying) {
            backgroundEnrichmentTimer.restart();
            return;
        }
        let items = pendingEnrichmentMessages;
        pendingEnrichmentMessages = [];
        resourceRepository.requestMessageAvatars(items);
        avatarPreloader.queueFromMessages(items);
        if (loadAuthorInfo)
            authorWorker.prefetchForMessages(items);
    }
    // Invalidate stale actor selections while keeping valid cached details available.
    function sanitizeCachedAuthors(messages, resolvedAuthors, fetchedAt) {
        let messagesByThread = {};
        for (let index = 0; index < messages.length; index++) {
            let message = messages[index];
            if (message && message.threadId)
                messagesByThread[message.threadId] = message;
        }
        let changedAuthors = {};
        for (let threadId in resolvedAuthors) {
            let message = messagesByThread[threadId];
            if (!message || !String(message.repositoryOwnerLogin || "").trim())
                continue;
            let authors = resolvedAuthors[threadId] || [];
            let normalizedAuthors = messageState.normalizeCachedAuthorsForMessage(message, authors);
            let changed = normalizedAuthors.length !== authors.length;
            if (authors.length === 0 && authorWorker.fetchedAtMatches(fetchedAt[threadId], message.updatedAt))
                changed = true;
            let ownerLogin = String(message.repositoryOwnerLogin || "").trim().toLowerCase();
            for (let index = 0; index < authors.length; index++) {
                if (String((authors[index] && authors[index].login) || "").trim().toLowerCase() === ownerLogin) {
                    changed = true;
                    break;
                }
            }
            if (!changed)
                continue;
            resolvedAuthors[threadId] = normalizedAuthors;
            fetchedAt[threadId] = "";
            changedAuthors[threadId] = normalizedAuthors;
            cacheCoordinator.updateAuthorFetchedAt(threadId, "");
        }
        if (Object.keys(changedAuthors).length > 0)
            cacheCoordinator.updateChangedAuthors(changedAuthors);
    }
    // Select unresolved messages and delay their enrichment until authentication is available.
    function scheduleBackgroundEnrichment(items) {
        pendingEnrichmentMessages = filterMessagesNeedingEnrichment(items || []);
        if (!tokenAvailable || pendingEnrichmentMessages.length === 0)
            return;
        backgroundEnrichmentTimer.restart();
    }
    // Stage restored messages and author avatars for an authenticated startup scan.
    function scheduleStartupScan(messages, resolvedAuthors) {
        if (!tokenAvailable)
            return;
        let source = messages || [];
        let fetchedAt = {};
        for (let threadId in authorWorker.fetchedAtUpdatedAt)
            fetchedAt[threadId] = authorWorker.fetchedAtUpdatedAt[threadId];
        authorWorker.fetchedAtUpdatedAt = fetchedAt;
        let authorLists = [];
        for (let threadId in resolvedAuthors) {
            let authors = resolvedAuthors[threadId] || [];
            if (authors.length > 0)
                authorLists.push(authors);
        }
        pendingStartupAuthorMessages = source.slice(0);
        pendingStartupAuthorAvatarLists = authorLists;
        pendingStartupAuthorAvatarIndex = 0;
        startupAuthorPrefetchQueued = false;
        if (source.length > 0 || authorLists.length > 0)
            startupMissingInfoTimer.restart();
    }

    Timer {
        id: startupMissingInfoTimer

        interval: GitHubConstants.startupMissingInfoScanIntervalMs
        repeat: true

        onTriggered: service.processStartupBatch()
    }
    Timer {
        id: backgroundEnrichmentTimer

        interval: GitHubConstants.backgroundEnrichmentDelayMs
        repeat: false

        onTriggered: service.runBackgroundEnrichment()
    }
}
