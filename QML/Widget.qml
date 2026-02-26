// Widget.qml - Main GitHub Inbox widget for DankMaterialShell

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

    layerNamespacePlugin: "github-inbox"

    // -- Settings-backed state ------------------------------------------------
    property string token: (pluginData.githubToken || "").trim()
    property int pollIntervalMs: GitHub.pollIntervalMs(pluginData.pollInterval)
    property int groupItemLimit: {
        var value = parseInt(pluginData.groupItemLimit || "25")
        if (isNaN(value))
            return 25
        return Math.max(1, Math.min(25, value))
    }
    property int fetchPageCount: {
        var value = parseInt(pluginData.fetchPages || "3")
        if (isNaN(value))
            return 3
        return Math.max(1, Math.min(10, value))
    }
    property int popupItems: {
        var value = parseInt(pluginData.popupItems || "5")
        if (isNaN(value))
            return 5
        return Math.max(1, Math.min(50, value))
    }
    property int titleLines: {
        var value = parseInt(pluginData.titleLines || "2")
        if (isNaN(value))
            return 2
        return Math.max(1, Math.min(6, value))
    }

    // -- Runtime state --------------------------------------------------------
    property var notifications: []
    property var notificationsForView: []
    property var pendingViewNotifications: []
    property int pendingViewIndex: 0
    property int unreadCount: 0
    property bool isLoading: false
    property bool isMutating: false
    property bool fetchQueued: false
    property string errorMessage: ""
    property real lastUpdated: 0
    property var doneThreadState: ({})
    property string fetchSplitToken: "__GH_PARTICIPATING_SPLIT__"
    property string authorSplitToken: "__GH_AUTHOR_SPLIT__"
    property int parseRequestSeq: 0
    property int viewApplyChunkSize: 20
    property var expandedReposState: ({ "__defaultExpanded": true })
    property var authorsByThread: ({})
    property var authorRequestQueue: []
    property bool authorRequestInFlight: false
    property var authorFetchedUrlsByThread: ({})
    property var pendingThreadDoneQueue: []
    property var avatarPreloadEntries: []
    property var avatarPreloadMap: ({})
    property int avatarPreloadLimit: 500

    property url githubIconPrimary: "https://github.com/favicon.ico"
    property url githubIconFallback: Qt.resolvedUrl("../Images/github-mark.svg")

    property int totalCount: notifications.length
    property int readCount: Math.max(0, notifications.length - unreadCount)
    property int shownCount: notificationsForView.length

    property string barCountText: GitHub.formatBarCount(unreadCount, totalCount, true)

    property string popoutDetails: {
        if (!token)
            return "Set your GitHub classic token in Settings"
        if (errorMessage)
            return errorMessage
        if (isLoading && notifications.length === 0)
            return "Loading notifications..."

        var counts = unreadCount + " unread / " + readCount + " read / " + totalCount + " total"
        var summary = counts + " - showing " + shownCount
        if (lastUpdated > 0)
            summary += " - updated " + GitHub.relativeTimeFromIso(new Date(lastUpdated).toISOString())
        return summary
    }

    // -- Polling --------------------------------------------------------------
    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        running: root.token !== ""
        repeat: true
        onTriggered: root.fetchNotifications()
    }

    Timer {
        id: viewApplyTimer
        interval: 8
        repeat: true
        onTriggered: root.applyViewChunk()
    }

    function queueViewNotifications(items) {
        var nextItems = (items || []).slice(0)
        pendingViewNotifications = nextItems
        pendingViewIndex = nextItems.length
        notificationsForView = nextItems
        viewApplyTimer.stop()
    }

    function applyViewChunk() {
        viewApplyTimer.stop()
    }

    function cloneExpandedState(state) {
        var copy = {}
        var source = state || {}
        for (var key in source)
            copy[key] = source[key]
        if (copy.__defaultExpanded === undefined)
            copy.__defaultExpanded = true
        return copy
    }

    function cloneAuthorsByThread() {
        var copy = {}
        for (var threadId in authorsByThread)
            copy[threadId] = authorsByThread[threadId]
        return copy
    }

    function cloneAuthorFetchedUrlsByThread() {
        var copy = {}
        for (var threadId in authorFetchedUrlsByThread) {
            var threadCopy = {}
            var source = authorFetchedUrlsByThread[threadId] || {}
            for (var url in source)
                threadCopy[url] = source[url]
            copy[threadId] = threadCopy
        }
        return copy
    }

    function cloneAvatarPreloadMap() {
        var copy = {}
        for (var key in avatarPreloadMap)
            copy[key] = avatarPreloadMap[key]
        return copy
    }

    function cloneThreadFetchedUrlMap(threadId) {
        var source = authorFetchedUrlsByThread[threadId] || {}
        var copy = {}
        for (var url in source)
            copy[url] = source[url]
        return copy
    }

    function markThreadUrlsFetched(threadId, urls) {
        if (!threadId || !urls || urls.length === 0)
            return

        var nextByThread = cloneAuthorFetchedUrlsByThread()
        var nextThreadMap = cloneThreadFetchedUrlMap(threadId)

        for (var index = 0; index < urls.length; index++) {
            var url = normalizeApiUrl(urls[index])
            if (url)
                nextThreadMap[url] = true
        }

        nextByThread[threadId] = nextThreadMap
        authorFetchedUrlsByThread = nextByThread
    }

    function filterThreadUnfetchedUrls(threadId, urls) {
        var result = []
        if (!threadId || !urls || urls.length === 0)
            return result

        var fetchedMap = authorFetchedUrlsByThread[threadId] || {}
        var seen = {}

        for (var index = 0; index < urls.length; index++) {
            var rawUrl = String(urls[index] || "").trim()
            var normalized = normalizeApiUrl(rawUrl)
            if (!normalized || fetchedMap[normalized] || seen[normalized])
                continue
            seen[normalized] = true
            result.push(rawUrl)
        }

        return result
    }

    function defaultAvatarUrlForLogin(login) {
        var normalized = String(login || "").trim()
        if (!normalized)
            return ""
        return "https://github.com/" + encodeURIComponent(normalized) + ".png?size=80"
    }

    function authorAvatarUrl(authorLike) {
        if (!authorLike)
            return ""

        var avatarUrl = String(authorLike.avatarUrl || authorLike.avatar_url || "").trim()
        if (avatarUrl)
            return avatarUrl

        var login = String(authorLike.login || "").trim()
        if (login)
            return defaultAvatarUrlForLogin(login)

        return ""
    }

    function authorKey(login, htmlUrl, avatarUrl) {
        var normalizedLogin = String(login || "").trim().toLowerCase()
        if (normalizedLogin)
            return normalizedLogin

        var normalizedHtml = String(htmlUrl || "").trim()
        if (normalizedHtml)
            return normalizedHtml

        return String(avatarUrl || "").trim()
    }

    function mergeAuthorLists(existingAuthors, incomingAuthors) {
        var merged = []
        var byKey = {}

        var existing = existingAuthors || []
        for (var existingIndex = 0; existingIndex < existing.length; existingIndex++)
            pushAuthorCandidate(merged, byKey, existing[existingIndex])

        var incoming = incomingAuthors || []
        for (var incomingIndex = 0; incomingIndex < incoming.length; incomingIndex++)
            pushAuthorCandidate(merged, byKey, incoming[incomingIndex])

        return merged
    }

    function isLikelyGitHubLogin(login) {
        var value = String(login || "").trim()
        if (!value)
            return false

        // Allow standard GitHub logins and GitHub bot accounts (e.g. dependabot[bot]).
        if (/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/.test(value))
            return true
        if (/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\[bot\]$/.test(value))
            return true

        return false
    }

    function pushAuthorCandidate(target, byKey, userLike) {
        if (!userLike || typeof userLike !== "object")
            return

        var login = String(userLike.login || "").trim()
        if (!isLikelyGitHubLogin(login))
            return

        var avatarUrl = userLike.avatar_url || userLike.avatarUrl || ""
        var htmlUrl = userLike.html_url || userLike.htmlUrl || ""

        htmlUrl = String(htmlUrl || "").trim()
        if (!htmlUrl)
            htmlUrl = "https://github.com/" + encodeURIComponent(login)

        avatarUrl = authorAvatarUrl({
            login: login,
            avatarUrl: avatarUrl
        })

        var key = authorKey(login, htmlUrl, avatarUrl)
        if (!key)
            return

        if (byKey.hasOwnProperty(key)) {
            var existing = target[byKey[key]]
            if (!existing.login && login)
                existing.login = login
            if (!existing.avatarUrl && avatarUrl)
                existing.avatarUrl = avatarUrl
            if (!existing.htmlUrl && htmlUrl)
                existing.htmlUrl = htmlUrl
            return
        }

        byKey[key] = target.length
        target.push({
            login: login,
            avatarUrl: avatarUrl,
            htmlUrl: htmlUrl
        })
    }

    function queueAvatarPreloadFromAuthors(authors) {
        if (!authors || authors.length === 0 || avatarPreloadEntries.length >= avatarPreloadLimit)
            return

        var nextEntries = avatarPreloadEntries.slice(0)
        var nextMap = cloneAvatarPreloadMap()
        var changed = false

        for (var index = 0; index < authors.length; index++) {
            if (nextEntries.length >= avatarPreloadLimit)
                break

            var author = authors[index]
            var login = String((author && author.login) || "").trim()
            var avatarUrl = authorAvatarUrl(author)
            var key = authorKey(login, (author && author.htmlUrl) || "", avatarUrl)
            if (!key || !avatarUrl || nextMap.hasOwnProperty(key))
                continue

            nextMap[key] = avatarUrl
            nextEntries.push({
                key: key,
                source: avatarUrl
            })
            changed = true
        }

        if (changed) {
            avatarPreloadMap = nextMap
            avatarPreloadEntries = nextEntries
        }
    }

    function queueAvatarPreloadFromNotifications(items) {
        if (!items || items.length === 0)
            return

        var ownerAuthors = []
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            ownerAuthors.push({
                login: item.repositoryOwnerLogin || "",
                avatarUrl: item.repositoryOwnerAvatarUrl || "",
                htmlUrl: item.repositoryOwnerLogin ? ("https://github.com/" + encodeURIComponent(item.repositoryOwnerLogin)) : ""
            })
        }

        queueAvatarPreloadFromAuthors(ownerAuthors)
    }

    function parseSubjectAuthors(payloadText) {
        var authors = []
        var byKey = {}
        var parsed

        try {
            parsed = JSON.parse(payloadText || "{}")
        } catch (error) {
            return []
        }

        function walk(value, depth) {
            if (!value || depth > 8)
                return

            if (Array.isArray(value)) {
                for (var arrayIndex = 0; arrayIndex < value.length; arrayIndex++)
                    walk(value[arrayIndex], depth + 1)
                return
            }

            if (typeof value !== "object")
                return

            if (value.login || value.avatar_url || value.avatarUrl || value.html_url || value.htmlUrl)
                pushAuthorCandidate(authors, byKey, value)

            pushAuthorCandidate(authors, byKey, value.user)
            pushAuthorCandidate(authors, byKey, value.author)
            pushAuthorCandidate(authors, byKey, value.assignee)
            pushAuthorCandidate(authors, byKey, value.sender)
            pushAuthorCandidate(authors, byKey, value.creator)
            pushAuthorCandidate(authors, byKey, value.merged_by)
            pushAuthorCandidate(authors, byKey, value.closed_by)
            pushAuthorCandidate(authors, byKey, value.dismissed_by)
            pushAuthorCandidate(authors, byKey, value.actor)

            for (var key in value) {
                if (!value.hasOwnProperty(key))
                    continue
                var child = value[key]
                if (!child || typeof child !== "object")
                    continue
                walk(child, depth + 1)
            }
        }

        walk(parsed, 0)
        return authors
    }

    function parseSubjectAuthorsMulti(payloadText, splitToken) {
        var marker = "\n" + (splitToken || authorSplitToken) + "\n"
        var normalized = String(payloadText || "")
        if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n")
            normalized += "\n"

        var parts = normalized.split(marker)
        var merged = []
        var mergedByKey = {}

        for (var partIndex = 0; partIndex < parts.length; partIndex++) {
            var part = String(parts[partIndex] || "").trim()
            if (!part)
                continue

            var partAuthors = parseSubjectAuthors(part)
            for (var authorIndex = 0; authorIndex < partAuthors.length; authorIndex++)
                pushAuthorCandidate(merged, mergedByKey, partAuthors[authorIndex])
        }

        return merged
    }

    function normalizeApiUrl(url) {
        var normalized = String(url || "").trim()
        if (!normalized)
            return ""

        var queryIndex = normalized.indexOf("?")
        if (queryIndex >= 0)
            normalized = normalized.substring(0, queryIndex)

        if (normalized.indexOf("{") >= 0)
            return ""

        if (normalized.indexOf("https://api.github.com/repos/") !== 0)
            return ""

        return normalized
    }

    function isThreadParentApiUrl(url) {
        var normalized = normalizeApiUrl(url)
        if (!normalized)
            return false

        var parts = normalized.split("/")
        if (parts.length !== 8)
            return false

        if (parts[0] !== "https:" || parts[2] !== "api.github.com" || parts[3] !== "repos")
            return false

        if (parts[6] !== "issues" && parts[6] !== "pulls")
            return false

        return /^[0-9]+$/.test(parts[7])
    }

    function collectSubjectExpansionUrls(value, target, seen, depth) {
        if (!value || depth > 8)
            return

        if (Array.isArray(value)) {
            for (var arrayIndex = 0; arrayIndex < value.length; arrayIndex++)
                collectSubjectExpansionUrls(value[arrayIndex], target, seen, depth + 1)
            return
        }

        if (typeof value !== "object")
            return

        function push(url) {
            var normalized = normalizeApiUrl(url)
            if (!normalized || !isThreadParentApiUrl(normalized) || seen[normalized])
                return
            seen[normalized] = true
            target.push(normalized)
        }

        push(value.issue_url)
        push(value.pull_request_url)
        push(value.url)

        for (var key in value) {
            if (!value.hasOwnProperty(key))
                continue
            var child = value[key]
            if (!child || typeof child !== "object")
                continue
            collectSubjectExpansionUrls(child, target, seen, depth + 1)
        }
    }

    function parseSubjectExpansionUrls(payloadText, splitToken) {
        var marker = "\n" + (splitToken || authorSplitToken) + "\n"
        var normalized = String(payloadText || "")
        if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n")
            normalized += "\n"

        var parts = normalized.split(marker)
        var urls = []
        var seen = {}

        for (var partIndex = 0; partIndex < parts.length; partIndex++) {
            var part = String(parts[partIndex] || "").trim()
            if (!part)
                continue

            var parsed
            try {
                parsed = JSON.parse(part)
            } catch (error) {
                continue
            }

            collectSubjectExpansionUrls(parsed, urls, seen, 0)
        }

        return urls
    }

    function appendAuthorQuery(url, query) {
        if (!url)
            return ""
        return url + (url.indexOf("?") >= 0 ? "&" : "?") + query
    }

    function buildAuthorFetchUrls(subjectApiUrl, subjectType) {
        var urls = []
        var perPageQuery = "per_page=100"

        function push(url) {
            if (!url)
                return
            if (urls.indexOf(url) >= 0)
                return
            urls.push(url)
        }

        push(subjectApiUrl)

        if (isThreadParentApiUrl(subjectApiUrl) && subjectApiUrl.indexOf("/pulls/") >= 0) {
            push(appendAuthorQuery(subjectApiUrl + "/reviews", perPageQuery))
            push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery))
            push(appendAuthorQuery(subjectApiUrl + "/commits", perPageQuery))

            var issueApiUrl = subjectApiUrl.replace("/pulls/", "/issues/")
            push(appendAuthorQuery(issueApiUrl + "/comments", perPageQuery))
            push(appendAuthorQuery(issueApiUrl + "/timeline", perPageQuery))
            push(appendAuthorQuery(issueApiUrl + "/events", perPageQuery))
        }

        if (isThreadParentApiUrl(subjectApiUrl) && subjectApiUrl.indexOf("/issues/") >= 0) {
            push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery))
            push(appendAuthorQuery(subjectApiUrl + "/timeline", perPageQuery))
            push(appendAuthorQuery(subjectApiUrl + "/events", perPageQuery))
        }

        if (subjectApiUrl.indexOf("/discussions/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery))

        if (subjectApiUrl.indexOf("/commits/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery))

        return urls
    }

    function enqueueAuthorUrls(threadId, urls) {
        if (!token || !threadId || !urls || urls.length === 0)
            return

        var candidateUrls = filterThreadUnfetchedUrls(threadId, urls)
        if (candidateUrls.length === 0)
            return

        var pendingMap = {}
        var nextQueue = authorRequestQueue.slice(0)

        for (var queueIndex = 0; queueIndex < nextQueue.length; queueIndex++) {
            var queueItem = nextQueue[queueIndex]
            if (queueItem.threadId !== threadId)
                continue
            var pendingUrls = queueItem.urls || []
            for (var pendingIndex = 0; pendingIndex < pendingUrls.length; pendingIndex++) {
                var pendingKey = normalizeApiUrl(pendingUrls[pendingIndex])
                if (pendingKey)
                    pendingMap[pendingKey] = true
            }
        }

        var filtered = []
        for (var index = 0; index < candidateUrls.length; index++) {
            var url = candidateUrls[index]
            var urlKey = normalizeApiUrl(url)
            if (!urlKey || pendingMap[urlKey])
                continue
            pendingMap[urlKey] = true
            filtered.push(url)
        }

        if (filtered.length === 0)
            return

        nextQueue.push({
            threadId: threadId,
            urls: filtered
        })
        authorRequestQueue = nextQueue
        processAuthorQueue()
    }

    function enqueueAuthorFetch(threadId, subjectApiUrl, subjectType) {
        if (!token || !threadId || !subjectApiUrl)
            return

        enqueueAuthorUrls(threadId, buildAuthorFetchUrls(subjectApiUrl, subjectType || ""))
    }

    function processAuthorQueue() {
        if (authorRequestInFlight || !token)
            return
        if (authorRequestQueue.length === 0)
            return

        var nextQueue = authorRequestQueue.slice(0)
        var request = nextQueue.shift()
        authorRequestQueue = nextQueue

        var urls = filterThreadUnfetchedUrls(request.threadId, request.urls || [])
        if (urls.length === 0) {
            Qt.callLater(root.processAuthorQueue)
            return
        }

        authorRequestInFlight = true
        var process = authorFetchComponent.createObject(root, {
            threadId: request.threadId,
            requestedUrls: urls
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
                "--connect-timeout", "10",
                "--max-time", "20",
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2022-11-28",
                "-H", "Authorization: token " + token,
                "-w", "\n" + authorSplitToken + "\n",
                url
            )
        }

        process.command = command
        process.running = true
    }

    function queueThreadDoneSync(threadIds) {
        if (!threadIds || threadIds.length === 0)
            return

        var nextQueue = pendingThreadDoneQueue.slice(0)
        var seen = {}
        for (var existingIndex = 0; existingIndex < nextQueue.length; existingIndex++)
            seen[nextQueue[existingIndex]] = true

        for (var index = 0; index < threadIds.length; index++) {
            var threadId = threadIds[index]
            if (!threadId || seen[threadId])
                continue
            seen[threadId] = true
            nextQueue.push(threadId)
        }

        pendingThreadDoneQueue = nextQueue
        processPendingThreadDoneQueue()
    }

    function processPendingThreadDoneQueue() {
        if (!token || isMutating || isLoading)
            return
        if (pendingThreadDoneQueue.length === 0)
            return

        var nextQueue = pendingThreadDoneQueue.slice(0)
        var threadId = nextQueue.shift()
        pendingThreadDoneQueue = nextQueue

        runMutation(
            "DELETE",
            "https://api.github.com/notifications/threads/" + threadId,
            "thread_done_sync",
            threadId,
            "",
            ""
        )
    }

    onPollIntervalMsChanged: {
        pollTimer.interval = pollIntervalMs
        if (pollTimer.running)
            pollTimer.restart()
    }

    onTokenChanged: {
        if (!token) {
            notifications = []
            notificationsForView = []
            pendingViewNotifications = []
            pendingViewIndex = 0
            viewApplyTimer.stop()
            unreadCount = 0
            errorMessage = ""
            lastUpdated = 0
            fetchQueued = false
            parseRequestSeq = parseRequestSeq + 1
            isLoading = false
            pendingThreadDoneQueue = []
            authorRequestQueue = []
            authorRequestInFlight = false
            authorFetchedUrlsByThread = ({})
            authorsByThread = ({})
            avatarPreloadEntries = []
            avatarPreloadMap = ({})
            expandedReposState = ({ "__defaultExpanded": true })
            return
        }
        fetchNotifications()
    }

    onGroupItemLimitChanged: {
        if (token)
            fetchNotifications()
    }

    onFetchPageCountChanged: {
        if (token)
            fetchNotifications()
    }

    Component.onCompleted: {
        if (token)
            fetchNotifications()
    }

    WorkerScript {
        id: parseWorker
        source: Qt.resolvedUrl("../JS/NotificationParserWorker.js")

        onMessage: function(message) {
            if (message.seq !== root.parseRequestSeq)
                return

            if (message.error) {
                root.isLoading = false
                root.notifications = []
                root.notificationsForView = []
                root.pendingViewNotifications = []
                root.pendingViewIndex = 0
                root.authorsByThread = ({})
                root.authorRequestQueue = []
                root.authorRequestInFlight = false
                root.authorFetchedUrlsByThread = ({})
                viewApplyTimer.stop()
                root.unreadCount = 0
                root.errorMessage = message.error
                root.lastUpdated = Date.now()
                Qt.callLater(root.processPendingThreadDoneQueue)
                if (root.fetchQueued) {
                    root.fetchQueued = false
                    Qt.callLater(root.fetchNotifications)
                }
                return
            }

            if (message.phase === "begin") {
                root.notifications = []
                root.notificationsForView = []
                root.pendingViewNotifications = []
                root.pendingViewIndex = 0
                root.authorsByThread = ({})
                root.authorRequestQueue = []
                root.authorRequestInFlight = false
                root.authorFetchedUrlsByThread = ({})
                root.unreadCount = parseInt(message.unreadCount || 0)
                root.errorMessage = ""
                root.lastUpdated = Date.now()
                root.isLoading = true

                if (parseInt(message.totalCount || 0) === 0) {
                    root.isLoading = false
                    if (root.fetchQueued) {
                        root.fetchQueued = false
                        Qt.callLater(root.fetchNotifications)
                    }
                }
                return
            }

            if (message.phase === "chunk") {
                var chunk = message.items || []
                if (chunk.length > 0) {
                    var nextNotifications = root.notifications.slice(0)
                    for (var index = 0; index < chunk.length; index++)
                        nextNotifications.push(chunk[index])
                    root.notifications = nextNotifications
                    root.notificationsForView = nextNotifications
                    root.queueAvatarPreloadFromNotifications(chunk)
                }

                if (message.isLast) {
                    root.isLoading = false
                    root.lastUpdated = Date.now()
                    Qt.callLater(root.processPendingThreadDoneQueue)
                    if (root.fetchQueued) {
                        root.fetchQueued = false
                        Qt.callLater(root.fetchNotifications)
                    }
                }
                return
            }

            root.isLoading = false
            root.notifications = message.items || []
            root.unreadCount = parseInt(message.unreadCount || 0)
            root.queueViewNotifications(root.notifications)
            root.queueAvatarPreloadFromNotifications(root.notifications)
            root.errorMessage = ""
            root.lastUpdated = Date.now()

            if (root.fetchQueued) {
                root.fetchQueued = false
                Qt.callLater(root.fetchNotifications)
            }
        }
    }

    // -- Process-based API calls ----------------------------------------------
    Component {
        id: fetchComponent

        Process {
            property var _chunks: []

            stdout: SplitParser {
                onRead: line => _chunks.push(line)
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[GitHubInbox] fetch:", line)
                }
            }

            onExited: exitCode => {
                if (exitCode !== 0) {
                    root.isLoading = false
                    root.errorMessage = "Request failed. Check token or network."
                    if (root.fetchQueued) {
                        root.fetchQueued = false
                        Qt.callLater(root.fetchNotifications)
                    }
                    destroy()
                    return
                }

                var nextSeq = root.parseRequestSeq + 1
                root.parseRequestSeq = nextSeq
                parseWorker.sendMessage({
                    seq: nextSeq,
                    payloadText: _chunks.join("\n") + "\n",
                    separator: root.fetchSplitToken,
                    allSegmentCount: root.fetchPageCount,
                    doneThreadState: root.doneThreadState,
                    chunkSize: 80
                })

                destroy()
            }
        }
    }

    Component {
        id: authorFetchComponent

        Process {
            property string threadId: ""
            property var requestedUrls: []
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
                root.markThreadUrlsFetched(threadId, requestedUrls || [])

                var fetchedAuthors = []
                if (exitCode === 0)
                    fetchedAuthors = root.parseSubjectAuthorsMulti(_buffer, root.authorSplitToken)

                var nextAuthors = root.cloneAuthorsByThread()
                var existingAuthors = nextAuthors[threadId] || []
                var mergedAuthors = root.mergeAuthorLists(existingAuthors, fetchedAuthors)
                nextAuthors[threadId] = mergedAuthors
                root.authorsByThread = nextAuthors
                root.queueAvatarPreloadFromAuthors(mergedAuthors)

                if (exitCode === 0) {
                    var expansionRoots = root.parseSubjectExpansionUrls(_buffer, root.authorSplitToken)
                    if (expansionRoots.length > 0) {
                        var expansionUrls = []
                        for (var rootIndex = 0; rootIndex < expansionRoots.length; rootIndex++) {
                            var parentUrl = expansionRoots[rootIndex]
                            var builtUrls = root.buildAuthorFetchUrls(parentUrl, "")
                            for (var urlIndex = 0; urlIndex < builtUrls.length; urlIndex++)
                                expansionUrls.push(builtUrls[urlIndex])
                        }
                        root.enqueueAuthorUrls(threadId, expansionUrls)
                    }
                }

                root.authorRequestInFlight = false
                Qt.callLater(root.processAuthorQueue)
                destroy()
            }
        }
    }

    Component {
        id: mutationComponent

        Process {
            property string _buffer: ""
            property string actionType: "thread_read"   // thread_read | thread_done | repo_read | all_read
            property string threadId: ""
            property string repositoryFullName: ""

            stdout: SplitParser {
                onRead: line => _buffer += line
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[GitHubInbox] mutate:", line)
                }
            }

            onExited: exitCode => {
                root.isMutating = false

                if (exitCode !== 0) {
                    root.errorMessage = "Action failed. Check token permissions."
                    destroy()
                    return
                }

                var statusCode = parseInt((_buffer || "").trim())
                if (!isNaN(statusCode) && statusCode >= 200 && statusCode < 300) {
                    root.applyMutationResult(actionType, threadId, repositoryFullName)
                    root.errorMessage = ""
                    root.lastUpdated = Date.now()
                } else {
                    root.errorMessage = "Action failed (HTTP " + (isNaN(statusCode) ? "?" : statusCode) + ")."
                }

                Qt.callLater(root.processPendingThreadDoneQueue)
                destroy()
            }
        }
    }

    function fetchNotifications() {
        if (!token || isMutating)
            return

        if (isLoading) {
            fetchQueued = true
            return
        }

        isLoading = true
        errorMessage = ""

        // Canonical data source from GitHub:
        // - full inbox (all=true)
        // - participation subset (all=true&participating=true)
        // We derive participation locally from the subset to avoid ambiguous participating=false behavior.
        var apiPageSize = 50
        var pages = Math.max(1, fetchPageCount)
        var baseQuery = "per_page=" + apiPageSize + "&all=true"
        var allBaseUrl = "https://api.github.com/notifications?" + baseQuery
        var participatingBaseUrl = allBaseUrl + "&participating=true"
        var command = ["curl"]

        function appendRequest(url) {
            if (command.length > 1)
                command.push("--next")
            command.push(
                "-sS",
                "--connect-timeout", "10",
                "--max-time", "20",
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2022-11-28",
                "-H", "Authorization: token " + token,
                "-w", "\n" + root.fetchSplitToken + "\n",
                url
            )
        }

        for (var page = 1; page <= pages; page++)
            appendRequest(allBaseUrl + "&page=" + page)

        for (var partPage = 1; partPage <= pages; partPage++)
            appendRequest(participatingBaseUrl + "&page=" + partPage)

        var process = fetchComponent.createObject(root)
        process.command = command
        process.running = true
    }

    function runMutation(method, url, actionType, threadId, repositoryFullName, payloadJson) {
        if (!token || isMutating || isLoading)
            return

        isMutating = true

        var process = mutationComponent.createObject(root, {
            actionType: actionType || "thread_read",
            threadId: threadId || "",
            repositoryFullName: repositoryFullName || ""
        })
        process.command = [
            "curl",
            "-sS",
            "-o", "/dev/null",
            "-w", "%{http_code}",
            "--connect-timeout", "10",
            "--max-time", "20",
            "-X", method,
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            "-H", "Authorization: token " + token,
            url
        ]
        if (payloadJson) {
            process.command.splice(process.command.length - 1, 0, "-H", "Content-Type: application/json", "-d", payloadJson)
        }
        process.running = true
    }

    function refreshNow() {
        if (!token) {
            errorMessage = "Set your GitHub token in Settings."
            return
        }
        fetchNotifications()
    }

    function _markAsReadItem(item) {
        var copy = {}
        for (var key in item)
            copy[key] = item[key]
        copy.unread = false
        return copy
    }

    function applyMutationResult(actionType, threadId, repositoryFullName) {
        var updated = []
        var doneCopy = {}
        for (var doneKey in doneThreadState) doneCopy[doneKey] = doneThreadState[doneKey]

        if (actionType === "thread_done_sync")
            return

        if (actionType === "all_read") {
            for (var allIndex = 0; allIndex < notifications.length; allIndex++)
                updated.push(_markAsReadItem(notifications[allIndex]))
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = 0
            return
        }

        if (actionType === "repo_read") {
            for (var repoIndex = 0; repoIndex < notifications.length; repoIndex++) {
                var repoItem = notifications[repoIndex]
                if (repoItem.repository === repositoryFullName) {
                    updated.push(_markAsReadItem(repoItem))
                    continue
                }
                updated.push(repoItem)
            }
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = recalculateUnread(updated)
            return
        }

        if (actionType === "thread_done") {
            doneCopy[threadId] = true
            doneThreadState = doneCopy
            for (var doneIndex = 0; doneIndex < notifications.length; doneIndex++) {
                var doneItem = notifications[doneIndex]
                if (doneItem.threadId !== threadId)
                    updated.push(doneItem)
            }
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = recalculateUnread(updated)
            return
        }

        if (actionType === "thread_unread") {
            if (doneCopy[threadId]) {
                delete doneCopy[threadId]
                doneThreadState = doneCopy
            }
            for (var unreadIndex = 0; unreadIndex < notifications.length; unreadIndex++) {
                var unreadItem = notifications[unreadIndex]
                if (unreadItem.threadId === threadId) {
                    var unreadCopy = {}
                    for (var unreadKey in unreadItem)
                        unreadCopy[unreadKey] = unreadItem[unreadKey]
                    unreadCopy.unread = true
                    updated.push(unreadCopy)
                    continue
                }
                updated.push(unreadItem)
            }
            notifications = updated
            queueViewNotifications(notifications)
            unreadCount = recalculateUnread(updated)
            return
        }

        // actionType === "thread_read"
        if (doneCopy[threadId]) {
            delete doneCopy[threadId]
            doneThreadState = doneCopy
        }
        for (var index = 0; index < notifications.length; index++) {
            var item = notifications[index]
            if (item.threadId === threadId) {
                var readCopy = _markAsReadItem(item)
                updated.push(readCopy)
                continue
            }
            updated.push(item)
        }

        notifications = updated
        queueViewNotifications(notifications)
        unreadCount = recalculateUnread(updated)
    }

    function recalculateUnread(items) {
        var count = 0
        for (var index = 0; index < items.length; index++) {
            if (items[index].unread)
                count++
        }
        return count
    }

    function markThreadAsRead(threadId) {
        if (!threadId)
            return
        runMutation(
            "PATCH",
            "https://api.github.com/notifications/threads/" + threadId,
            "thread_read",
            threadId,
            "",
            ""
        )
    }

    function markThreadAsUnread(threadId) {
        if (!threadId)
            return
        runMutation(
            "PATCH",
            "https://api.github.com/notifications/threads/" + threadId,
            "thread_unread",
            threadId,
            "",
            "{\"read\":false}"
        )
    }

    function markThreadDone(threadId) {
        if (!threadId)
            return
        runMutation(
            "DELETE",
            "https://api.github.com/notifications/threads/" + threadId,
            "thread_done",
            threadId,
            "",
            ""
        )
    }

    function markRepoDone(repositoryFullName) {
        if (!repositoryFullName)
            return

        var doneCopy = {}
        for (var doneKey in doneThreadState)
            doneCopy[doneKey] = doneThreadState[doneKey]

        var updated = []
        var threadIds = []

        for (var index = 0; index < notifications.length; index++) {
            var item = notifications[index]
            if (item.repository === repositoryFullName && item.threadId) {
                doneCopy[item.threadId] = true
                threadIds.push(item.threadId)
                continue
            }
            updated.push(item)
        }

        if (threadIds.length === 0)
            return

        doneThreadState = doneCopy
        notifications = updated
        queueViewNotifications(notifications)
        unreadCount = recalculateUnread(updated)
        queueThreadDoneSync(threadIds)
    }

    function markRepoAsRead(repositoryFullName) {
        if (!repositoryFullName)
            return

        var parts = repositoryFullName.split("/")
        if (parts.length !== 2)
            return

        var owner = encodeURIComponent(parts[0])
        var repo = encodeURIComponent(parts[1])
        runMutation(
            "PUT",
            "https://api.github.com/repos/" + owner + "/" + repo + "/notifications",
            "repo_read",
            "",
            repositoryFullName,
            ""
        )
    }

    function markAllAsRead() {
        runMutation(
            "PUT",
            "https://api.github.com/notifications",
            "all_read",
            "",
            "",
            ""
        )
    }

    Item {
        id: avatarPreloadHost
        visible: false
        width: 0
        height: 0

        Repeater {
            model: root.avatarPreloadEntries

            delegate: Image {
                required property var modelData
                source: modelData.source || ""
                asynchronous: true
                cache: true
                sourceSize.width: 48
                sourceSize.height: 48
                visible: false
            }
        }
    }

    // =======================================================================
    //  BAR PILLS
    // =======================================================================

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            GitHubIcon {
                size: Math.max(12, root.iconSize - 4)
                iconOpacity: 0.74
                sourcePrimary: root.githubIconPrimary
                sourceFallback: root.githubIconFallback
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
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
                size: Math.max(12, root.iconSize - 4)
                iconOpacity: 0.74
                sourcePrimary: root.githubIconPrimary
                sourceFallback: root.githubIconFallback
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.barCountText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // =======================================================================
    //  POPOUT
    // =======================================================================

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

                notifications: root.notificationsForView
                unreadCount: root.unreadCount
                tokenConfigured: root.token !== ""
                isLoading: root.isLoading
                isMutating: root.isMutating
                errorMessage: root.errorMessage
                headerOffset: popout.headerHeight + popout.detailsHeight
                titleLines: root.titleLines
                groupItemLimit: root.groupItemLimit
                expandedReposState: root.expandedReposState
                authorsByThread: root.authorsByThread

                onRefreshNow: root.refreshNow()
                onMarkAllRead: root.markAllAsRead()
                onMarkRepoDone: function(repositoryFullName) { root.markRepoDone(repositoryFullName) }
                onMarkThreadRead: function(threadId) { root.markThreadAsRead(threadId) }
                onMarkThreadUnread: function(threadId) { root.markThreadAsUnread(threadId) }
                onMarkThreadDone: function(threadId) { root.markThreadDone(threadId) }
                onRequestThreadAuthors: function(threadId, subjectApiUrl, subjectType) {
                    root.enqueueAuthorFetch(threadId, subjectApiUrl, subjectType)
                }
                onClosePopout: root.closePopout()
                onPersistExpandedRepos: function(state) { root.expandedReposState = root.cloneExpandedState(state) }
            }
        }
    }

    popoutWidth: 560
    popoutHeight: {
        var items = Math.max(1, popupItems)
        var rowHeight = 40 + titleLines * 16
        var estimatedRepoHeaders = Math.max(1, Math.ceil(items / 3))
        var estimated = (items * rowHeight) + (estimatedRepoHeaders * 30) + 130
        return Math.max(240, Math.min(1000, estimated))
    }
}
