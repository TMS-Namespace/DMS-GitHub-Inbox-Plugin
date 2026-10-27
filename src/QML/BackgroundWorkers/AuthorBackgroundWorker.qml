// AuthorBackgroundWorker.qml - Manages author data fetching and queue processing
//
// Handles URL-level deduplication, queue management, curl-based fetching,
// and offloading JSON parsing to a WorkerScript (via InboxBackgroundWorker).
// Dux v2's dms dl accepts headers only through argv, not stdin or a header file.
// Both authenticated fetch builders retain curl -H @- to keep tokens out of process arguments.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: authorFetcher

    property var activeUrlsByThread: ({})
    property string authorSplitToken: GitHubConstants.authorPayloadSplitToken

    // Reference to the current authorsByThread from Widget for merge base
    property var authorsByThreadRef: ({})
    property var fetchedAtUpdatedAt: ({})
    property var fetchedUrlsByThread: ({})
    readonly property bool isBusy: requestsInFlight > 0 || requestQueue.length > 0 || authorPrefetch.isBusy || authorMerges.isBusy
    property bool loadAuthorInfo: true
    property bool prefetchPending: false
    readonly property var providerApi: GitHubManager.getProviderApi(GitHubManager.providerTypes[0])
    property int requestGeneration: 0

    // -- State ----------------------------------------------------------------
    property var requestQueue: []
    property int requestsInFlight: 0

    // -- Configuration --------------------------------------------------------
    property string token: ""

    // -- External dependency: inbox worker provides sendWorkerMessage() --------
    property var workerSendMessage: null   // bind to inboxBackgroundWorker.sendWorkerMessage

    /// Emitted per-thread when authorFetchedAtUpdatedAt is updated.
    signal authorFetchedAtChanged(string threadId, string updatedAt)

    // -- Signals --------------------------------------------------------------

    /// Emitted once per tick with the full merged authorsByThread snapshot,
    /// accumulated avatar-preload authors, and the IDs of changed threads.
    signal authorsMerged(var authorsByThread, var preloadAuthors, var changedThreadIds)

    /// Emitted when expansion URLs are discovered and need enqueueing.
    signal expansionUrlsDiscovered(string threadId, var urls)

    /// Emitted when the prefetch cycle may have completed.
    signal prefetchMaybeComplete

    /// Emitted when a fetched subject is matched to its concrete web URL.
    signal subjectWebUrlResolved(string threadId, string webUrl, string subjectReference)

    // Copy a thread's URL set before changing its reactive queue membership.
    function _cloneThreadActiveUrlMap(threadId) {
        let source = activeUrlsByThread[threadId] || {};
        let copy = {};
        for (let url in source)
            copy[url] = source[url];
        return copy;
    }
    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        PluginLogger.debug("AuthorBackgroundWorker", label);
    }
    // Measure this operation through the shared profiling gate.
    function _profile(label, startMs, details) {
        profileOperation(label, startMs, details);
    }
    // Build the automatic fetch command using the shared request service.
    function buildAutomaticAuthorExtractCommand(urls) {
        return authorRequests.buildAutomaticAuthorExtractCommand(urls);
    }
    // Build the explicit fetch command using the shared request service.
    function buildRawAuthorFetchCommand(urls) {
        return authorRequests.buildRawAuthorFetchCommand(urls);
    }
    // Cancel author work and clear both completed endpoint history and activity markers.
    function clearAllState() {
        resetState();
        fetchedUrlsByThread = ({});
        activeUrlsByThread = ({});
        fetchedAtUpdatedAt = ({});
    }
    // Include pending merge batches when the cache requests the current author snapshot.
    function cloneAuthorsByThread(authorsByThread) {
        return authorMerges.cloneAuthorsByThread(authorsByThread);
    }

    // Plan subject endpoints and enqueue them when author loading and authentication are available.
    function enqueueAuthorFetch(threadId, subjectApiUrl, subjectType, updatedAt, automaticPrefetch, fallbackAuthor, subjectTitle) {
        if (!loadAuthorInfo || !token || !threadId || !subjectApiUrl || typeof subjectApiUrl !== 'string')
            return;
        enqueueAuthorUrls(threadId, AuthorUtils.buildAuthorFetchUrls(subjectApiUrl, subjectType || "", !automaticPrefetch, ""), updatedAt || "", !!automaticPrefetch, fallbackAuthor || null, subjectTitle || "", subjectType || "", "");
    }
    // Deduplicate endpoint requests per thread, cap automatic work and prioritize explicit requests.
    function enqueueAuthorUrls(threadId, urls, updatedAt, automaticPrefetch, fallbackAuthor, subjectTitle, subjectType, reason) {
        let profileStart = Date.now();
        if (!token || !threadId || !urls || urls.length === 0)
            return;
        let candidateUrls = filterThreadUnfetchedUrls(threadId, urls);
        if (candidateUrls.length === 0)
            return;
        let pendingMap = _cloneThreadActiveUrlMap(threadId);
        let nextQueue = requestQueue.slice(0);

        for (let queueIndex = 0; queueIndex < nextQueue.length; queueIndex++) {
            let queueItem = nextQueue[queueIndex];
            if (queueItem.threadId !== threadId)
                continue;
            let pendingUrls = queueItem.urls || [];
            for (let pendingIndex = 0; pendingIndex < pendingUrls.length; pendingIndex++) {
                let pendingKey = AuthorUtils.normalizeApiUrl(pendingUrls[pendingIndex]);
                if (pendingKey)
                    pendingMap[pendingKey] = true;
            }
        }

        let filtered = [];
        for (let index = 0; index < candidateUrls.length; index++) {
            let url = candidateUrls[index];
            let urlKey = AuthorUtils.normalizeApiUrl(url);
            if (!urlKey || pendingMap[urlKey])
                continue;
            pendingMap[urlKey] = true;
            filtered.push(url);
        }

        if (filtered.length === 0)
            return;
        if (filtered.length > GitHubConstants.maxAuthorUrlsPerThreadFetch)
            filtered = filtered.slice(0, GitHubConstants.maxAuthorUrlsPerThreadFetch);

        let request = {
            threadId: threadId,
            urls: filtered,
            updatedAt: updatedAt || "",
            automaticPrefetch: !!automaticPrefetch,
            fallbackAuthor: fallbackAuthor || null,
            subjectTitle: subjectTitle || "",
            subjectType: subjectType || "",
            reason: reason || ""
        };

        if (automaticPrefetch && nextQueue.length >= GitHubConstants.maxAuthorRequestQueueLength)
            return;
        if (automaticPrefetch)
            nextQueue.push(request);
        else
            nextQueue.unshift(request);

        requestQueue = nextQueue;
        profileOperation("enqueueAuthorUrls", profileStart, "thread=" + threadId + " urls=" + filtered.length + " queue=" + requestQueue.length);
        processQueue();
    }
    // Do not guess authors from notification hints; resolve them from subject or workflow details.
    function fallbackAuthorForMessage(item) {
        return null;
    }
    // Compare saved fetch markers with the notification activity being resolved.
    function fetchedAtMatches(cachedValue, updatedAt) {
        return String(cachedValue || "") === fetchedAtValue(updatedAt);
    }
    // Prefix nonempty activity timestamps with the author-cache policy version; missing time stays empty.
    function fetchedAtValue(updatedAt) {
        let value = String(updatedAt || "");
        return value ? ("authors-v4:" + value) : "";
    }
    // Exclude GitHub Actions automation from issue and pull-request participant lists.
    function filterAuthorsForSubject(normalizedType, authors) {
        let source = authors || [];
        if (normalizedType !== "pullrequest" && normalizedType !== "issue")
            return source;

        let filtered = [];
        for (let index = 0; index < source.length; index++) {
            let author = source[index] || ({});
            let login = String(author.login || "").trim().toLowerCase();
            let htmlUrl = String(author.htmlUrl || author.html_url || "").trim().toLowerCase();
            if (login === "github-actions" || login === "github-actions[bot]" || htmlUrl === GitHubConstants.githubWebBaseUrl + "/apps/github-actions")
                continue;
            filtered.push(author);
        }
        return filtered;
    }
    // Keep valid endpoints that are neither fetched, active nor repeated in this request.
    function filterThreadUnfetchedUrls(threadId, urls) {
        let result = [];
        if (!threadId || !urls || urls.length === 0)
            return result;

        let fetchedMap = fetchedUrlsByThread[threadId] || {};
        let activeMap = activeUrlsByThread[threadId] || {};
        let seen = {};

        for (let index = 0; index < urls.length; index++) {
            let rawUrl = String(urls[index] || "").trim();
            let normalized = AuthorUtils.normalizeApiUrl(rawUrl);
            if (!normalized || fetchedMap[normalized] || activeMap[normalized] || seen[normalized])
                continue;
            seen[normalized] = true;
            result.push(rawUrl);
        }

        return result;
    }

    // =========================================================================
    //  AUTHOR RESULT HANDLING (called from InboxBackgroundWorker signal)
    // =========================================================================

    // Merge only results from the current generation and release their in-flight slot.
    function handleAuthorResult(message) {
        if (message.generation !== requestGeneration)
            return;
        let threadId = message.threadId || "";
        let updatedAt = message.updatedAt || "";
        let fetchedAuthors = message.authors || [];
        let fallbackAuthor = message.fallbackAuthor || null;
        if (fetchedAuthors.length === 0 && fallbackAuthor)
            fetchedAuthors = [fallbackAuthor];
        fetchedAuthors = normalizeAuthorsForSubject(message.subjectType || "", message.reason || "", fetchedAuthors);
        authorMerges.stage(threadId, fetchedAuthors, !!message.automaticPrefetch);

        if (threadId) {
            let fetchedMarker = fetchedAtValue(updatedAt);
            fetchedAtUpdatedAt[threadId] = fetchedMarker;
            authorFetchedAtChanged(threadId, fetchedMarker);
        }

        if (message.shouldExpand) {
            let expansionRoots = message.expansionUrls || [];
            if (expansionRoots.length > 0) {
                let expansionUrls = [];
                for (let expIdx = 0; expIdx < expansionRoots.length; expIdx++) {
                    let builtUrls = AuthorUtils.buildAuthorFetchUrls(expansionRoots[expIdx], "");
                    for (let urlIdx = 0; urlIdx < builtUrls.length; urlIdx++)
                        expansionUrls.push(builtUrls[urlIdx]);
                }
                expansionUrlsDiscovered(threadId, expansionUrls);
            }
        }

        if ((message.subjectWebUrl || message.subjectReference) && threadId)
            subjectWebUrlResolved(threadId, message.subjectWebUrl || "", message.subjectReference || "");

        authorMerges.schedule();

        requestsInFlight = Math.max(0, requestsInFlight - 1);
        prefetchMaybeComplete();
        Qt.callLater(processQueue);
    }
    // Release a completed request and pass successful response text to the parser worker.
    function handleRequestFinished(request, generation, exitCode, buffer, bufferBytes, startedAt) {
        if (generation !== requestGeneration)
            return;
        let threadId = request.threadId || "";
        let requestedUrls = request.urls || [];
        markThreadUrlsInactive(threadId, requestedUrls);

        if (!loadAuthorInfo || exitCode !== 0 || !workerSendMessage) {
            if (loadAuthorInfo && exitCode !== 0)
                PluginLogger.error("author", "GitHub author request failed with exit code " + exitCode);
            requestsInFlight = Math.max(0, requestsInFlight - 1);
            prefetchMaybeComplete();
            Qt.callLater(processQueue);
            return;
        }

        markThreadUrlsFetched(threadId, requestedUrls);
        workerSendMessage({
            action: "parseAuthors",
            generation: generation,
            threadId: threadId,
            updatedAt: request.updatedAt || "",
            requestedUrls: requestedUrls,
            automaticPrefetch: !!request.automaticPrefetch,
            subjectType: request.subjectType || "",
            reason: request.reason || "",
            shouldExpand: !request.automaticPrefetch && shouldExpandFromRequestedUrls(requestedUrls),
            fallbackAuthor: request.fallbackAuthor || null,
            subjectTitle: request.subjectTitle || "",
            buffer: buffer,
            splitToken: authorSplitToken
        });
        profileOperation("authorFetchProcess", startedAt, "thread=" + threadId + " bytes=" + bufferBytes + " urls=" + requestedUrls.length + " automatic=" + !!request.automaticPrefetch);
    }
    // Treat optional detail endpoints as covered when each has been fetched or is already active.
    function hasFetchedAuthorDetailsForMessage(item) {
        if (!item || !item.threadId || !shouldFetchAuthorDetailsForMessage(item))
            return true;

        let subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item);
        let urls = AuthorUtils.buildAuthorFetchUrls(subjectApiUrl, item.subjectType || "", true, item.reason || "");
        if (urls.length <= 1)
            return true;

        let fetchedMap = fetchedUrlsByThread[item.threadId] || {};
        let activeMap = activeUrlsByThread[item.threadId] || {};
        for (let index = 1; index < urls.length; index++) {
            let normalized = AuthorUtils.normalizeApiUrl(urls[index]);
            if (normalized && !fetchedMap[normalized] && !activeMap[normalized])
                return false;
        }

        return true;
    }
    // Include delayed prefetch batches and unpublished author merges in the pending-work check.
    function hasPendingPrefetchWork() {
        return authorPrefetch.isBusy || authorMerges.isBusy;
    }
    // Check both active endpoint membership and queued requests for this thread.
    function hasQueuedOrActiveThreadRequest(threadId) {
        if (!threadId)
            return false;

        let activeMap = activeUrlsByThread[threadId] || {};
        for (let activeUrl in activeMap)
            return true;

        for (let index = 0; index < requestQueue.length; index++) {
            if (requestQueue[index].threadId === threadId)
                return true;
        }

        return false;
    }
    // Recognize check-suite, check-run and workflow-run subjects case-insensitively.
    function isCiSubjectType(subjectType) {
        let normalizedType = String(subjectType || "").toLowerCase();
        return normalizedType === "checksuite" || normalizedType === "checkrun" || normalizedType === "workflowrun";
    }
    // Reserve normalized endpoints while a thread's author fetch is active.
    function markThreadUrlsActive(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return;
        let nextThreadMap = activeUrlsByThread[threadId] || {};

        for (let index = 0; index < urls.length; index++) {
            let url = AuthorUtils.normalizeApiUrl(urls[index]);
            if (url)
                nextThreadMap[url] = true;
        }

        activeUrlsByThread[threadId] = nextThreadMap;
    }
    // Record completed endpoints so subsequent requests can skip them.
    function markThreadUrlsFetched(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return;
        let nextThreadMap = fetchedUrlsByThread[threadId] || {};

        for (let index = 0; index < urls.length; index++) {
            let url = AuthorUtils.normalizeApiUrl(urls[index]);
            if (url)
                nextThreadMap[url] = true;
        }

        fetchedUrlsByThread[threadId] = nextThreadMap;
    }
    // Release a thread's completed or failed endpoint reservations and remove empty entries.
    function markThreadUrlsInactive(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return;
        let nextThreadMap = activeUrlsByThread[threadId] || {};
        let changed = false;

        for (let index = 0; index < urls.length; index++) {
            let url = AuthorUtils.normalizeApiUrl(urls[index]);
            if (url && nextThreadMap.hasOwnProperty(url)) {
                delete nextThreadMap[url];
                changed = true;
            }
        }

        if (!changed)
            return;
        let hasRemaining = false;
        for (let activeUrl in nextThreadMap) {
            hasRemaining = true;
            break;
        }

        if (hasRemaining)
            activeUrlsByThread[threadId] = nextThreadMap;
        else
            delete activeUrlsByThread[threadId];
    }
    // Filter automation, keep one CI actor and cap comment/PR-author lists at the display limit.
    function normalizeAuthorsForSubject(subjectType, reason, authors) {
        let source = authors || [];
        let normalizedType = String(subjectType || "").toLowerCase();
        let normalizedReason = String(reason || "").toLowerCase();
        let filtered = filterAuthorsForSubject(normalizedType, source);

        if (isCiSubjectType(subjectType) && filtered.length > 1)
            return filtered.slice(0, 1);

        if ((normalizedType === "pullrequest" || normalizedType === "issue") && normalizedReason === "comment" && filtered.length > GitHubConstants.maxAuthorsDisplayedPerMessage)
            return filtered.slice(0, GitHubConstants.maxAuthorsDisplayedPerMessage);

        if (normalizedType === "pullrequest" && normalizedReason === "author" && filtered.length > GitHubConstants.maxAuthorsDisplayedPerMessage)
            return filtered.slice(0, GitHubConstants.maxAuthorsDisplayedPerMessage);

        return filtered;
    }
    // Schedule missing details for messages received during a refresh.
    function prefetchForMessages(items) {
        authorPrefetch.prefetchForMessages(items);
    }
    // Schedule missing details after cached author state is restored.
    function prefetchMissingForMessages(items, authorsByThread) {
        authorPrefetch.prefetchMissingForMessages(items, authorsByThread);
    }
    // =========================================================================
    //  INTERNAL
    // =========================================================================

    // Start work only while concurrency slots remain; obsolete callers are discarded first.
    function processQueue() {
        let profileStart = Date.now();
        let startedRequests = 0;
        if (!token || !loadAuthorInfo)
            return;
        let queue = requestQueue;
        let queueOffset = 0;
        while (requestsInFlight < GitHubConstants.maxConcurrentAuthorFetches && queueOffset < queue.length) {
            _perfLog("processQueue --- queueLen=" + requestQueue.length + " inFlight=" + requestsInFlight);

            let request = queue[queueOffset];
            queueOffset++;

            let urls = filterThreadUnfetchedUrls(request.threadId, request.urls || []);
            if (urls.length === 0)
                continue;
            markThreadUrlsActive(request.threadId, urls);
            requestsInFlight++;
            startedRequests++;
            let fetchRequest = Object.assign({}, request, {
                urls: urls
            });
            authorRequests.startRequest(fetchRequest, requestGeneration, token);

            ApiCallStats.recordCalls(urls.length);
        }
        if (queueOffset > 0)
            requestQueue = queue.slice(queueOffset);
        profileOperation("processQueue", profileStart, "started=" + startedRequests + " inFlight=" + requestsInFlight + " queue=" + requestQueue.length);
    }
    // Apply the common profiling policy rather than checking development flags locally.
    function profileOperation(label, startMs, details) {
        let duration = Date.now() - startMs;
        PluginLogger.profile("AuthorBackgroundWorker", label, duration, details);
    }
    // Use the message's repository URL, falling back to a URL built from its repository name.
    function repositoryWebUrlForMessage(item) {
        let repoUrl = String((item && item.repositoryUrl) || "").trim();
        if (repoUrl)
            return repoUrl;

        let repo = String((item && item.repository) || "").trim();
        return repo ? (GitHubConstants.githubWebBaseUrl + "/" + repo) : "";
    }
    // Fetch workflow details when a CI subject has no displayable run number.
    function requiresSubjectReferenceResolution(item) {
        if (!item)
            return false;

        let subjectType = String(item.subjectType || "").toLowerCase();
        if (subjectType !== "checksuite" && subjectType !== "checkrun" && subjectType !== "workflowrun")
            return false;

        return String(item.subjectReference || "").trim() === "";
    }
    // Resolve generic CI links and release links that have not yet been confirmed by the API.
    function requiresSubjectWebUrlResolution(item) {
        if (!item)
            return false;

        let subjectType = String(item.subjectType || "").toLowerCase();
        let reason = String(item.reason || "").toLowerCase();
        let rawUrl = String(item.webUrl || "").trim();
        let repoUrl = repositoryWebUrlForMessage(item);
        let subjectApiUrl = String(item.subjectApiUrl || "").trim();

        if (reason === "ci_activity" || subjectType === "checksuite" || subjectType === "checkrun" || subjectType === "workflowrun") {
            return !rawUrl || rawUrl === repoUrl || rawUrl === repoUrl + "/actions" || rawUrl.indexOf(GitHubConstants.githubWebBaseUrl + "/notifications/threads/") === 0;
        }

        if (subjectType === "release" && /\/releases\/[0-9]+$/.test(subjectApiUrl)) {
            if (!rawUrl || rawUrl === repoUrl || rawUrl === repoUrl + "/releases")
                return true;

            // Older cache entries guessed the tag from the notification title.
            // Numeric release API subjects need one enrichment fetch to get the
            // authoritative html_url, including suffixes like -rc15.
            if (rawUrl.indexOf("/releases/tag/") >= 0 && !item.webUrlResolved)
                return true;
        }

        return false;
    }
    // Invalidate in-flight results and clear pending requests, prefetch batches and unpublished merges.
    function resetState() {
        requestGeneration = requestGeneration + 1;
        authorPrefetch.reset();
        authorMerges.reset();
        requestQueue = [];
        requestsInFlight = 0;
        activeUrlsByThread = ({});
        prefetchPending = false;
    }
    // Expand comment or detail responses that may refer back to a parent issue or pull request.
    function shouldExpandFromRequestedUrls(urls) {
        if (!urls || urls.length === 0)
            return false;

        for (let index = 0; index < urls.length; index++) {
            let normalized = AuthorUtils.normalizeApiUrl(urls[index]);
            if (!normalized)
                continue;
            if (!AuthorUtils.isThreadParentApiUrl(normalized))
                return true;
        }

        return false;
    }
    // Request participant detail endpoints only for issue or pull-request root subjects.
    function shouldFetchAuthorDetailsForMessage(item) {
        if (!item)
            return false;

        let subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item);
        if (!subjectApiUrl)
            return false;

        return AuthorUtils.isThreadParentApiUrl(subjectApiUrl);
    }

    visible: false

    AuthorPrefetchService {
        id: authorPrefetch

        authorWorker: authorFetcher
        loadAuthorInfo: authorFetcher.loadAuthorInfo
        token: authorFetcher.token

        onPrefetchMaybeComplete: authorFetcher.prefetchMaybeComplete()
    }
    AuthorMergeService {
        id: authorMerges

        authorsByThread: authorFetcher.authorsByThreadRef

        onMerged: (authorsByThread, preloadAuthors, changedThreadIds) => authorFetcher.authorsMerged(authorsByThread, preloadAuthors, changedThreadIds)
    }
    AuthorRequestService {
        id: authorRequests

        authorSplitToken: authorFetcher.authorSplitToken
        providerApi: authorFetcher.providerApi

        onFinished: (request, generation, exitCode, buffer, bufferBytes, startedAt) => authorFetcher.handleRequestFinished(request, generation, exitCode, buffer, bufferBytes, startedAt)
    }
}
