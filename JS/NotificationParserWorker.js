// NotificationParserWorker.js - background parser for GitHub notifications

WorkerScript.onMessage = function(message) {
    try {
        var parsed = parseNotificationsWithParticipationSegments(
            message.payloadText || "",
            message.separator || "__GH_PARTICIPATING_SPLIT__",
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
        var chunkSize = parseInt(message.chunkSize || 80)
        if (isNaN(chunkSize) || chunkSize < 20)
            chunkSize = 80

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
            error: "Failed to parse notifications payload."
        })
    }
}

function parseNotificationsWithParticipationSegments(payloadText, separator, allSegmentCount) {
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

    var allSegments = segments.slice(0, Math.min(count, segments.length))
    var participatingSegments = segments.slice(Math.min(count, segments.length))

    var allItemsByThread = {}
    var participationMap = {}

    for (var allIndex = 0; allIndex < allSegments.length; allIndex++) {
        var allParsed = parseNotificationsPayload(allSegments[allIndex])
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
        var partParsed = parseNotificationsPayload(participatingSegments[partIndex])
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

    mergedItems.sort(function(a, b) {
        if (a.unread !== b.unread)
            return a.unread ? -1 : 1
        var tA = Date.parse(a.updatedAt) || 0
        var tB = Date.parse(b.updatedAt) || 0
        return tB - tA
    })

    return { items: mergedItems }
}

function parseNotificationsPayload(payloadText) {
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
        var participatingReasons = {
            comment: true, author: true, assign: true,
            review_requested: true, mention: true, team_mention: true
        }

        items.push({
            threadId: item.id || "",
            unread: !!item.unread,
            reason: reason,
            participated: !!participatingReasons[reason],
            updatedAt: item.updated_at || "",
            repository: repository.full_name || "",
            repositoryUrl: repository.html_url || "",
            repositoryOwnerLogin: (repository.owner && repository.owner.login) || "",
            repositoryOwnerAvatarUrl: (repository.owner && repository.owner.avatar_url) || "",
            subjectType: subject.type || "Notification",
            title: subject.title || "(untitled)",
            subjectApiUrl: subject.url || "",
            webUrl: resolveWebUrl(item)
        })
    }

    return { items: items }
}

function resolveWebUrl(notification) {
    if (!notification)
        return "https://github.com/notifications"

    var subject = notification.subject || {}
    var apiUrl = subject.url || ""
    var converted = apiToWebUrl(apiUrl, subject.type || "", subject.title || "")
    if (converted)
        return converted

    var repository = notification.repository || {}
    if (repository.html_url)
        return repository.html_url

    return "https://github.com/notifications"
}

function releaseTagFromSubject(subjectType, subjectTitle) {
    var normalizedType = String(subjectType || "").toLowerCase()
    if (normalizedType !== "release")
        return ""

    var title = String(subjectTitle || "").trim()
    if (!title)
        return ""

    title = title.replace(/^release\s+/i, "").trim()
    return title
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
    if (tail.length >= 2 && tail[0] === "discussions")
        return base + "/discussions/" + tail[1]
    if (tail.length >= 2 && tail[0] === "releases") {
        var releaseTag = releaseTagFromSubject(subjectType, subjectTitle)
        if (releaseTag)
            return base + "/releases/tag/" + encodeURIComponent(releaseTag)
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
