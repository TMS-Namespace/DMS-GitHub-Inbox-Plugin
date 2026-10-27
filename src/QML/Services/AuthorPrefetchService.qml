// AuthorPrefetchService.qml - batches bounded automatic author and subject-detail requests.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: prefetch

    property int _prefetchAcceptedCount: 0
    property var _prefetchQueue: []
    property var _prefetchQueuedThreadIds: ({})
    property var authorWorker: null
    readonly property bool isBusy: _prefetchQueue.length > 0 || prefetchTimer.running
    property bool loadAuthorInfo: true
    property string token: ""

    signal prefetchMaybeComplete

    // Forward performance messages through the shared logger.
    function _perfLog(label) {
        PluginLogger.debug("AuthorBackgroundWorker", label);
    }
    // Turn one prefetch batch into endpoint requests, refreshing URL history when activity changes.
    function _processPrefetchBatch() {
        let profileStart = Date.now();
        if (!loadAuthorInfo || !token) {
            prefetchTimer.stop();
            _prefetchQueue = [];
            _prefetchQueuedThreadIds = ({});
            prefetchMaybeComplete();
            return;
        }

        if (_prefetchQueue.length === 0) {
            prefetchTimer.stop();
            prefetchMaybeComplete();
            profileOperation("_processPrefetchBatch", profileStart, "empty");
            return;
        }

        let batchSize = Math.max(1, GitHubConstants.authorPrefetchBatchSize);
        let queue = _prefetchQueue;
        let nextQueuedIds = _prefetchQueuedThreadIds;
        let processed = 0;

        while (processed < batchSize && processed < queue.length) {
            let item = queue[processed];
            processed++;

            if (item.threadId)
                delete nextQueuedIds[item.threadId];

            let lastFetchedUpdatedAt = authorWorker.fetchedAtUpdatedAt[item.threadId] || "";
            let forceFetch = !!item.force;
            let includeDetails = !!item.includeDetails;
            if (!forceFetch && !includeDetails && authorWorker.fetchedAtMatches(lastFetchedUpdatedAt, item.updatedAt))
                continue;

            // Message updated since last fetch: clear URL-level state once,
            // then let the normal URL filter avoid duplicate subrequests.
            if ((forceFetch || lastFetchedUpdatedAt !== "") && authorWorker.fetchedUrlsByThread.hasOwnProperty(item.threadId)) {
                delete authorWorker.fetchedUrlsByThread[item.threadId];
            }

            authorWorker.enqueueAuthorUrls(item.threadId, AuthorUtils.buildAuthorFetchUrls(item.subjectApiUrl, item.subjectType || "", includeDetails, item.reason || ""), item.updatedAt || "", true, item.fallbackAuthor || null, item.subjectTitle || "", item.subjectType || "", item.reason || "");
        }

        _prefetchQueue = queue.slice(processed);
        _prefetchQueuedThreadIds = nextQueuedIds;

        if (_prefetchQueue.length === 0) {
            prefetchTimer.stop();
            prefetchMaybeComplete();
        }
        profileOperation("_processPrefetchBatch", profileStart, "processed=" + processed + " remaining=" + _prefetchQueue.length);
    }

    // Queue missing or stale subject details within the automatic per-refresh message budget.
    function prefetchForMessages(items) {
        let profileStart = Date.now();
        _perfLog("prefetchForMessages --- items=" + (items ? items.length : 0));
        if (!GitHubConstants.automaticAuthorPrefetchEnabled)
            return;
        if (!loadAuthorInfo || !token || !items || items.length === 0)
            return;
        let nextQueue = _prefetchQueue.slice(0);
        let nextQueuedIds = _prefetchQueuedThreadIds;
        let accepted = _prefetchAcceptedCount;
        let enqueued = 0;

        for (let index = 0; index < items.length; index++) {
            if (accepted >= GitHubConstants.maxAuthorPrefetchMessagesPerRefresh)
                break;
            let item = items[index];
            if (!item || !item.threadId)
                continue;
            let needsSubjectWebUrl = authorWorker.requiresSubjectWebUrlResolution(item);
            let needsSubjectReference = authorWorker.requiresSubjectReferenceResolution(item);
            let needsAuthorDetails = authorWorker.shouldFetchAuthorDetailsForMessage(item) && !authorWorker.hasFetchedAuthorDetailsForMessage(item);
            let existingAuthors = (authorWorker.authorsByThreadRef || ({}))[item.threadId] || [];
            let needsMissingAuthors = existingAuthors.length === 0;
            if (!needsSubjectWebUrl && !needsSubjectReference && !needsAuthorDetails && !needsMissingAuthors && authorWorker.fetchedAtMatches(authorWorker.fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue;
            let subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item);
            if (!subjectApiUrl)
                continue;
            if (nextQueuedIds[item.threadId])
                continue;
            if (authorWorker.hasQueuedOrActiveThreadRequest(item.threadId))
                continue;
            nextQueuedIds[item.threadId] = true;
            nextQueue.push({
                threadId: item.threadId,
                subjectApiUrl: subjectApiUrl,
                subjectType: item.subjectType || "",
                updatedAt: item.updatedAt || "",
                subjectTitle: item.title || "",
                includeDetails: authorWorker.shouldFetchAuthorDetailsForMessage(item),
                force: needsSubjectWebUrl || needsSubjectReference,
                fallbackAuthor: authorWorker.fallbackAuthorForMessage(item),
                reason: item.reason || ""
            });
            accepted++;
            enqueued++;
        }

        if (enqueued > 0) {
            _prefetchQueue = nextQueue;
            _prefetchQueuedThreadIds = nextQueuedIds;
            _prefetchAcceptedCount = accepted;
            if (!prefetchTimer.running)
                prefetchTimer.restart();
        }
        _perfLog("prefetchForMessages --- enqueued=" + enqueued);
        profileOperation("prefetchForMessages", profileStart, "items=" + (items ? items.length : 0) + " enqueued=" + enqueued);
    }

    // Queue unresolved details after cache restoration without duplicating queued or active threads.
    function prefetchMissingForMessages(items, authorsByThread) {
        let profileStart = Date.now();
        _perfLog("prefetchMissingForMessages --- items=" + (items ? items.length : 0));
        if (!GitHubConstants.automaticAuthorPrefetchEnabled)
            return;
        if (!loadAuthorInfo || !token || !items || items.length === 0)
            return;
        let knownAuthors = authorsByThread || ({});
        let nextQueue = _prefetchQueue.slice(0);
        let nextQueuedIds = _prefetchQueuedThreadIds;
        let enqueued = 0;

        for (let index = 0; index < items.length; index++) {
            let item = items[index];
            if (!item || !item.threadId)
                continue;
            let needsSubjectWebUrl = authorWorker.requiresSubjectWebUrlResolution(item);
            let needsSubjectReference = authorWorker.requiresSubjectReferenceResolution(item);
            let needsAuthorDetails = authorWorker.shouldFetchAuthorDetailsForMessage(item) && !authorWorker.hasFetchedAuthorDetailsForMessage(item);
            let existingAuthors = knownAuthors[item.threadId] || [];
            let needsMissingAuthors = existingAuthors.length === 0;
            if (!needsSubjectWebUrl && !needsSubjectReference && !needsAuthorDetails && !needsMissingAuthors && authorWorker.fetchedAtMatches(authorWorker.fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue;
            if (!needsSubjectWebUrl && !needsSubjectReference && !needsAuthorDetails && existingAuthors.length > 0 && authorWorker.fetchedAtMatches(authorWorker.fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue;
            let subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item);
            if (!subjectApiUrl)
                continue;
            if (nextQueuedIds[item.threadId])
                continue;
            if (authorWorker.hasQueuedOrActiveThreadRequest(item.threadId))
                continue;
            nextQueuedIds[item.threadId] = true;
            nextQueue.push({
                threadId: item.threadId,
                subjectApiUrl: subjectApiUrl,
                subjectType: item.subjectType || "",
                updatedAt: item.updatedAt || "",
                subjectTitle: item.title || "",
                includeDetails: authorWorker.shouldFetchAuthorDetailsForMessage(item),
                force: needsSubjectWebUrl || needsSubjectReference,
                fallbackAuthor: authorWorker.fallbackAuthorForMessage(item),
                reason: item.reason || ""
            });
            enqueued++;
        }

        if (enqueued > 0) {
            _prefetchQueue = nextQueue;
            _prefetchQueuedThreadIds = nextQueuedIds;
            if (!prefetchTimer.running)
                prefetchTimer.restart();
        }
        _perfLog("prefetchMissingForMessages --- enqueued=" + enqueued);
        profileOperation("prefetchMissingForMessages", profileStart, "items=" + (items ? items.length : 0) + " enqueued=" + enqueued);
    }
    // Measure prefetch work through the shared profiling gate.
    function profileOperation(label, startMs, details) {
        PluginLogger.profile("AuthorBackgroundWorker", label, Date.now() - startMs, details);
    }

    // Stop the timer and discard staged requests and their per-refresh budget.
    function reset() {
        prefetchTimer.stop();
        _prefetchQueue = [];
        _prefetchQueuedThreadIds = ({});
        _prefetchAcceptedCount = 0;
    }

    visible: false

    Timer {
        id: prefetchTimer

        interval: GitHubConstants.authorPrefetchBatchIntervalMs
        repeat: true

        onTriggered: prefetch._processPrefetchBatch()
    }
}
