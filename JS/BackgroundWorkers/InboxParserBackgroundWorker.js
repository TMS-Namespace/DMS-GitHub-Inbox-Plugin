// InboxParserBackgroundWorker.js - background parser for GitHub inbox messages

// Local mirrors of QML/Constants.qml values.
// WorkerScript files cannot access QML singletons; constants are inlined here.
var _FETCH_PAYLOAD_SPLIT_TOKEN = "__GH_PARTICIPATING_SPLIT__"
var _MESSAGES_PARSE_CHUNK_SIZE = 40
var _GITHUB_INBOX_FALLBACK_URL = "https://github.com/notifications"
var _AVATAR_DEFAULT_SIZE_PX = 128

WorkerScript.onMessage = function (message) {
    // ---- Author JSON parsing (offloaded from Widget.qml main thread) -------
    if (message.action === "parseAuthors") {
        var authors = []
        var expansionUrls = []
        var subjectWebUrl = ""
        if (message.buffer) {
            authors = parseSubjectAuthorsMulti(message.buffer, message.splitToken || "")
            subjectWebUrl = parseSubjectWebUrlMulti(
                message.buffer,
                message.splitToken || "",
                message.subjectTitle || "",
                message.updatedAt || ""
            )
            if (message.shouldExpand)
                expansionUrls = parseSubjectExpansionUrls(message.buffer, message.splitToken || "")
        }
        WorkerScript.sendMessage({
            action: "authorsResult",
            generation: message.generation || 0,
            threadId: message.threadId || "",
            updatedAt: message.updatedAt || "",
            requestedUrls: message.requestedUrls || [],
            shouldExpand: !!message.shouldExpand,
            fallbackAuthor: message.fallbackAuthor || null,
            authors: authors,
            subjectWebUrl: subjectWebUrl,
            expansionUrls: expansionUrls
        })
        return
    }
    // -----------------------------------------------------------------------
    try {
        var parsed = parseMessagesWithParticipationSegments(
            message.payloadText || "",
            message.separator || _FETCH_PAYLOAD_SPLIT_TOKEN,
            message.allSegmentCount || 1
        )

        if (parsed.error) {
            WorkerScript.sendMessage({
                seq: message.seq || 0,
                error: parsed.error
            })
            return
        }

        var doneState = message.doneThreadState || {}
        var filtered = []
        var unread = 0

        for (var index = 0; index < parsed.items.length; index++) {
            var item = parsed.items[index]
            if (doneState[item.threadId])
                continue
            item.participated = !!item.participated
            if (item.unread)
                unread++
            filtered.push(item)
        }

        var seq = message.seq || 0
        var chunkSize = parseInt(message.chunkSize || _MESSAGES_PARSE_CHUNK_SIZE)
        if (isNaN(chunkSize) || chunkSize < 20)
            chunkSize = _MESSAGES_PARSE_CHUNK_SIZE

        WorkerScript.sendMessage({
            seq: seq,
            phase: "begin",
            unreadCount: unread,
            totalCount: filtered.length
        })

        if (filtered.length === 0) {
            WorkerScript.sendMessage({
                seq: seq,
                phase: "chunk",
                items: [],
                isLast: true
            })
            return
        }

        for (var offset = 0; offset < filtered.length; offset += chunkSize) {
            var end = Math.min(filtered.length, offset + chunkSize)
            WorkerScript.sendMessage({
                seq: seq,
                phase: "chunk",
                items: filtered.slice(offset, end),
                isLast: end >= filtered.length
            })
        }
    } catch (error) {
        WorkerScript.sendMessage({
            seq: message.seq || 0,
            error: "Failed to parse inbox messages payload."
        })
    }
}

function parseMessagesWithParticipationSegments(payloadText, separator, allSegmentCount) {
    var splitToken = separator || "__GH_PARTICIPATING_SPLIT__"
    var marker = "\n" + splitToken + "\n"
    var normalizedPayload = String(payloadText || "")
    if (normalizedPayload.length > 0 && normalizedPayload.charAt(normalizedPayload.length - 1) !== "\n")
        normalizedPayload += "\n"
    var chunks = normalizedPayload.split(marker)
    var segments = []

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        var chunk = String(chunks[chunkIndex] || "").trim()
        if (chunk.length > 0)
            segments.push(chunk)
    }

    if (segments.length === 0)
        return { items: [] }

    var count = parseInt(allSegmentCount || 1)
    if (isNaN(count) || count < 1)
        count = 1

    var expectedSegmentCount = count * 2
    if (segments.length < expectedSegmentCount) {
        return {
            error: "GitHub returned an incomplete notification response."
        }
    }

    var allSegments = segments.slice(0, Math.min(count, segments.length))
    var participatingSegments = segments.slice(Math.min(count, segments.length))

    var allItemsByThread = {}
    var participationMap = {}

    for (var allIndex = 0; allIndex < allSegments.length; allIndex++) {
        var allParsed = parseMessagesPayload(allSegments[allIndex])
        if (allParsed.error)
            return allParsed
        for (var allItemIndex = 0; allItemIndex < allParsed.items.length; allItemIndex++) {
            var allItem = allParsed.items[allItemIndex]
            if (!allItem.threadId)
                continue
            if (!allItemsByThread[allItem.threadId])
                allItemsByThread[allItem.threadId] = allItem
        }
    }

    for (var partIndex = 0; partIndex < participatingSegments.length; partIndex++) {
        var partParsed = parseMessagesPayload(participatingSegments[partIndex])
        if (partParsed.error)
            return partParsed
        for (var partItemIndex = 0; partItemIndex < partParsed.items.length; partItemIndex++) {
            var partItem = partParsed.items[partItemIndex]
            if (partItem.threadId)
                participationMap[partItem.threadId] = true
        }
    }

    var mergedItems = []
    for (var threadId in allItemsByThread) {
        var mergedItem = allItemsByThread[threadId]
        mergedItem.participated = mergedItem.participated || !!participationMap[threadId]
        mergedItems.push(mergedItem)
    }

    mergedItems.sort(function (a, b) {
        if (a.unread !== b.unread)
            return a.unread ? -1 : 1
        var tA = a.updatedAtMs || 0
        var tB = b.updatedAtMs || 0
        return tB - tA
    })

    return { items: mergedItems }
}

function parseMessagesPayload(payloadText) {
    var payload
    try {
        payload = JSON.parse(payloadText || "[]")
    } catch (error) {
        return { error: "GitHub returned invalid JSON." }
    }

    if (!Array.isArray(payload)) {
        if (payload && payload.message)
            return { error: payload.message }
        return { error: "Unexpected GitHub response format." }
    }

    var items = []
    for (var index = 0; index < payload.length; index++) {
        var item = payload[index]
        var subject = item.subject || {}
        var repository = item.repository || {}

        var reason = item.reason || ""
        var updatedAt = item.updated_at || ""
        var participatingReasons = {
            comment: true, author: true, assign: true,
            review_requested: true, mention: true, team_mention: true
        }

        items.push({
            threadId: item.id || "",
            unread: !!item.unread,
            reason: reason,
            participated: !!participatingReasons[reason],
            updatedAt: updatedAt,
            updatedAtMs: Date.parse(updatedAt) || 0,
            repository: repository.full_name || "",
            repositoryUrl: repository.html_url || "",
            repositoryOwnerLogin: (repository.owner && repository.owner.login) || "",
            repositoryOwnerAvatarUrl: (repository.owner && repository.owner.avatar_url) || "",
            subjectType: subject.type || "Message",
            title: subject.title || "(untitled)",
            subjectApiUrl: subject.url || "",
            webUrl: resolveWebUrl(item),
            webUrlResolved: false
        })
    }

    return { items: items }
}

function resolveWebUrl(notification) {
    if (!notification)
        return _GITHUB_INBOX_FALLBACK_URL

    var subject = notification.subject || {}
    var apiUrl = subject.url || ""
    var converted = apiToWebUrl(apiUrl, subject.type || "", subject.title || "")
    if (converted)
        return converted

    var repository = notification.repository || {}
    if (repository.html_url)
        return repository.html_url

    return _GITHUB_INBOX_FALLBACK_URL
}

function apiToWebUrl(apiUrl, subjectType, subjectTitle) {
    if (!apiUrl || apiUrl.indexOf("https://api.github.com/repos/") !== 0)
        return ""

    var path = apiUrl.substring("https://api.github.com/repos/".length)
    var parts = path.split("/")
    if (parts.length < 2)
        return ""

    var owner = parts[0]
    var repo = parts[1]
    var base = "https://github.com/" + owner + "/" + repo
    var tail = parts.slice(2)

    if (tail.length >= 2 && tail[0] === "issues")
        return base + "/issues/" + tail[1]
    if (tail.length >= 2 && tail[0] === "pulls")
        return base + "/pull/" + tail[1]
    if (tail.length >= 2 && tail[0] === "commits")
        return base + "/commit/" + tail[1]
    if (tail.length >= 3 && tail[0] === "actions" && tail[1] === "runs")
        return base + "/actions/runs/" + tail[2]
    if (tail.length >= 2 && tail[0] === "check-runs")
        return base + "/runs/" + tail[1]
    if (tail.length >= 2 && tail[0] === "check-suites")
        return base + "/actions"
    if (tail.length >= 2 && tail[0] === "statuses")
        return base + "/commit/" + tail[1]
    if (tail.length >= 2 && tail[0] === "discussions")
        return base + "/discussions/" + tail[1]
    if (tail.length >= 3 && tail[0] === "releases" && tail[1] === "tags")
        return base + "/releases/tag/" + encodeURIComponent(tail.slice(2).join("/"))
    if (tail.length >= 2 && tail[0] === "releases") {
        return base + "/releases"
    }
    if (tail.length >= 3 && tail[0] === "dependabot" && tail[1] === "alerts")
        return base + "/security/dependabot/" + tail[2]
    if (tail.length >= 2 && tail[0] === "security-advisories")
        return base + "/security/advisories/" + tail[1]
    if (tail.length >= 3 && tail[0] === "code-scanning" && tail[1] === "alerts")
        return base + "/security/code-scanning/" + tail[2]

    return base
}

// ---- Author parsing helpers (mirror of Widget.qml, runs in worker thread) --

function defaultAvatarUrlForLogin(login) {
    var normalized = String(login || "").trim()
    if (!normalized) return ""
    return "https://avatars.githubusercontent.com/" + encodeURIComponent(normalized) + "?size=" + _AVATAR_DEFAULT_SIZE_PX
}

function authorAvatarUrl(authorLike) {
    if (!authorLike) return ""
    var avatarUrl = String(authorLike.avatarUrl || authorLike.avatar_url || "").trim()
    if (avatarUrl) return avatarUrl
    var htmlUrl = String(authorLike.htmlUrl || authorLike.html_url || "").trim()
    if (isGitHubAppUrl(htmlUrl)) return htmlUrl + ".png?size=" + _AVATAR_DEFAULT_SIZE_PX
    var login = String(authorLike.login || "").trim()
    if (login) return defaultAvatarUrlForLogin(login)
    return ""
}

function appSlugFromHtmlUrl(htmlUrl) {
    var normalized = String(htmlUrl || "").trim()
    var prefix = "https://github.com/apps/"
    if (normalized.indexOf(prefix) !== 0) return ""
    var slug = normalized.substring(prefix.length).split(/[/?#]/)[0]
    return String(slug || "").trim()
}

function isGitHubAppUrl(htmlUrl) {
    return appSlugFromHtmlUrl(htmlUrl) !== ""
}

function authorKey(login, htmlUrl, avatarUrl) {
    var normalizedLogin = String(login || "").trim().toLowerCase()
    if (normalizedLogin) return normalizedLogin
    var normalizedHtml = String(htmlUrl || "").trim()
    if (normalizedHtml) return normalizedHtml
    return String(avatarUrl || "").trim()
}

function isLikelyGitHubLogin(login) {
    var value = String(login || "").trim()
    if (!value) return false
    var base = value
    if (base.slice(-5) === "[bot]") base = base.slice(0, -5)
    return /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9])?$/.test(base)
}

function isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl) {
    if (!userLike || typeof userLike !== "object") return false
    var normalizedLogin = String(login || "").trim()
    if (!isLikelyGitHubLogin(normalizedLogin)) return false
    var normalizedType = String(userLike.type || "").trim().toLowerCase()
    if (normalizedType === "user" || normalizedType === "bot" ||
        normalizedType === "app" ||
        normalizedType === "organization" || normalizedType === "mannequin")
        return true
    var normalizedAvatar = String(avatarUrl || "").trim().toLowerCase()
    if (normalizedAvatar.indexOf("https://avatars.githubusercontent.com/") === 0) return true
    if (normalizedAvatar.indexOf("https://github.com/") === 0 && normalizedAvatar.indexOf(".png") > 0) return true
    var normalizedHtml = String(htmlUrl || "").trim().toLowerCase()
    var lowerLogin = normalizedLogin.toLowerCase()
    if (appSlugFromHtmlUrl(normalizedHtml) === lowerLogin) return true
    if (normalizedHtml === "https://github.com/" + lowerLogin) return true
    if (normalizedHtml.indexOf("https://github.com/" + lowerLogin + "/") === 0) return true
    return false
}

function pushAuthorCandidate(target, byKey, userLike) {
    if (!userLike || typeof userLike !== "object") return
    var htmlUrl = userLike.html_url || userLike.htmlUrl || ""
    var login = String(userLike.login || userLike.slug || appSlugFromHtmlUrl(htmlUrl) || "").trim()
    var avatarUrl = userLike.avatar_url || userLike.avatarUrl || ""
    if (!isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl)) return
    htmlUrl = String(htmlUrl || "").trim()
    if (!htmlUrl && String(userLike.slug || "").trim())
        htmlUrl = "https://github.com/apps/" + encodeURIComponent(String(userLike.slug).trim())
    if (!htmlUrl) htmlUrl = "https://github.com/" + encodeURIComponent(login)
    avatarUrl = authorAvatarUrl({ login: login, avatarUrl: avatarUrl, htmlUrl: htmlUrl })
    var key = authorKey(login, htmlUrl, avatarUrl)
    if (!key) return
    if (byKey.hasOwnProperty(key)) {
        var existing = target[byKey[key]]
        if (!existing.login && login) existing.login = login
        if (!existing.avatarUrl && avatarUrl) existing.avatarUrl = avatarUrl
        if (!existing.htmlUrl && htmlUrl) existing.htmlUrl = htmlUrl
        return
    }
    byKey[key] = target.length
    target.push({ login: login, avatarUrl: avatarUrl, htmlUrl: htmlUrl })
}

function parseSubjectAuthors(payloadText) {
    var authors = []
    var byKey = {}
    var parsed
    try { parsed = JSON.parse(payloadText || "{}") } catch (e) { return [] }

    function walk(value, depth) {
        if (!value || depth > 8) return
        if (Array.isArray(value)) {
            for (var i = 0; i < value.length; i++) walk(value[i], depth + 1)
            return
        }
        if (typeof value !== "object") return
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
        for (var k in value) {
            if (!value.hasOwnProperty(k)) continue
            var child = value[k]
            if (!child || typeof child !== "object") continue
            walk(child, depth + 1)
        }
    }
    walk(parsed, 0)
    return authors
}

function parseSubjectAuthorsMulti(payloadText, splitToken) {
    var marker = "\n" + (splitToken || "") + "\n"
    var normalized = String(payloadText || "")
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n")
        normalized += "\n"
    var parts = normalized.split(marker)
    var merged = []
    var mergedByKey = {}
    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim()
        if (!part) continue
        var partAuthors = parseSubjectAuthors(part)
        for (var j = 0; j < partAuthors.length; j++)
            pushAuthorCandidate(merged, mergedByKey, partAuthors[j])
    }
    return merged
}

function normalizeApiUrlWorker(url) {
    var normalized = String(url || "").trim()
    if (!normalized) return ""
    var qi = normalized.indexOf("?")
    if (qi >= 0) normalized = normalized.substring(0, qi)
    if (normalized.indexOf("{") >= 0) return ""
    if (normalized.indexOf("https://api.github.com/repos/") !== 0) return ""
    return normalized
}

function isThreadParentApiUrlWorker(url) {
    var normalized = normalizeApiUrlWorker(url)
    if (!normalized) return false
    var parts = normalized.split("/")
    if (parts.length !== 8) return false
    if (parts[0] !== "https:" || parts[2] !== "api.github.com" || parts[3] !== "repos") return false
    if (parts[6] !== "issues" && parts[6] !== "pulls") return false
    return /^[0-9]+$/.test(parts[7])
}

function collectSubjectExpansionUrlsWorker(value, target, seen) {
    if (!value || typeof value !== "object") return
    function push(url) {
        var normalized = normalizeApiUrlWorker(url)
        if (!normalized || !isThreadParentApiUrlWorker(normalized) || seen[normalized]) return
        seen[normalized] = true
        target.push(normalized)
    }
    push(value.issue_url)
    push(value.pull_request_url)
    push(value.url)
}

function parseSubjectExpansionUrls(payloadText, splitToken) {
    var marker = "\n" + (splitToken || "") + "\n"
    var normalized = String(payloadText || "")
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n")
        normalized += "\n"
    var parts = normalized.split(marker)
    var urls = []
    var seen = {}
    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim()
        if (!part) continue
        var parsed
        try { parsed = JSON.parse(part) } catch (e) { continue }
        if (Array.isArray(parsed)) {
            for (var j = 0; j < parsed.length; j++)
                collectSubjectExpansionUrlsWorker(parsed[j], urls, seen)
        } else {
            collectSubjectExpansionUrlsWorker(parsed, urls, seen)
        }
    }
    return urls
}

function parseSubjectWebUrlMulti(payloadText, splitToken, subjectTitle, updatedAt) {
    var marker = "\n" + (splitToken || "") + "\n"
    var normalized = String(payloadText || "")
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n")
        normalized += "\n"
    var parts = normalized.split(marker)
    var best = { score: -1, url: "" }

    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim()
        if (!part) continue
        var parsed
        try { parsed = JSON.parse(part) } catch (e) { continue }

        var directUrl = directSubjectWebUrlFromObject(parsed)
        if (directUrl)
            return directUrl

        best = chooseBestActionRunUrl(parsed, subjectTitle, updatedAt, best)
    }

    return best.url || ""
}

function directSubjectWebUrlFromObject(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return ""

    var subjectWebUrl = String(value.subjectWebUrl || value.subject_web_url || "").trim()
    if (subjectWebUrl)
        return subjectWebUrl

    var tagName = String(value.tagName || value.tag_name || "").trim()
    var htmlUrl = String(value.htmlUrl || value.html_url || "").trim()
    if (tagName && htmlUrl)
        return htmlUrl
    if (htmlUrl && isLikelySubjectObject(value))
        return htmlUrl

    if (value.release && typeof value.release === "object")
        return directSubjectWebUrlFromObject(value.release)

    return ""
}

function isLikelySubjectObject(value) {
    if (!value || typeof value !== "object")
        return false
    if (value.url || value.node_id || value.id || value.number || value.sha)
        return true
    if (value.tag_name || value.name || value.title || value.state)
        return true
    return false
}

function chooseBestActionRunUrl(value, subjectTitle, updatedAt, currentBest) {
    var best = currentBest || { score: -1, url: "" }
    var runs = []

    if (value && typeof value === "object") {
        if (value.actionRunUrl)
            return { score: 1000000, url: String(value.actionRunUrl) }
        if (Array.isArray(value.actionRuns))
            runs = runs.concat(value.actionRuns)
        if (Array.isArray(value.workflow_runs))
            runs = runs.concat(value.workflow_runs)
    }

    var expectedName = workflowNameFromNotificationTitle(subjectTitle)
    var expectedBranch = branchFromNotificationTitle(subjectTitle)
    var expectedConclusion = conclusionFromNotificationTitle(subjectTitle)
    var expectedTime = Date.parse(updatedAt || "") || 0

    for (var index = 0; index < runs.length; index++) {
        var run = runs[index] || {}
        var url = String(run.htmlUrl || run.html_url || "").trim()
        if (!url)
            continue

        var score = 0
        var runName = String(run.name || "").trim()
        var displayTitle = String(run.displayTitle || run.display_title || "").trim()
        var headBranch = String(run.headBranch || run.head_branch || "").trim()
        var conclusion = String(run.conclusion || "").trim().toLowerCase()

        if (expectedName) {
            if (runName.toLowerCase() === expectedName.toLowerCase())
                score += 100
            else if (displayTitle.toLowerCase().indexOf(expectedName.toLowerCase()) >= 0)
                score += 40
            else
                score -= 100
        }

        if (expectedBranch) {
            if (headBranch === expectedBranch)
                score += 100
            else
                score -= 100
        }

        if (expectedConclusion) {
            if (conclusion === expectedConclusion)
                score += 50
            else
                score -= 40
        }

        var runTime = Date.parse(run.updatedAt || run.updated_at || "") || 0
        if (expectedTime && runTime) {
            var deltaMinutes = Math.abs(runTime - expectedTime) / 60000
            if (deltaMinutes <= 10)
                score += 40
            else if (deltaMinutes <= 120)
                score += 20
            else
                score -= Math.min(40, Math.floor(deltaMinutes / 60))
        } else {
            score += Math.max(0, runs.length - index)
        }

        if (score > best.score)
            best = { score: score, url: url }
    }

    return best
}

function workflowNameFromNotificationTitle(title) {
    var match = String(title || "").match(/^(.+?) workflow run/i)
    return match ? match[1].trim() : ""
}

function branchFromNotificationTitle(title) {
    var match = String(title || "").match(/ for (.+) branch$/i)
    return match ? match[1].trim() : ""
}

function conclusionFromNotificationTitle(title) {
    var normalized = String(title || "").toLowerCase()
    if (normalized.indexOf(" failed ") >= 0)
        return "failure"
    if (normalized.indexOf(" succeeded ") >= 0)
        return "success"
    if (normalized.indexOf(" cancelled ") >= 0 || normalized.indexOf(" canceled ") >= 0)
        return "cancelled"
    if (normalized.indexOf(" skipped ") >= 0)
        return "skipped"
    return ""
}
