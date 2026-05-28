// GitHubHelpers.js - utility helpers for GitHub Inbox plugin
//
// Usage:
//   import "../JS/GitHubHelpers.js" as GitHub

// Local mirrors of QML/Constants.qml values.
// This file uses .pragma library and cannot importScripts, so constants are inlined here.
var _DEFAULT_POLL_INTERVAL_SECONDS = 120
var _MIN_POLL_INTERVAL_SECONDS = 60
var _UNREAD_COUNT_DISPLAY_MAX = 999
var _GITHUB_INBOX_FALLBACK_URL = "https://github.com/notifications"

function pluginDataBool(value, defaultValue) {
    if (value === undefined || value === "")
        return !!defaultValue
    if (typeof value === "boolean")
        return value
    var normalized = String(value).toLowerCase()
    return normalized === "true" || normalized === "1" || normalized === "yes"
}

function pollIntervalMs(value) {
    var seconds = parseInt(value || String(_DEFAULT_POLL_INTERVAL_SECONDS))
    if (isNaN(seconds) || seconds < _MIN_POLL_INTERVAL_SECONDS)
        return _DEFAULT_POLL_INTERVAL_SECONDS * 1000
    return seconds * 1000
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
    var unreadCount = 0

    for (var index = 0; index < payload.length; index++) {
        var item = payload[index]
        var subject = item.subject || {}
        var repository = item.repository || {}
        var unread = !!item.unread

        if (unread)
            unreadCount++

        var reason = item.reason || ""
        var participatingReasons = {
            comment: true, author: true, assign: true,
            review_requested: true, mention: true, team_mention: true
        }

        items.push({
            threadId: item.id || "",
            unread: unread,
            reason: reason,
            participated: !!participatingReasons[reason],
            updatedAt: item.updated_at || "",
            repository: repository.full_name || "",
            repositoryUrl: repository.html_url || "",
            repositoryOwnerLogin: (repository.owner && repository.owner.login) || "",
            repositoryOwnerAvatarUrl: (repository.owner && repository.owner.avatar_url) || "",
            subjectType: subject.type || "Message",
            title: subject.title || "(untitled)",
            subjectApiUrl: subject.url || "",
            webUrl: resolveWebUrl(item)
        })
    }

    // Keep unread items first, then most recently updated.
    items.sort(function (a, b) {
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

function parseMessagesWithParticipation(payloadText, separator) {
    var splitToken = separator || "__GH_PARTICIPATING_SPLIT__"
    var marker = "\n" + splitToken + "\n"
    var splitIndex = payloadText.indexOf(marker)

    // Backward compatibility: if only one payload is present, parse normally.
    if (splitIndex < 0) {
        var single = parseMessagesPayload(payloadText)
        if (single.error)
            return single
        for (var singleIndex = 0; singleIndex < single.items.length; singleIndex++)
            single.items[singleIndex].participated = false
        return single
    }

    var allText = payloadText.substring(0, splitIndex)
    var participatingText = payloadText.substring(splitIndex + marker.length)

    var allParsed = parseMessagesPayload(allText)
    if (allParsed.error)
        return allParsed

    var participatingParsed = parseMessagesPayload(participatingText)
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
        return { items: [], unreadCount: 0 }

    var count = parseInt(allSegmentCount || 1)
    if (isNaN(count) || count < 1)
        count = 1

    var expectedSegmentCount = count * 2
    if (segments.length < expectedSegmentCount)
        return { error: "GitHub returned an incomplete notification response." }

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
    var unreadCount = 0
    for (var threadId in allItemsByThread) {
        var mergedItem = allItemsByThread[threadId]
        mergedItem.participated = !!participationMap[threadId]
        if (mergedItem.unread)
            unreadCount++
        mergedItems.push(mergedItem)
    }

    mergedItems.sort(function (a, b) {
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

    var now = new Date()
    var updated = new Date(timestamp)
    var calendarDays = localDayNumber(now) - localDayNumber(updated)
    var days = Math.max(1, calendarDays || Math.floor(hours / 24))
    if (days < 30)
        return days + " day" + (days !== 1 ? "s" : "") + " ago"

    var months = Math.floor(days / 30)
    if (months < 12)
        return months + " month" + (months !== 1 ? "s" : "") + " ago"

    var years = Math.floor(days / 365)
    return years + " year" + (years !== 1 ? "s" : "") + " ago"
}

function localDayNumber(value) {
    return Math.floor(Date.UTC(value.getFullYear(), value.getMonth(), value.getDate())
                      / (24 * 60 * 60 * 1000))
}

function reasonLabel(reason) {
    if (!reason)
        return "Activity"

    var normalized = String(reason).trim().toLowerCase()
    var labels = {
        assign: "Assigned",
        author: "Author",
        ci_activity: "CI Activity",
        comment: "Comment",
        manual: "Manual",
        mention: "Mention",
        review_requested: "Review Requested",
        security_alert: "Security Alert",
        state_change: "State Change",
        subscribed: "Subscribed",
        team_mention: "Team Mention"
    }
    if (labels[normalized])
        return labels[normalized]

    var words = normalized.replace(/_/g, " ").split(" ")
    for (var index = 0; index < words.length; index++) {
        if (!words[index])
            continue
        words[index] = words[index].charAt(0).toUpperCase() + words[index].substring(1)
    }
    return words.join(" ")
}

function formatCountValue(value) {
    var safe = Math.max(0, parseInt(value || 0))
    if (safe > _UNREAD_COUNT_DISPLAY_MAX)
        return _UNREAD_COUNT_DISPLAY_MAX + "+"
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
