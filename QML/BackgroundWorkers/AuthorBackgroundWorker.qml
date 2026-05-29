// AuthorBackgroundWorker.qml - Manages author data fetching and queue processing
//
// Handles URL-level deduplication, queue management, curl-based fetching,
// and offloading JSON parsing to a WorkerScript (via InboxBackgroundWorker).

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: authorFetcher
    visible: false

    // -- Configuration --------------------------------------------------------
    property string token: ""
    property bool loadAuthorInfo: true
    property string authorSplitToken: GitHubConstants.authorPayloadSplitToken

    // -- External dependency: inbox worker provides sendWorkerMessage() --------
    property var workerSendMessage: null   // bind to inboxBackgroundWorker.sendWorkerMessage

    // -- State ----------------------------------------------------------------
    property var requestQueue: []
    property int requestsInFlight: 0
    property var fetchedUrlsByThread: ({})
    property var activeUrlsByThread: ({})
    property var fetchedAtUpdatedAt: ({})
    property bool prefetchPending: false
    property int requestGeneration: 0

    // Deferred merge batching
    property var _pendingMerges: ({})
    property bool _mergeFlushQueued: false
    property var _pendingAvatarPreloadAuthors: []
    property var _prefetchQueue: []
    property var _prefetchQueuedThreadIds: ({})
    property int _prefetchAcceptedCount: 0

    readonly property bool isBusy: requestsInFlight > 0
                                   || requestQueue.length > 0
                                   || _prefetchQueue.length > 0
                                   || prefetchTimer.running
                                   || _mergeFlushQueued
                                   || mergeFlushTimer.running

    // -- Signals --------------------------------------------------------------

    /// Emitted once per tick with the full merged authorsByThread snapshot,
    /// accumulated avatar-preload authors, and the IDs of changed threads.
    signal authorsMerged(var authorsByThread, var preloadAuthors, var changedThreadIds)

    /// Emitted per-thread when authorFetchedAtUpdatedAt is updated.
    signal authorFetchedAtChanged(string threadId, string updatedAt)

    /// Emitted when expansion URLs are discovered and need enqueueing.
    signal expansionUrlsDiscovered(string threadId, var urls)

    /// Emitted when a fetched subject is matched to its concrete web URL.
    signal subjectWebUrlResolved(string threadId, string webUrl, string subjectReference)

    /// Emitted when the prefetch cycle may have completed.
    signal prefetchMaybeComplete()

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        if (!GitHubConstants.debugPerformanceLogging) return
        console.warn("[GitHubInbox PERF] AuthorBackgroundWorker: " + label)
    }

    function profileOperation(label, startMs, details) {
        if (!GitHubConstants.profileLoggingEnabled)
            return
        var duration = Date.now() - startMs
        if (!GitHubConstants.profileLogAllOperations
                && duration < GitHubConstants.profileSlowOperationThresholdMs)
            return
        var suffix = details ? (" — " + details) : ""
        console.warn("[GitHubInbox PROFILE] AuthorBackgroundWorker." + label
                     + " took " + duration + "ms" + suffix)
    }

    function _profile(label, startMs, details) {
        profileOperation(label, startMs, details)
    }

    function fetchedAtValue(updatedAt) {
        var value = String(updatedAt || "")
        return value ? ("authors-v3:" + value) : ""
    }

    function fetchedAtMatches(cachedValue, updatedAt) {
        return String(cachedValue || "") === fetchedAtValue(updatedAt)
    }

    Timer {
        id: prefetchTimer
        interval: GitHubConstants.authorPrefetchBatchIntervalMs
        repeat: true
        onTriggered: authorFetcher._processPrefetchBatch()
    }

    Timer {
        id: mergeFlushTimer
        interval: GitHubConstants.authorMergeFlushIntervalMs
        repeat: false
        onTriggered: authorFetcher._flushMerges()
    }

    function enqueueAuthorFetch(threadId, subjectApiUrl, subjectType, updatedAt, automaticPrefetch, fallbackAuthor, subjectTitle) {
        if (!loadAuthorInfo || !token || !threadId || !subjectApiUrl || typeof subjectApiUrl !== 'string')
            return

        enqueueAuthorUrls(threadId,
            AuthorUtils.buildAuthorFetchUrls(subjectApiUrl, subjectType || "", !automaticPrefetch, ""),
            updatedAt || "",
            !!automaticPrefetch,
            fallbackAuthor || null,
            subjectTitle || "",
            subjectType || "",
            "")
    }

    function enqueueAuthorUrls(threadId, urls, updatedAt, automaticPrefetch, fallbackAuthor, subjectTitle, subjectType, reason) {
        var profileStart = Date.now()
        if (!token || !threadId || !urls || urls.length === 0)
            return

        var candidateUrls = filterThreadUnfetchedUrls(threadId, urls)
        if (candidateUrls.length === 0)
            return

        var pendingMap = _cloneThreadActiveUrlMap(threadId)
        var nextQueue = requestQueue.slice(0)

        for (var queueIndex = 0; queueIndex < nextQueue.length; queueIndex++) {
            var queueItem = nextQueue[queueIndex]
            if (queueItem.threadId !== threadId)
                continue
            var pendingUrls = queueItem.urls || []
            for (var pendingIndex = 0; pendingIndex < pendingUrls.length; pendingIndex++) {
                var pendingKey = AuthorUtils.normalizeApiUrl(pendingUrls[pendingIndex])
                if (pendingKey)
                    pendingMap[pendingKey] = true
            }
        }

        var filtered = []
        for (var index = 0; index < candidateUrls.length; index++) {
            var url = candidateUrls[index]
            var urlKey = AuthorUtils.normalizeApiUrl(url)
            if (!urlKey || pendingMap[urlKey])
                continue
            pendingMap[urlKey] = true
            filtered.push(url)
        }

        if (filtered.length === 0)
            return

        if (filtered.length > GitHubConstants.maxAuthorUrlsPerThreadFetch)
            filtered = filtered.slice(0, GitHubConstants.maxAuthorUrlsPerThreadFetch)

        var request = {
            threadId: threadId,
            urls: filtered,
            updatedAt: updatedAt || "",
            automaticPrefetch: !!automaticPrefetch,
            fallbackAuthor: fallbackAuthor || null,
            subjectTitle: subjectTitle || "",
            subjectType: subjectType || "",
            reason: reason || ""
        }

        if (automaticPrefetch && nextQueue.length >= GitHubConstants.maxAuthorRequestQueueLength)
            return

        if (automaticPrefetch)
            nextQueue.push(request)
        else
            nextQueue.unshift(request)

        requestQueue = nextQueue
        profileOperation("enqueueAuthorUrls", profileStart,
                 "thread=" + threadId + " urls=" + filtered.length + " queue=" + requestQueue.length)
        processQueue()
    }

    function prefetchForMessages(items) {
        var profileStart = Date.now()
        _perfLog("prefetchForMessages — items=" + (items ? items.length : 0))
        if (!GitHubConstants.automaticAuthorPrefetchEnabled)
            return

        if (!loadAuthorInfo || !token || !items || items.length === 0)
            return

        var nextQueue = _prefetchQueue.slice(0)
        var nextQueuedIds = _prefetchQueuedThreadIds
        var accepted = _prefetchAcceptedCount
        var enqueued = 0

        for (var index = 0; index < items.length; index++) {
            if (accepted >= GitHubConstants.maxAuthorPrefetchMessagesPerRefresh)
                break

            var item = items[index]
            if (!item || !item.threadId)
                continue

            var needsSubjectWebUrl = requiresSubjectWebUrlResolution(item)
            var needsSubjectReference = requiresSubjectReferenceResolution(item)
            var needsAuthorDetails = shouldFetchAuthorDetailsForMessage(item)
                                      && !hasFetchedAuthorDetailsForMessage(item)
            var existingAuthors = (authorsByThreadRef || ({}))[item.threadId] || []
            var needsMissingAuthors = existingAuthors.length === 0
            if (!needsSubjectWebUrl
                    && !needsSubjectReference
                    && !needsAuthorDetails
                    && !needsMissingAuthors
                    && fetchedAtMatches(fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue

            var subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item)
            if (!subjectApiUrl)
                continue

            if (nextQueuedIds[item.threadId])
                continue
            if (hasQueuedOrActiveThreadRequest(item.threadId))
                continue

            nextQueuedIds[item.threadId] = true
            nextQueue.push({
                threadId: item.threadId,
                subjectApiUrl: subjectApiUrl,
                subjectType: item.subjectType || "",
                updatedAt: item.updatedAt || "",
                subjectTitle: item.title || "",
                includeDetails: shouldFetchAuthorDetailsForMessage(item),
                force: needsSubjectWebUrl || needsSubjectReference,
                fallbackAuthor: fallbackAuthorForMessage(item),
                reason: item.reason || ""
            })
            accepted++
            enqueued++
        }

        if (enqueued > 0) {
            _prefetchQueue = nextQueue
            _prefetchQueuedThreadIds = nextQueuedIds
            _prefetchAcceptedCount = accepted
            if (!prefetchTimer.running)
                prefetchTimer.restart()
        }
        _perfLog("prefetchForMessages — enqueued=" + enqueued)
        profileOperation("prefetchForMessages", profileStart,
                 "items=" + (items ? items.length : 0) + " enqueued=" + enqueued)
    }

    function prefetchMissingForMessages(items, authorsByThread) {
        var profileStart = Date.now()
        _perfLog("prefetchMissingForMessages — items=" + (items ? items.length : 0))
        if (!GitHubConstants.automaticAuthorPrefetchEnabled)
            return

        if (!loadAuthorInfo || !token || !items || items.length === 0)
            return

        var knownAuthors = authorsByThread || ({})
        var nextQueue = _prefetchQueue.slice(0)
        var nextQueuedIds = _prefetchQueuedThreadIds
        var enqueued = 0

        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            if (!item || !item.threadId)
                continue

            var needsSubjectWebUrl = requiresSubjectWebUrlResolution(item)
            var needsSubjectReference = requiresSubjectReferenceResolution(item)
            var needsAuthorDetails = shouldFetchAuthorDetailsForMessage(item)
                                      && !hasFetchedAuthorDetailsForMessage(item)
            var existingAuthors = knownAuthors[item.threadId] || []
            var needsMissingAuthors = existingAuthors.length === 0
            if (!needsSubjectWebUrl
                    && !needsSubjectReference
                    && !needsAuthorDetails
                    && !needsMissingAuthors
                    && fetchedAtMatches(fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue

            if (!needsSubjectWebUrl
                    && !needsSubjectReference
                    && !needsAuthorDetails
                    && existingAuthors.length > 0
                    && fetchedAtMatches(fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue

            var subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item)
            if (!subjectApiUrl)
                continue

            if (nextQueuedIds[item.threadId])
                continue
            if (hasQueuedOrActiveThreadRequest(item.threadId))
                continue

            nextQueuedIds[item.threadId] = true
            nextQueue.push({
                threadId: item.threadId,
                subjectApiUrl: subjectApiUrl,
                subjectType: item.subjectType || "",
                updatedAt: item.updatedAt || "",
                subjectTitle: item.title || "",
                includeDetails: shouldFetchAuthorDetailsForMessage(item),
                force: needsSubjectWebUrl || needsSubjectReference,
                fallbackAuthor: fallbackAuthorForMessage(item),
                reason: item.reason || ""
            })
            enqueued++
        }

        if (enqueued > 0) {
            _prefetchQueue = nextQueue
            _prefetchQueuedThreadIds = nextQueuedIds
            if (!prefetchTimer.running)
                prefetchTimer.restart()
        }
        _perfLog("prefetchMissingForMessages — enqueued=" + enqueued)
        profileOperation("prefetchMissingForMessages", profileStart,
                 "items=" + (items ? items.length : 0) + " enqueued=" + enqueued)
    }

    function resetState() {
        requestGeneration = requestGeneration + 1
        prefetchTimer.stop()
        mergeFlushTimer.stop()
        requestQueue = []
        requestsInFlight = 0
        activeUrlsByThread = ({})
        prefetchPending = false
        _pendingMerges = ({})
        _mergeFlushQueued = false
        _pendingAvatarPreloadAuthors = []
        _prefetchQueue = []
        _prefetchQueuedThreadIds = ({})
        _prefetchAcceptedCount = 0
    }

    function clearAllState() {
        resetState()
        fetchedUrlsByThread = ({})
        activeUrlsByThread = ({})
        fetchedAtUpdatedAt = ({})
    }

    function shouldExpandFromRequestedUrls(urls) {
        if (!urls || urls.length === 0)
            return false

        for (var index = 0; index < urls.length; index++) {
            var normalized = AuthorUtils.normalizeApiUrl(urls[index])
            if (!normalized)
                continue
            if (!AuthorUtils.isThreadParentApiUrl(normalized))
                return true
        }

        return false
    }

    function hasPendingPrefetchWork() {
        return _prefetchQueue.length > 0
               || prefetchTimer.running
               || _mergeFlushQueued
               || mergeFlushTimer.running
    }

    function hasQueuedOrActiveThreadRequest(threadId) {
        if (!threadId)
            return false

        var activeMap = activeUrlsByThread[threadId] || {}
        for (var activeUrl in activeMap)
            return true

        for (var index = 0; index < requestQueue.length; index++) {
            if (requestQueue[index].threadId === threadId)
                return true
        }

        return false
    }

    function repositoryWebUrlForMessage(item) {
        var repoUrl = String((item && item.repositoryUrl) || "").trim()
        if (repoUrl)
            return repoUrl

        var repo = String((item && item.repository) || "").trim()
        return repo ? (GitHubConstants.githubWebBaseUrl + "/" + repo) : ""
    }

    function requiresSubjectWebUrlResolution(item) {
        if (!item)
            return false

        var subjectType = String(item.subjectType || "").toLowerCase()
        var reason = String(item.reason || "").toLowerCase()
        var rawUrl = String(item.webUrl || "").trim()
        var repoUrl = repositoryWebUrlForMessage(item)
        var subjectApiUrl = String(item.subjectApiUrl || "").trim()

        if (reason === "ci_activity"
                || subjectType === "checksuite"
                || subjectType === "checkrun"
                || subjectType === "workflowrun") {
            return !rawUrl
                   || rawUrl === repoUrl
                   || rawUrl === repoUrl + "/actions"
                   || rawUrl.indexOf(GitHubConstants.githubWebBaseUrl + "/notifications/threads/") === 0
        }

        if (subjectType === "release" && /\/releases\/[0-9]+$/.test(subjectApiUrl)) {
            if (!rawUrl || rawUrl === repoUrl || rawUrl === repoUrl + "/releases")
                return true

            // Older cache entries guessed the tag from the notification title.
            // Numeric release API subjects need one enrichment fetch to get the
            // authoritative html_url, including suffixes like -rc15.
            if (rawUrl.indexOf("/releases/tag/") >= 0 && !item.webUrlResolved)
                return true
        }

        return false
    }

    function requiresSubjectReferenceResolution(item) {
        if (!item)
            return false

        var subjectType = String(item.subjectType || "").toLowerCase()
        if (subjectType !== "checksuite"
                && subjectType !== "checkrun"
                && subjectType !== "workflowrun")
            return false

        return String(item.subjectReference || "").trim() === ""
    }

    function shouldFetchAuthorDetailsForMessage(item) {
        if (!item)
            return false

        var subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item)
        if (!subjectApiUrl)
            return false

        return AuthorUtils.isThreadParentApiUrl(subjectApiUrl)
    }

    function hasFetchedAuthorDetailsForMessage(item) {
        if (!item || !item.threadId || !shouldFetchAuthorDetailsForMessage(item))
            return true

        var subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item)
        var urls = AuthorUtils.buildAuthorFetchUrls(subjectApiUrl,
                                                    item.subjectType || "",
                                                    true,
                                                    item.reason || "")
        if (urls.length <= 1)
            return true

        var fetchedMap = fetchedUrlsByThread[item.threadId] || {}
        var activeMap = activeUrlsByThread[item.threadId] || {}
        for (var index = 1; index < urls.length; index++) {
            var normalized = AuthorUtils.normalizeApiUrl(urls[index])
            if (normalized && !fetchedMap[normalized] && !activeMap[normalized])
                return false
        }

        return true
    }

    /// Returns the current merged authorsByThread including not-yet-flushed pending merges.
    function cloneAuthorsByThread(authorsByThread) {
        var copy = {}
        for (var threadId in authorsByThread)
            copy[threadId] = authorsByThread[threadId]
        for (var pendingId in _pendingMerges)
            copy[pendingId] = _pendingMerges[pendingId]
        return copy
    }

    // =========================================================================
    //  AUTHOR RESULT HANDLING (called from InboxBackgroundWorker signal)
    // =========================================================================

    function handleAuthorResult(message) {
        if (message.generation !== requestGeneration)
            return

        var threadId = message.threadId || ""
        var updatedAt = message.updatedAt || ""
        var fetchedAuthors = message.authors || []
        var fallbackAuthor = message.fallbackAuthor || null
        if (fetchedAuthors.length === 0 && fallbackAuthor)
            fetchedAuthors = [fallbackAuthor]
        fetchedAuthors = normalizeAuthorsForSubject(message.subjectType || "",
                                                    message.reason || "",
                                                    fetchedAuthors)
        var currentAuthors = authorsByThreadRef ? authorsByThreadRef : ({})

        var existingAuthors = message.automaticPrefetch
            ? []
            : (_pendingMerges[threadId] || currentAuthors[threadId] || [])
        var mergedAuthors = AuthorUtils.mergeAuthorLists(existingAuthors, fetchedAuthors)

        var nextPending = _pendingMerges
        nextPending[threadId] = mergedAuthors
        _pendingMerges = nextPending

        var pendingAvatars = _pendingAvatarPreloadAuthors
        for (var aIdx = 0; aIdx < mergedAuthors.length; aIdx++)
            pendingAvatars.push(mergedAuthors[aIdx])
        _pendingAvatarPreloadAuthors = pendingAvatars

        if (threadId) {
            var fetchedMarker = fetchedAtValue(updatedAt)
            fetchedAtUpdatedAt[threadId] = fetchedMarker
            authorFetchedAtChanged(threadId, fetchedMarker)
        }

        if (message.shouldExpand) {
            var expansionRoots = message.expansionUrls || []
            if (expansionRoots.length > 0) {
                var expansionUrls = []
                for (var expIdx = 0; expIdx < expansionRoots.length; expIdx++) {
                    var builtUrls = AuthorUtils.buildAuthorFetchUrls(expansionRoots[expIdx], "")
                    for (var urlIdx = 0; urlIdx < builtUrls.length; urlIdx++)
                        expansionUrls.push(builtUrls[urlIdx])
                }
                expansionUrlsDiscovered(threadId, expansionUrls)
            }
        }

        if ((message.subjectWebUrl || message.subjectReference) && threadId)
            subjectWebUrlResolved(threadId, message.subjectWebUrl || "", message.subjectReference || "")

        if (!_mergeFlushQueued) {
            _mergeFlushQueued = true
            mergeFlushTimer.restart()
        }

        requestsInFlight = Math.max(0, requestsInFlight - 1)
        prefetchMaybeComplete()
        Qt.callLater(processQueue)
    }

    // Reference to the current authorsByThread from Widget for merge base
    property var authorsByThreadRef: ({})

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    function processQueue() {
        var profileStart = Date.now()
        var startedRequests = 0
        if (!token || !loadAuthorInfo)
            return

        var queue = requestQueue
        var queueOffset = 0
        while (requestsInFlight < GitHubConstants.maxConcurrentAuthorFetches && queueOffset < queue.length) {
            _perfLog("processQueue — queueLen=" + requestQueue.length + " inFlight=" + requestsInFlight)

            var request = queue[queueOffset]
            queueOffset++

            var urls = filterThreadUnfetchedUrls(request.threadId, request.urls || [])
            if (urls.length === 0)
                continue

            markThreadUrlsActive(request.threadId, urls)
            requestsInFlight++
            startedRequests++
            var process = authorFetchComponentDef.createObject(authorFetcher, {
                generation: requestGeneration,
                threadId: request.threadId,
                requestedUrls: urls,
                updatedAt: request.updatedAt || "",
                automaticPrefetch: !!request.automaticPrefetch,
                fallbackAuthor: request.fallbackAuthor || null,
                subjectTitle: request.subjectTitle || "",
                subjectType: request.subjectType || "",
                reason: request.reason || ""
            })

            var command = request.automaticPrefetch
                    ? buildAutomaticAuthorExtractCommand(urls)
                    : buildRawAuthorFetchCommand(urls)

            ApiCallStats.recordCalls(urls.length)
            process.command = command
            process.running = true
        }
        if (queueOffset > 0)
            requestQueue = queue.slice(queueOffset)
        profileOperation("processQueue", profileStart,
                 "started=" + startedRequests + " inFlight=" + requestsInFlight
                 + " queue=" + requestQueue.length)
    }

    function _processPrefetchBatch() {
        var profileStart = Date.now()
        if (!loadAuthorInfo || !token) {
            prefetchTimer.stop()
            _prefetchQueue = []
            _prefetchQueuedThreadIds = ({})
            prefetchMaybeComplete()
            return
        }

        if (_prefetchQueue.length === 0) {
            prefetchTimer.stop()
            prefetchMaybeComplete()
            profileOperation("_processPrefetchBatch", profileStart, "empty")
            return
        }

        var batchSize = Math.max(1, GitHubConstants.authorPrefetchBatchSize)
        var queue = _prefetchQueue
        var nextQueuedIds = _prefetchQueuedThreadIds
        var processed = 0

        while (processed < batchSize && processed < queue.length) {
            var item = queue[processed]
            processed++

            if (item.threadId)
                delete nextQueuedIds[item.threadId]

            var lastFetchedUpdatedAt = fetchedAtUpdatedAt[item.threadId] || ""
            var forceFetch = !!item.force
            var includeDetails = !!item.includeDetails
            if (!forceFetch && !includeDetails && fetchedAtMatches(lastFetchedUpdatedAt, item.updatedAt))
                continue

            // Message updated since last fetch: clear URL-level state once,
            // then let the normal URL filter avoid duplicate subrequests.
            if ((forceFetch || lastFetchedUpdatedAt !== "")
                    && fetchedUrlsByThread.hasOwnProperty(item.threadId)) {
                delete fetchedUrlsByThread[item.threadId]
            }

            enqueueAuthorUrls(item.threadId,
                              AuthorUtils.buildAuthorFetchUrls(item.subjectApiUrl,
                                                               item.subjectType || "",
                                                               includeDetails,
                                                               item.reason || ""),
                              item.updatedAt || "",
                              true,
                              item.fallbackAuthor || null,
                              item.subjectTitle || "",
                              item.subjectType || "",
                              item.reason || "")
        }

        _prefetchQueue = queue.slice(processed)
        _prefetchQueuedThreadIds = nextQueuedIds

        if (_prefetchQueue.length === 0) {
            prefetchTimer.stop()
            prefetchMaybeComplete()
        }
        profileOperation("_processPrefetchBatch", profileStart,
                 "processed=" + processed + " remaining=" + _prefetchQueue.length)
    }

    function filterThreadUnfetchedUrls(threadId, urls) {
        var result = []
        if (!threadId || !urls || urls.length === 0)
            return result

        var fetchedMap = fetchedUrlsByThread[threadId] || {}
        var activeMap = activeUrlsByThread[threadId] || {}
        var seen = {}

        for (var index = 0; index < urls.length; index++) {
            var rawUrl = String(urls[index] || "").trim()
            var normalized = AuthorUtils.normalizeApiUrl(rawUrl)
            if (!normalized || fetchedMap[normalized] || activeMap[normalized] || seen[normalized])
                continue
            seen[normalized] = true
            result.push(rawUrl)
        }

        return result
    }

    function markThreadUrlsActive(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return

        var nextThreadMap = activeUrlsByThread[threadId] || {}

        for (var index = 0; index < urls.length; index++) {
            var url = AuthorUtils.normalizeApiUrl(urls[index])
            if (url)
                nextThreadMap[url] = true
        }

        activeUrlsByThread[threadId] = nextThreadMap
    }

    function markThreadUrlsInactive(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return

        var nextThreadMap = activeUrlsByThread[threadId] || {}
        var changed = false

        for (var index = 0; index < urls.length; index++) {
            var url = AuthorUtils.normalizeApiUrl(urls[index])
            if (url && nextThreadMap.hasOwnProperty(url)) {
                delete nextThreadMap[url]
                changed = true
            }
        }

        if (!changed)
            return

        var hasRemaining = false
        for (var activeUrl in nextThreadMap) {
            hasRemaining = true
            break
        }

        if (hasRemaining)
            activeUrlsByThread[threadId] = nextThreadMap
        else
            delete activeUrlsByThread[threadId]
    }

    function markThreadUrlsFetched(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return

        var nextThreadMap = fetchedUrlsByThread[threadId] || {}

        for (var index = 0; index < urls.length; index++) {
            var url = AuthorUtils.normalizeApiUrl(urls[index])
            if (url)
                nextThreadMap[url] = true
        }

        fetchedUrlsByThread[threadId] = nextThreadMap
    }

    function _flushMerges() {
        var profileStart = Date.now()
        _mergeFlushQueued = false

        var pending = _pendingMerges
        var remainingPending = {}
        var pendingAvatars = _pendingAvatarPreloadAuthors

        var changedIds = []
        var processed = 0
        var remainingCount = 0
        for (var changedId in pending) {
            if (processed >= GitHubConstants.authorMergeFlushBatchSize) {
                remainingPending[changedId] = pending[changedId]
                remainingCount++
                continue
            }
            changedIds.push(changedId)
            processed++
        }

        if (changedIds.length === 0) {
            _pendingMerges = remainingPending
            _pendingAvatarPreloadAuthors = pendingAvatars
            if (remainingCount > 0) {
                _mergeFlushQueued = true
                mergeFlushTimer.restart()
            }
            profileOperation("_flushMerges", profileStart, "changed=0")
            return
        }

        var changedSet = {}
        for (var setIndex = 0; setIndex < changedIds.length; setIndex++)
            changedSet[changedIds[setIndex]] = true

        var currentAuthors = authorsByThreadRef || ({})
        var next = {}
        for (var existingId in currentAuthors)
            next[existingId] = currentAuthors[existingId]
        for (var pendingId in pending) {
            if (!changedSet[pendingId])
                continue
            next[pendingId] = pending[pendingId]
        }

        _pendingMerges = remainingPending
        _pendingAvatarPreloadAuthors = []

        authorsMerged(next, pendingAvatars, changedIds)

        if (remainingCount > 0) {
            _mergeFlushQueued = true
            mergeFlushTimer.restart()
        }
        profileOperation("_flushMerges", profileStart,
                 "changed=" + changedIds.length + " remaining=" + remainingCount)
    }

    function _cloneThreadActiveUrlMap(threadId) {
        var source = activeUrlsByThread[threadId] || {}
        var copy = {}
        for (var url in source)
            copy[url] = source[url]
        return copy
    }

    function fallbackAuthorForMessage(item) {
        return null
    }

    function isCiSubjectType(subjectType) {
        var normalizedType = String(subjectType || "").toLowerCase()
        return normalizedType === "checksuite"
               || normalizedType === "checkrun"
               || normalizedType === "workflowrun"
    }

    function normalizeAuthorsForSubject(subjectType, reason, authors) {
        var source = authors || []
        var normalizedType = String(subjectType || "").toLowerCase()
        var normalizedReason = String(reason || "").toLowerCase()
        var filtered = filterAuthorsForSubject(normalizedType, source)

        if (isCiSubjectType(subjectType) && filtered.length > 1)
            return filtered.slice(0, 1)

        if ((normalizedType === "pullrequest" || normalizedType === "issue")
                && normalizedReason === "comment"
                && filtered.length > GitHubConstants.maxAuthorsDisplayedPerMessage)
            return filtered.slice(0, GitHubConstants.maxAuthorsDisplayedPerMessage)

        if (normalizedType === "pullrequest"
                && normalizedReason === "author"
                && filtered.length > GitHubConstants.maxAuthorsDisplayedPerMessage)
            return filtered.slice(0, GitHubConstants.maxAuthorsDisplayedPerMessage)

        return filtered
    }

    function filterAuthorsForSubject(normalizedType, authors) {
        var source = authors || []
        if (normalizedType !== "pullrequest" && normalizedType !== "issue")
            return source

        var filtered = []
        for (var index = 0; index < source.length; index++) {
            var author = source[index] || ({})
            var login = String(author.login || "").trim().toLowerCase()
            var htmlUrl = String(author.htmlUrl || author.html_url || "").trim().toLowerCase()
            if (login === "github-actions" || login === "github-actions[bot]"
                    || htmlUrl === GitHubConstants.githubWebBaseUrl + "/apps/github-actions")
                continue
            filtered.push(author)
        }
        return filtered
    }

    function buildRawAuthorFetchCommand(urls) {
        var command = ["curl"]
        for (var urlIndex = 0; urlIndex < urls.length; urlIndex++) {
            var url = urls[urlIndex]
            if (!url)
                continue
            if (command.length > 1)
                command.push("--next")
            command.push(
                "-sS",
                "--connect-timeout", GitHubConstants.curlConnectTimeoutSeconds,
                "--max-time", GitHubConstants.curlMaxTimeSeconds,
                "-H", "Accept: " + GitHubConstants.httpAcceptHeader,
                "-H", "X-GitHub-Api-Version: " + GitHubConstants.githubApiVersionHeader,
                "-H", "Authorization: token " + token,
                "-w", "\n" + authorSplitToken + "\n",
                url
            )
        }
        return command
    }

    function buildAutomaticAuthorExtractCommand(urls) {
        var script = ""
            + "token=$1\n"
            + "split=$2\n"
            + "connect_timeout=$3\n"
            + "max_time=$4\n"
            + "accept_header=$5\n"
            + "api_version=$6\n"
            + "shift 6\n"
            + "command -v jq >/dev/null 2>&1 || exit 127\n"
            + "filter='def appslug($u): if (($u // \"\") | startswith(\"https://github.com/apps/\")) then (($u | split(\"?\")[0] | split(\"#\")[0] | split(\"/\"))[-1]) else \"\" end; def rootobj: if type == \"object\" then . else {} end; def nodes: if type == \"array\" then reverse[] else . end; def authorobj: . as $o | (($o.html_url? // $o.htmlUrl? // \"\") as $html | ($o.login? // $o.slug? // appslug($html) // \"\") as $login | ($o.avatar_url? // $o.avatarUrl? // $o.logo_url? // $o.logoUrl? // (if appslug($html) != \"\" then ($html + \".png?size=128\") else \"\" end)) as $avatar | {login:$login, avatarUrl:$avatar, htmlUrl:($html // (if (($o.slug? // \"\") != \"\") then (\"https://github.com/apps/\" + $o.slug) else \"\" end)), type:($o.type? // (if appslug($html) != \"\" then \"App\" else \"\" end))}); def validauthor: authorobj | select((.login // \"\") != \"\" and (((.avatarUrl // \"\") != \"\") or ((.htmlUrl // \"\") != \"\"))); def author_sources($o): $o.actor?, $o.triggering_actor?, $o.user?, $o.author?, $o.sender?, $o.creator?, $o.merged_by?, $o.closed_by?, $o.dismissed_by?, ($o.workflow_runs?[]? | .actor?), ($o.workflow_runs?[]? | .triggering_actor?); rootobj as $root | {authors:([nodes as $n | author_sources($n) | validauthor] | reduce .[] as $a ([]; if any(.[]; .login == $a.login and .htmlUrl == $a.htmlUrl and .avatarUrl == $a.avatarUrl) then . else . + [$a] end)), subjectWebUrl:($root.html_url // \"\"), subjectReference:(($root.subjectReference // $root.subject_reference // $root.run_number // \"\") | tostring), actionRuns:(($root.workflow_runs // []) | map({htmlUrl:(.html_url // \"\"), runNumber:((.run_number // \"\") | tostring), name:(.name // \"\"), displayTitle:(.display_title // \"\"), headBranch:(.head_branch // \"\"), conclusion:(.conclusion // \"\"), updatedAt:(.updated_at // \"\")})), release:(if (($root.tag_name // \"\") != \"\" and ($root.html_url // \"\") != \"\") then {tagName:($root.tag_name // \"\"), htmlUrl:($root.html_url // \"\")} else null end)}'\n"
            + "for url in \"$@\"; do\n"
            + "  body=$(curl -f -sS -L --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H \"Authorization: token $token\" \"$url\") || exit $?\n"
            + "  printf '%s\\n' \"$body\" | jq -c \"$filter\" || exit $?\n"
            + "  printf '\\n%s\\n' \"$split\"\n"
            + "done\n"

        var command = [
            "nice", "-n", "10", "sh", "-c", script, "github-author-extract",
            token,
            authorSplitToken,
            GitHubConstants.curlConnectTimeoutSeconds,
            GitHubConstants.curlMaxTimeSeconds,
            GitHubConstants.httpAcceptHeader,
            GitHubConstants.githubApiVersionHeader
        ]

        for (var urlIndex = 0; urlIndex < urls.length; urlIndex++) {
            if (urls[urlIndex])
                command.push(urls[urlIndex])
        }
        return command
    }

    // =========================================================================
    //  PROCESS COMPONENT
    // =========================================================================

    Component {
        id: authorFetchComponentDef

        Process {
            property string threadId: ""
            property var requestedUrls: []
            property string updatedAt: ""
            property int generation: 0
            property bool automaticPrefetch: false
            property var fallbackAuthor: null
            property string subjectTitle: ""
            property string subjectType: ""
            property string reason: ""
            property string _buffer: ""
            property int _bufferBytes: 0
            property real _startedAt: Date.now()

            stdout: SplitParser {
                onRead: line => {
                    _buffer += line + "\n"
                    _bufferBytes += line.length + 1
                }
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[GitHubInbox] author:", line)
                }
            }

            onExited: exitCode => {
                if (generation !== authorFetcher.requestGeneration) {
                    destroy()
                    return
                }

                authorFetcher.markThreadUrlsInactive(threadId, requestedUrls || [])

                if (!authorFetcher.loadAuthorInfo) {
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1)
                    authorFetcher.prefetchMaybeComplete()
                    Qt.callLater(authorFetcher.processQueue)
                    destroy()
                    return
                }

                if (exitCode !== 0) {
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1)
                    authorFetcher.prefetchMaybeComplete()
                    Qt.callLater(authorFetcher.processQueue)
                    destroy()
                    return
                }

                if (!authorFetcher.workerSendMessage) {
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1)
                    authorFetcher.prefetchMaybeComplete()
                    Qt.callLater(authorFetcher.processQueue)
                    destroy()
                    return
                }

                authorFetcher.markThreadUrlsFetched(threadId, requestedUrls || [])

                authorFetcher.workerSendMessage({
                    action: "parseAuthors",
                    generation: generation,
                    threadId: threadId,
                    updatedAt: updatedAt || "",
                    requestedUrls: requestedUrls || [],
                    automaticPrefetch: automaticPrefetch,
                    subjectType: subjectType || "",
                    reason: reason || "",
                    shouldExpand: !automaticPrefetch && authorFetcher.shouldExpandFromRequestedUrls(requestedUrls || []),
                    fallbackAuthor: fallbackAuthor || null,
                    subjectTitle: subjectTitle || "",
                    buffer: _buffer,
                    splitToken: authorFetcher.authorSplitToken
                })
                authorFetcher.profileOperation("authorFetchProcess",
                                               _startedAt,
                                               "thread=" + threadId
                                               + " bytes=" + _bufferBytes
                                               + " urls=" + (requestedUrls ? requestedUrls.length : 0)
                                               + " automatic=" + automaticPrefetch)
                destroy()
            }
        }
    }
}
