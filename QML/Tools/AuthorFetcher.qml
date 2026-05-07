// AuthorFetcher.qml - Manages author data fetching and queue processing
//
// Handles URL-level deduplication, queue management, curl-based fetching,
// and offloading JSON parsing to a WorkerScript (via InboxFetcher).

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

    // -- External dependency: fetcher provides sendWorkerMessage()  -----------
    property var workerSendMessage: null   // bind to inboxFetcher.sendWorkerMessage

    // -- State ----------------------------------------------------------------
    property var requestQueue: []
    property int requestsInFlight: 0
    property var fetchedUrlsByThread: ({})
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

    // -- Signals --------------------------------------------------------------

    /// Emitted once per tick with the full merged authorsByThread snapshot,
    /// accumulated avatar-preload authors, and the IDs of changed threads.
    signal authorsMerged(var authorsByThread, var preloadAuthors, var changedThreadIds)

    /// Emitted per-thread when authorFetchedAtUpdatedAt is updated.
    signal authorFetchedAtChanged(string threadId, string updatedAt)

    /// Emitted when expansion URLs are discovered and need enqueueing.
    signal expansionUrlsDiscovered(string threadId, var urls)

    /// Emitted when the prefetch cycle may have completed.
    signal prefetchMaybeComplete()

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        if (!GitHubConstants.debugPerformanceLogging) return
        console.warn("[GitHubInbox PERF] AuthorFetcher: " + label)
    }

    Timer {
        id: prefetchTimer
        interval: GitHubConstants.authorPrefetchBatchIntervalMs
        repeat: true
        onTriggered: authorFetcher._processPrefetchBatch()
    }

    function enqueueAuthorFetch(threadId, subjectApiUrl, subjectType, updatedAt, automaticPrefetch) {
        if (!loadAuthorInfo || !token || !threadId || !subjectApiUrl)
            return

        enqueueAuthorUrls(threadId,
            AuthorUtils.buildAuthorFetchUrls(subjectApiUrl, subjectType || "", !automaticPrefetch),
            updatedAt || "",
            !!automaticPrefetch)
    }

    function enqueueAuthorUrls(threadId, urls, updatedAt, automaticPrefetch) {
        if (!token || !threadId || !urls || urls.length === 0)
            return

        var candidateUrls = filterThreadUnfetchedUrls(threadId, urls)
        if (candidateUrls.length === 0)
            return

        var pendingMap = {}
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
            automaticPrefetch: !!automaticPrefetch
        }

        if (automaticPrefetch && nextQueue.length >= GitHubConstants.maxAuthorRequestQueueLength)
            return

        if (automaticPrefetch)
            nextQueue.push(request)
        else
            nextQueue.unshift(request)

        requestQueue = nextQueue
        processQueue()
    }

    function prefetchForMessages(items) {
        _perfLog("prefetchForMessages — items=" + (items ? items.length : 0))
        if (!GitHubConstants.automaticAuthorPrefetchEnabled)
            return

        if (!loadAuthorInfo || !token || !items || items.length === 0)
            return

        var nextQueue = _prefetchQueue.slice(0)
        var nextQueuedIds = _cloneMap(_prefetchQueuedThreadIds)
        var accepted = _prefetchAcceptedCount
        var enqueued = 0

        for (var index = 0; index < items.length; index++) {
            if (accepted >= GitHubConstants.maxAuthorPrefetchMessagesPerRefresh)
                break

            var item = items[index]
            if (!item || !item.threadId)
                continue

            var subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item)
            if (!subjectApiUrl)
                continue

            if (nextQueuedIds[item.threadId])
                continue

            nextQueuedIds[item.threadId] = true
            nextQueue.push({
                threadId: item.threadId,
                subjectApiUrl: subjectApiUrl,
                subjectType: item.subjectType || "",
                updatedAt: item.updatedAt || ""
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
    }

    function resetState() {
        requestGeneration = requestGeneration + 1
        prefetchTimer.stop()
        requestQueue = []
        requestsInFlight = 0
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
        return _prefetchQueue.length > 0 || prefetchTimer.running
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
    //  AUTHOR RESULT HANDLING (called from InboxFetcher signal)
    // =========================================================================

    function handleAuthorResult(message) {
        if (message.generation !== requestGeneration)
            return

        var threadId = message.threadId || ""
        var updatedAt = message.updatedAt || ""
        var fetchedAuthors = message.authors || []
        var currentAuthors = authorsByThreadRef ? authorsByThreadRef : ({})

        var existingAuthors = (_pendingMerges[threadId]
                               || currentAuthors[threadId] || [])
        var mergedAuthors = AuthorUtils.mergeAuthorLists(existingAuthors, fetchedAuthors)

        var nextPending = _pendingMerges
        nextPending[threadId] = mergedAuthors
        _pendingMerges = nextPending

        var pendingAvatars = _pendingAvatarPreloadAuthors
        for (var aIdx = 0; aIdx < mergedAuthors.length; aIdx++)
            pendingAvatars.push(mergedAuthors[aIdx])
        _pendingAvatarPreloadAuthors = pendingAvatars

        if (threadId && mergedAuthors.length > 0) {
            fetchedAtUpdatedAt[threadId] = updatedAt
            authorFetchedAtChanged(threadId, updatedAt)
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

        if (!_mergeFlushQueued) {
            _mergeFlushQueued = true
            Qt.callLater(_flushMerges)
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
        if (!token || !loadAuthorInfo)
            return

        while (requestsInFlight < GitHubConstants.maxConcurrentAuthorFetches && requestQueue.length > 0) {
            _perfLog("processQueue — queueLen=" + requestQueue.length + " inFlight=" + requestsInFlight)

            var nextQueue = requestQueue.slice(0)
            var request = nextQueue.shift()
            requestQueue = nextQueue

            var urls = filterThreadUnfetchedUrls(request.threadId, request.urls || [])
            if (urls.length === 0)
                continue

            requestsInFlight++
            var process = authorFetchComponentDef.createObject(authorFetcher, {
                generation: requestGeneration,
                threadId: request.threadId,
                requestedUrls: urls,
                updatedAt: request.updatedAt || "",
                automaticPrefetch: !!request.automaticPrefetch
            })

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

            ApiCallStats.recordCalls(urls.length)
            process.command = command
            process.running = true
        }
    }

    function _processPrefetchBatch() {
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
            return
        }

        var batchSize = Math.max(1, GitHubConstants.authorPrefetchBatchSize)
        var remaining = _prefetchQueue.slice(0)
        var nextQueuedIds = _cloneMap(_prefetchQueuedThreadIds)
        var processed = 0

        while (processed < batchSize && remaining.length > 0) {
            var item = remaining.shift()
            processed++

            if (item.threadId)
                delete nextQueuedIds[item.threadId]

            var lastFetchedUpdatedAt = fetchedAtUpdatedAt[item.threadId] || ""
            if (lastFetchedUpdatedAt === item.updatedAt)
                continue

            // Message updated since last fetch: clear URL-level state once,
            // then let the normal URL filter avoid duplicate subrequests.
            if (lastFetchedUpdatedAt !== "" && fetchedUrlsByThread.hasOwnProperty(item.threadId)) {
                var nextFetchedState = _cloneFetchedUrlsByThread()
                delete nextFetchedState[item.threadId]
                fetchedUrlsByThread = nextFetchedState
            }

            enqueueAuthorFetch(item.threadId, item.subjectApiUrl, item.subjectType || "", item.updatedAt || "", true)
        }

        _prefetchQueue = remaining
        _prefetchQueuedThreadIds = nextQueuedIds

        if (_prefetchQueue.length === 0) {
            prefetchTimer.stop()
            prefetchMaybeComplete()
        }
    }

    function filterThreadUnfetchedUrls(threadId, urls) {
        var result = []
        if (!threadId || !urls || urls.length === 0)
            return result

        var fetchedMap = fetchedUrlsByThread[threadId] || {}
        var seen = {}

        for (var index = 0; index < urls.length; index++) {
            var rawUrl = String(urls[index] || "").trim()
            var normalized = AuthorUtils.normalizeApiUrl(rawUrl)
            if (!normalized || fetchedMap[normalized] || seen[normalized])
                continue
            seen[normalized] = true
            result.push(rawUrl)
        }

        return result
    }

    function markThreadUrlsFetched(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return

        var nextByThread = _cloneFetchedUrlsByThread()
        var nextThreadMap = _cloneThreadFetchedUrlMap(threadId)

        for (var index = 0; index < urls.length; index++) {
            var url = AuthorUtils.normalizeApiUrl(urls[index])
            if (url)
                nextThreadMap[url] = true
        }

        nextByThread[threadId] = nextThreadMap
        fetchedUrlsByThread = nextByThread
    }

    function _flushMerges() {
        _mergeFlushQueued = false

        var pending = _pendingMerges
        _pendingMerges = ({})
        var pendingAvatars = _pendingAvatarPreloadAuthors
        _pendingAvatarPreloadAuthors = []

        // Collect which thread IDs were changed in this batch
        var changedIds = []
        for (var changedId in pending)
            changedIds.push(changedId)

        // Build the full merged authorsByThread snapshot
        var currentAuthors = authorsByThreadRef || ({})
        var next = {}
        for (var existingId in currentAuthors)
            next[existingId] = currentAuthors[existingId]
        for (var pendingId in pending)
            next[pendingId] = pending[pendingId]
        // Also fold in any not-yet-flushed pending merges
        for (var extraId in _pendingMerges)
            next[extraId] = _pendingMerges[extraId]

        authorsMerged(next, pendingAvatars, changedIds)
    }

    function _cloneFetchedUrlsByThread() {
        var copy = {}
        for (var threadId in fetchedUrlsByThread) {
            var threadCopy = {}
            var source = fetchedUrlsByThread[threadId] || {}
            for (var url in source)
                threadCopy[url] = source[url]
            copy[threadId] = threadCopy
        }
        return copy
    }

    function _cloneThreadFetchedUrlMap(threadId) {
        var source = fetchedUrlsByThread[threadId] || {}
        var copy = {}
        for (var url in source)
            copy[url] = source[url]
        return copy
    }

    function _cloneMap(source) {
        var copy = {}
        for (var key in source)
            copy[key] = source[key]
        return copy
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
            property string _buffer: ""

            stdout: SplitParser {
                onRead: line => _buffer += line + "\n"
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

                if (!authorFetcher.loadAuthorInfo) {
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1)
                    authorFetcher.prefetchMaybeComplete()
                    Qt.callLater(authorFetcher.processQueue)
                    destroy()
                    return
                }

                authorFetcher.markThreadUrlsFetched(threadId, requestedUrls || [])

                if (exitCode !== 0) {
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1)
                    authorFetcher.prefetchMaybeComplete()
                    Qt.callLater(authorFetcher.processQueue)
                    destroy()
                    return
                }

                if (authorFetcher.workerSendMessage) {
                    authorFetcher.workerSendMessage({
                        action: "parseAuthors",
                        generation: generation,
                        threadId: threadId,
                        updatedAt: updatedAt || "",
                        requestedUrls: requestedUrls || [],
                        shouldExpand: !automaticPrefetch && authorFetcher.shouldExpandFromRequestedUrls(requestedUrls || []),
                        buffer: _buffer,
                        splitToken: authorFetcher.authorSplitToken
                    })
                }
                destroy()
            }
        }
    }
}
