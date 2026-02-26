// GitHubHelpers.js - utility helpers for GitHub Inbox plugin
//
// Usage:
//   import "../JS/GitHubHelpers.js" as GitHub

function pluginDataBool(value, defaultValue) {
    if (value === undefined || value === "")
        return !!defaultValue
    if (typeof value === "boolean")
        return value
    var normalized = String(value).toLowerCase()
    return normalized === "true" || normalized === "1" || normalized === "yes"
}

function pollIntervalMs(value) {
    var seconds = parseInt(value || "120")
    if (isNaN(seconds) || seconds < 30)
        return 120000
    return seconds * 1000
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
    var unreadCount = 0

    for (var index = 0; index < payload.length; index++) {
        var item = payload[index]
        var subject = item.subject || {}
        var repository = item.repository || {}
        var unread = !!item.unread

        if (unread)
            unreadCount++

        items.push({
            threadId: item.id || "",
            unread: unread,
            reason: item.reason || "",
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

    // Keep unread items first, then most recently updated.
    items.sort(function(a, b) {
        if (a.unread !== b.unread)
            return a.unread ? -1 : 1
        var tA = Date.parse(a.updatedAt) || 0
        var tB = Date.parse(b.updatedAt) || 0
        return tB - tA
    })

    return {
        items: items,
        unreadCount: unreadCount
    }
}

function parseNotificationsWithParticipation(payloadText, separator) {
    var splitToken = separator || "__GH_PARTICIPATING_SPLIT__"
    var marker = "\n" + splitToken + "\n"
    var splitIndex = payloadText.indexOf(marker)

    // Backward compatibility: if only one payload is present, parse normally.
    if (splitIndex < 0) {
        var single = parseNotificationsPayload(payloadText)
        if (single.error)
            return single
        for (var singleIndex = 0; singleIndex < single.items.length; singleIndex++)
            single.items[singleIndex].participated = false
        return single
    }

    var allText = payloadText.substring(0, splitIndex)
    var participatingText = payloadText.substring(splitIndex + marker.length)

    var allParsed = parseNotificationsPayload(allText)
    if (allParsed.error)
        return allParsed

    var participatingParsed = parseNotificationsPayload(participatingText)
    if (participatingParsed.error)
        return participatingParsed

    var participationMap = {}
    for (var partIndex = 0; partIndex < participatingParsed.items.length; partIndex++) {
        var partItem = participatingParsed.items[partIndex]
        if (partItem.threadId)
            participationMap[partItem.threadId] = true
    }

    for (var allIndex = 0; allIndex < allParsed.items.length; allIndex++) {
        var allItem = allParsed.items[allIndex]
        allItem.participated = !!participationMap[allItem.threadId]
    }

    return allParsed
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
        return { items: [], unreadCount: 0 }

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
    var unreadCount = 0
    for (var threadId in allItemsByThread) {
        var mergedItem = allItemsByThread[threadId]
        mergedItem.participated = !!participationMap[threadId]
        if (mergedItem.unread)
            unreadCount++
        mergedItems.push(mergedItem)
    }

    mergedItems.sort(function(a, b) {
        if (a.unread !== b.unread)
            return a.unread ? -1 : 1
        var tA = Date.parse(a.updatedAt) || 0
        var tB = Date.parse(b.updatedAt) || 0
        return tB - tA
    })

    return {
        items: mergedItems,
        unreadCount: unreadCount
    }
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

function relativeTimeFromIso(isoDate) {
    if (!isoDate)
        return ""

    var timestamp = Date.parse(isoDate)
    if (isNaN(timestamp))
        return ""

    var seconds = Math.floor((Date.now() - timestamp) / 1000)
    if (seconds < 10)
        return "just now"
    if (seconds < 60)
        return seconds + " sec ago"

    var minutes = Math.floor(seconds / 60)
    if (minutes < 60)
        return minutes + " min ago"

    var hours = Math.floor(minutes / 60)
    if (hours < 24)
        return hours + " hr ago"

    var days = Math.floor(hours / 24)
    if (days < 30)
        return days + " day" + (days !== 1 ? "s" : "") + " ago"

    var months = Math.floor(days / 30)
    if (months < 12)
        return months + " month" + (months !== 1 ? "s" : "") + " ago"

    var years = Math.floor(days / 365)
    return years + " year" + (years !== 1 ? "s" : "") + " ago"
}

function reasonLabel(reason) {
    if (!reason)
        return "activity"
    return String(reason).replace(/_/g, " ")
}

function formatCountValue(value) {
    var safe = Math.max(0, parseInt(value || 0))
    if (safe > 999)
        return "999+"
    return String(safe)
}

function formatBarCount(unreadCount, totalCount, includeRead) {
    var unread = Math.max(0, parseInt(unreadCount || 0))
    var total = Math.max(0, parseInt(totalCount || 0))
    var read = Math.max(0, total - unread)

    if (includeRead)
        return formatCountValue(unread) + "/" + formatCountValue(read) + "/" + formatCountValue(total)
    return formatCountValue(unread) + "/" + formatCountValue(total)
}

function subjectIconName(subjectType) {
    var type = String(subjectType || "").toLowerCase()

    if (type === "pullrequest")
        return "call_split"
    if (type === "issue")
        return "error_outline"
    if (type === "discussion")
        return "forum"
    if (type === "release")
        return "new_releases"
    if (type === "commit")
        return "account_tree"
    if (type === "repositoryvulnerabilityalert"
            || type === "repositoryadvisory"
            || type === "repositorydependabotalert"
            || type === "vulnerabilityalert"
            || type === "dependabotalert"
            || type === "codescanningalert")
        return "shield"
    if (type === "checksuite")
        return "fact_check"

    return "notifications"
}
