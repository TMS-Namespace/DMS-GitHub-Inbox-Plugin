// AuthorBackgroundWorker.qml - Manages author data fetching and queue processing
//
// Handles URL-level deduplication, queue management, curl-based fetching,
// and offloading JSON parsing to a WorkerScript (via InboxBackgroundWorker).
// Dux v2's dms dl accepts headers only through argv, not stdin or a header file.
// Both authenticated fetch builders retain curl -H @- to keep tokens out of process arguments.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: authorFetcher

    property bool _mergeFlushQueued: false
    property var _pendingAvatarPreloadAuthors: []

    // Deferred merge batching
    property var _pendingMerges: ({})
    property int _prefetchAcceptedCount: 0
    property var _prefetchQueue: []
    property var _prefetchQueuedThreadIds: ({})
    property var activeUrlsByThread: ({})
    property string authorSplitToken: GitHubConstants.authorPayloadSplitToken

    // Reference to the current authorsByThread from Widget for merge base
    property var authorsByThreadRef: ({})
    property var fetchedAtUpdatedAt: ({})
    property var fetchedUrlsByThread: ({})
    readonly property bool isBusy: requestsInFlight > 0 || requestQueue.length > 0 || _prefetchQueue.length > 0 || prefetchTimer.running || _mergeFlushQueued || mergeFlushTimer.running
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
    // Publish one batch of pending author merges and defer any remaining threads.
    function _flushMerges() {
        let profileStart = Date.now();
        _mergeFlushQueued = false;

        let pending = _pendingMerges;
        let remainingPending = {};
        let pendingAvatars = _pendingAvatarPreloadAuthors;

        let changedIds = [];
        let processed = 0;
        let remainingCount = 0;
        for (let changedId in pending) {
            if (processed >= GitHubConstants.authorMergeFlushBatchSize) {
                remainingPending[changedId] = pending[changedId];
                remainingCount++;
                continue;
            }
            changedIds.push(changedId);
            processed++;
        }

        if (changedIds.length === 0) {
            _pendingMerges = remainingPending;
            _pendingAvatarPreloadAuthors = pendingAvatars;
            if (remainingCount > 0) {
                _mergeFlushQueued = true;
                mergeFlushTimer.restart();
            }
            profileOperation("_flushMerges", profileStart, "changed=0");
            return;
        }

        let changedSet = {};
        for (let setIndex = 0; setIndex < changedIds.length; setIndex++)
            changedSet[changedIds[setIndex]] = true;

        let currentAuthors = authorsByThreadRef || ({});
        let next = {};
        for (let existingId in currentAuthors)
            next[existingId] = currentAuthors[existingId];
        for (let pendingId in pending) {
            if (!changedSet[pendingId])
                continue;
            next[pendingId] = pending[pendingId];
        }

        _pendingMerges = remainingPending;
        _pendingAvatarPreloadAuthors = [];

        authorsMerged(next, pendingAvatars, changedIds);

        if (remainingCount > 0) {
            _mergeFlushQueued = true;
            mergeFlushTimer.restart();
        }
        profileOperation("_flushMerges", profileStart, "changed=" + changedIds.length + " remaining=" + remainingCount);
    }

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
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

            let lastFetchedUpdatedAt = fetchedAtUpdatedAt[item.threadId] || "";
            let forceFetch = !!item.force;
            let includeDetails = !!item.includeDetails;
            if (!forceFetch && !includeDetails && fetchedAtMatches(lastFetchedUpdatedAt, item.updatedAt))
                continue;

            // Message updated since last fetch: clear URL-level state once,
            // then let the normal URL filter avoid duplicate subrequests.
            if ((forceFetch || lastFetchedUpdatedAt !== "") && fetchedUrlsByThread.hasOwnProperty(item.threadId)) {
                delete fetchedUrlsByThread[item.threadId];
            }

            enqueueAuthorUrls(item.threadId, AuthorUtils.buildAuthorFetchUrls(item.subjectApiUrl, item.subjectType || "", includeDetails, item.reason || ""), item.updatedAt || "", true, item.fallbackAuthor || null, item.subjectTitle || "", item.subjectType || "", item.reason || "");
        }

        _prefetchQueue = queue.slice(processed);
        _prefetchQueuedThreadIds = nextQueuedIds;

        if (_prefetchQueue.length === 0) {
            prefetchTimer.stop();
            prefetchMaybeComplete();
        }
        profileOperation("_processPrefetchBatch", profileStart, "processed=" + processed + " remaining=" + _prefetchQueue.length);
    }
    // Measure this operation through the shared profiling gate.
    function _profile(label, startMs, details) {
        profileOperation(label, startMs, details);
    }
    // Build authenticated fetches that use jq to extract actors, workflow details and release links.
    function buildAutomaticAuthorExtractCommand(urls) {
        let retryPolicy = authorFetcher.providerApi.getRetryPolicy();
        let script = "" + "IFS= read -r token || exit 1\n" + "split=$1\n" + "connect_timeout=$2\n" + "max_time=$3\n" + "accept_header=$4\n" + "api_version=$5\n" + "retry_count=$6\n" + "retry_max_time=$7\n" + "shift 7\n" + "command -v jq >/dev/null 2>&1 || exit 127\n" + "filter='def appslug($profileUrl): if (($profileUrl // \"\") | startswith(\"https://github.com/apps/\")) then (($profileUrl | split(\"?\")[0] | split(\"#\")[0] | split(\"/\"))[-1]) else \"\" end; def rootobj: if type == \"object\" then . else {} end; def nodes: if type == \"array\" then reverse[] else . end; def authorobj: . as $authorObject | (($authorObject.html_url? // $authorObject.htmlUrl? // \"\") as $html | ($authorObject.login? // $authorObject.slug? // appslug($html) // \"\") as $login | ($authorObject.avatar_url? // $authorObject.avatarUrl? // $authorObject.logo_url? // $authorObject.logoUrl? // (if appslug($html) != \"\" then ($html + \".png?size=128\") else \"\" end)) as $avatar | {login:$login, avatarUrl:$avatar, htmlUrl:($html // (if (($authorObject.slug? // \"\") != \"\") then (\"https://github.com/apps/\" + $authorObject.slug) else \"\" end)), type:($authorObject.type? // (if appslug($html) != \"\" then \"App\" else \"\" end))}); def validauthor: authorobj | select((.login // \"\") != \"\" and (((.avatarUrl // \"\") != \"\") or ((.htmlUrl // \"\") != \"\"))); def author_sources($authorObject): $authorObject.actor?, $authorObject.triggering_actor?, $authorObject.user?, $authorObject.author?, $authorObject.sender?, $authorObject.creator?, $authorObject.merged_by?, $authorObject.closed_by?, $authorObject.dismissed_by?; rootobj as $root | {authors:([nodes as $node | author_sources($node) | validauthor] | reduce .[] as $author ([]; if any(.[]; .login == $author.login and .htmlUrl == $author.htmlUrl and .avatarUrl == $author.avatarUrl) then . else . + [$author] end)), subjectWebUrl:($root.html_url // \"\"), subjectReference:(($root.subjectReference // $root.subject_reference // $root.run_number // \"\") | tostring), actionRuns:(($root.workflow_runs // []) | map({htmlUrl:(.html_url // \"\"), runNumber:((.run_number // \"\") | tostring), name:(.name // \"\"), displayTitle:(.display_title // \"\"), headBranch:(.head_branch // \"\"), conclusion:(.conclusion // \"\"), updatedAt:(.updated_at // \"\"), actor:(if .actor? then (.actor | authorobj) else null end), triggeringActor:(if .triggering_actor? then (.triggering_actor | authorobj) else null end)})), release:(if (($root.tag_name // \"\") != \"\" and ($root.html_url // \"\") != \"\") then {tagName:($root.tag_name // \"\"), htmlUrl:($root.html_url // \"\")} else null end)}'\n" + "for url in \"$@\"; do\n" + "  body=$(printf 'Authorization: token %s\\n' \"$token\" | curl -f -sS -L --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" --retry \"$retry_count\" --retry-connrefused --retry-max-time \"$retry_max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H @- \"$url\") || exit $?\n" + "  printf '%s\\n' \"$body\" | jq -c \"$filter\" || exit $?\n" + "  printf '\\n%s\\n' \"$split\"\n" + "done\n";

        let command = ["nice", "-n", "10", "bash", "-c", script, "github-author-extract", authorSplitToken, GitHubConstants.curlConnectTimeoutSeconds, GitHubConstants.curlMaxTimeSeconds, GitHubConstants.httpAcceptHeader, GitHubConstants.githubApiVersionHeader, String(retryPolicy.retryCount), String(retryPolicy.maximumRetryTimeSeconds)];

        for (let urlIndex = 0; urlIndex < urls.length; urlIndex++) {
            if (urls[urlIndex])
                command.push(urls[urlIndex]);
        }
        return command;
    }
    // Build authenticated fetches that return raw response bodies separated by the worker marker.
    function buildRawAuthorFetchCommand(urls) {
        let retryPolicy = authorFetcher.providerApi.getRetryPolicy();
        let script = "" + "IFS= read -r token || exit 1\n" + "split=$1; connect_timeout=$2; max_time=$3; accept_header=$4; api_version=$5; retry_count=$6; retry_max_time=$7\n" + "shift 7\n" + "for url in \"$@\"; do\n" + "  printf 'Authorization: token %s\\n' \"$token\" | curl -sS --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" --retry \"$retry_count\" --retry-connrefused --retry-max-time \"$retry_max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H @- -w \"\\n$split\\n\" \"$url\"\n" + "done\n";
        let command = ["bash", "-c", script, "github-author-fetch", authorSplitToken, GitHubConstants.curlConnectTimeoutSeconds, GitHubConstants.curlMaxTimeSeconds, GitHubConstants.httpAcceptHeader, GitHubConstants.githubApiVersionHeader, String(retryPolicy.retryCount), String(retryPolicy.maximumRetryTimeSeconds)];
        for (let urlIndex = 0; urlIndex < urls.length; urlIndex++)
            if (urls[urlIndex])
                command.push(urls[urlIndex]);
        return command;
    }
    // Cancel author work and clear both completed endpoint history and activity markers.
    function clearAllState() {
        resetState();
        fetchedUrlsByThread = ({});
        activeUrlsByThread = ({});
        fetchedAtUpdatedAt = ({});
    }

    /// Returns the current merged authorsByThread including not-yet-flushed pending merges.
    function cloneAuthorsByThread(authorsByThread) {
        let copy = {};
        for (let threadId in authorsByThread)
            copy[threadId] = authorsByThread[threadId];
        for (let pendingId in _pendingMerges)
            copy[pendingId] = _pendingMerges[pendingId];
        return copy;
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
        let currentAuthors = authorsByThreadRef ? authorsByThreadRef : ({});

        let existingAuthors = message.automaticPrefetch ? [] : (_pendingMerges[threadId] || currentAuthors[threadId] || []);
        let mergedAuthors = AuthorUtils.mergeAuthorLists(existingAuthors, fetchedAuthors);

        let nextPending = _pendingMerges;
        nextPending[threadId] = mergedAuthors;
        _pendingMerges = nextPending;

        let pendingAvatars = _pendingAvatarPreloadAuthors;
        for (let authorIndex = 0; authorIndex < mergedAuthors.length; authorIndex++)
            pendingAvatars.push(mergedAuthors[authorIndex]);
        _pendingAvatarPreloadAuthors = pendingAvatars;

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

        if (!_mergeFlushQueued) {
            _mergeFlushQueued = true;
            mergeFlushTimer.restart();
        }

        requestsInFlight = Math.max(0, requestsInFlight - 1);
        prefetchMaybeComplete();
        Qt.callLater(processQueue);
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
        return _prefetchQueue.length > 0 || prefetchTimer.running || _mergeFlushQueued || mergeFlushTimer.running;
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
            let needsSubjectWebUrl = requiresSubjectWebUrlResolution(item);
            let needsSubjectReference = requiresSubjectReferenceResolution(item);
            let needsAuthorDetails = shouldFetchAuthorDetailsForMessage(item) && !hasFetchedAuthorDetailsForMessage(item);
            let existingAuthors = (authorsByThreadRef || ({}))[item.threadId] || [];
            let needsMissingAuthors = existingAuthors.length === 0;
            if (!needsSubjectWebUrl && !needsSubjectReference && !needsAuthorDetails && !needsMissingAuthors && fetchedAtMatches(fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue;
            let subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item);
            if (!subjectApiUrl)
                continue;
            if (nextQueuedIds[item.threadId])
                continue;
            if (hasQueuedOrActiveThreadRequest(item.threadId))
                continue;
            nextQueuedIds[item.threadId] = true;
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
            let needsSubjectWebUrl = requiresSubjectWebUrlResolution(item);
            let needsSubjectReference = requiresSubjectReferenceResolution(item);
            let needsAuthorDetails = shouldFetchAuthorDetailsForMessage(item) && !hasFetchedAuthorDetailsForMessage(item);
            let existingAuthors = knownAuthors[item.threadId] || [];
            let needsMissingAuthors = existingAuthors.length === 0;
            if (!needsSubjectWebUrl && !needsSubjectReference && !needsAuthorDetails && !needsMissingAuthors && fetchedAtMatches(fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue;
            if (!needsSubjectWebUrl && !needsSubjectReference && !needsAuthorDetails && existingAuthors.length > 0 && fetchedAtMatches(fetchedAtUpdatedAt[item.threadId], item.updatedAt))
                continue;
            let subjectApiUrl = AuthorUtils.resolveSubjectApiUrlForAuthors(item);
            if (!subjectApiUrl)
                continue;
            if (nextQueuedIds[item.threadId])
                continue;
            if (hasQueuedOrActiveThreadRequest(item.threadId))
                continue;
            nextQueuedIds[item.threadId] = true;
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
            let command = request.automaticPrefetch ? buildAutomaticAuthorExtractCommand(urls) : buildRawAuthorFetchCommand(urls);

            authorFetchComponentDef.createObject(authorFetcher, {
                generation: requestGeneration,
                requestToken: token,
                threadId: request.threadId,
                requestedUrls: urls,
                updatedAt: request.updatedAt || "",
                automaticPrefetch: !!request.automaticPrefetch,
                fallbackAuthor: request.fallbackAuthor || null,
                subjectTitle: request.subjectTitle || "",
                subjectType: request.subjectType || "",
                reason: request.reason || "",
                command: command,
                running: true
            });

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
        prefetchTimer.stop();
        mergeFlushTimer.stop();
        requestQueue = [];
        requestsInFlight = 0;
        activeUrlsByThread = ({});
        prefetchPending = false;
        _pendingMerges = ({});
        _mergeFlushQueued = false;
        _pendingAvatarPreloadAuthors = [];
        _prefetchQueue = [];
        _prefetchQueuedThreadIds = ({});
        _prefetchAcceptedCount = 0;
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

    // =========================================================================
    //  PROCESS COMPONENT
    // =========================================================================

    Component {
        id: authorFetchComponentDef

        Process {
            id: authorFetchProcess

            property string _buffer: ""
            property int _bufferBytes: 0
            property real _startedAt: Date.now()
            property bool automaticPrefetch: false
            property var fallbackAuthor: null
            property int generation: 0
            property string reason: ""
            property string requestToken: ""
            property var requestedUrls: []
            property string subjectTitle: ""
            property string subjectType: ""
            property string threadId: ""
            property string updatedAt: ""

            stdinEnabled: true

            stdout: SplitParser {
                onRead: line => {
                    authorFetchProcess._buffer += line + "\n";
                    authorFetchProcess._bufferBytes += line.length + 1;
                }
            }

            onExited: exitCode => {
                if (generation !== authorFetcher.requestGeneration) {
                    destroy();
                    return;
                }

                authorFetcher.markThreadUrlsInactive(threadId, requestedUrls || []);

                if (!authorFetcher.loadAuthorInfo) {
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1);
                    authorFetcher.prefetchMaybeComplete();
                    Qt.callLater(authorFetcher.processQueue);
                    destroy();
                    return;
                }

                if (exitCode !== 0) {
                    PluginLogger.error("author", "GitHub author request failed with exit code " + exitCode);
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1);
                    authorFetcher.prefetchMaybeComplete();
                    Qt.callLater(authorFetcher.processQueue);
                    destroy();
                    return;
                }

                if (!authorFetcher.workerSendMessage) {
                    authorFetcher.requestsInFlight = Math.max(0, authorFetcher.requestsInFlight - 1);
                    authorFetcher.prefetchMaybeComplete();
                    Qt.callLater(authorFetcher.processQueue);
                    destroy();
                    return;
                }

                authorFetcher.markThreadUrlsFetched(threadId, requestedUrls || []);

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
                });
                authorFetcher.profileOperation("authorFetchProcess", _startedAt, "thread=" + threadId + " bytes=" + _bufferBytes + " urls=" + (requestedUrls ? requestedUrls.length : 0) + " automatic=" + automaticPrefetch);
                destroy();
            }
            onStarted: {
                write(requestToken + "\n");
                stdinEnabled = false;
                requestToken = "";
            }
        }
    }
}
