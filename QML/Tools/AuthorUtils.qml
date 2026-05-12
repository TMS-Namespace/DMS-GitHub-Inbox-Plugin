// AuthorUtils.qml - Pure helper functions for author data processing
//
// Contains URL normalization, author validation, merge logic, and URL building.
// These are stateless utility functions used by AuthorBackgroundWorker and Widget.

pragma Singleton

import QtQuick
import ".."

QtObject {

    // =========================================================================
    //  URL Normalization
    // =========================================================================

    function normalizeApiUrl(url) {
        var normalized = String(url || "").trim()
        if (!normalized)
            return ""

        var queryIndex = normalized.indexOf("?")
        if (queryIndex >= 0)
            normalized = normalized.substring(0, queryIndex)

        if (normalized.indexOf("{") >= 0)
            return ""

        if (normalized.indexOf(GitHubConstants.githubApiReposPrefix) !== 0)
            return ""

        return normalized
    }

    function apiUrlFromWebUrl(webUrl) {
        var normalized = String(webUrl || "").trim()
        if (!normalized || normalized.indexOf(GitHubConstants.githubWebBaseUrl + "/") !== 0)
            return ""

        var pathOnly = normalized.split("#")[0].split("?")[0]
        var path = pathOnly.substring((GitHubConstants.githubWebBaseUrl + "/").length)
        var parts = path.split("/")
        if (parts.length < 4)
            return ""

        var owner = parts[0]
        var repo = parts[1]
        var section = parts[2]
        var subjectId = parts[3]
        if (!owner || !repo || !section || !subjectId)
            return ""

        if (section === "pull")
            section = "pulls"

        if (section === "issues" || section === "pulls" || section === "discussions") {
            if (!/^[0-9]+$/.test(subjectId))
                return ""
            return GitHubConstants.githubApiReposPrefix
                   + encodeURIComponent(owner) + "/"
                   + encodeURIComponent(repo) + "/"
                   + section + "/" + subjectId
        }

        if (section === "commit")
            return GitHubConstants.githubApiReposPrefix
                   + encodeURIComponent(owner) + "/"
                   + encodeURIComponent(repo) + "/commits/" + subjectId

        return ""
    }

    function resolveSubjectApiUrlForAuthors(item) {
        if (!item)
            return ""

        var directUrl = normalizeApiUrl(item.subjectApiUrl || "")
        if (directUrl)
            return directUrl

        var fromWeb = normalizeApiUrl(apiUrlFromWebUrl(item.webUrl || ""))
        if (fromWeb)
            return fromWeb

        return buildCiApiUrl(item.repository || "", item.subjectType || "")
    }

    function buildCiApiUrl(repoFullName, subjectType) {
        if (!repoFullName)
            return ""
        var normalizedType = String(subjectType || "").toLowerCase()
        if (normalizedType !== "checksuite" && normalizedType !== "workflowrun")
            return ""
        return GitHubConstants.githubApiReposPrefix + repoFullName + "/actions/runs"
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

    function appendAuthorQuery(url, query) {
        if (!url)
            return ""
        return url + (url.indexOf("?") >= 0 ? "&" : "?") + query
    }

    // =========================================================================
    //  Author Fetch URL Building
    // =========================================================================

    function buildAuthorFetchUrls(subjectApiUrl, subjectType, includeDetails) {
        var urls = []
        var perPageQuery = GitHubConstants.authorFetchPerPageQuery

        function push(url) {
            if (!url || urls.indexOf(url) >= 0)
                return
            urls.push(url)
        }

        push(subjectApiUrl)

        if (includeDetails === false)
            return urls

        if (isThreadParentApiUrl(subjectApiUrl)) {
            var isPR = subjectApiUrl.indexOf("/pulls/") >= 0
            var issueApiUrl = isPR
                ? subjectApiUrl.replace("/pulls/", "/issues/")
                : subjectApiUrl

            if (isPR)
                push(appendAuthorQuery(subjectApiUrl + "/reviews", perPageQuery))

            push(appendAuthorQuery(issueApiUrl + "/timeline", perPageQuery))
        }

        if (subjectApiUrl.indexOf("/discussions/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery))

        if (subjectApiUrl.indexOf("/commits/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery))

        if (subjectApiUrl.indexOf("/check-suites/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/check-runs", perPageQuery))

        if (subjectApiUrl.indexOf("/actions/runs") >= 0
                && subjectApiUrl.indexOf("/actions/runs/") < 0)
            push(appendAuthorQuery(subjectApiUrl, "per_page=5"))

        if (subjectApiUrl.indexOf("/actions/runs/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/jobs", perPageQuery))

        return urls
    }

    // =========================================================================
    //  Subject Expansion URL Parsing
    // =========================================================================

    function collectSubjectExpansionUrls(value, target, seen) {
        if (!value || typeof value !== "object")
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
    }

    function parseSubjectExpansionUrls(payloadText, splitToken) {
        var marker = "\n" + splitToken + "\n"
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

            if (Array.isArray(parsed)) {
                for (var itemIndex = 0; itemIndex < parsed.length; itemIndex++)
                    collectSubjectExpansionUrls(parsed[itemIndex], urls, seen)
            } else {
                collectSubjectExpansionUrls(parsed, urls, seen)
            }
        }

        return urls
    }

    // =========================================================================
    //  Author Validation & Key Building
    // =========================================================================

    function defaultAvatarUrlForLogin(login) {
        var normalized = String(login || "").trim()
        if (!normalized)
            return ""
        return GitHubConstants.githubAvatarsBaseUrl + "/" + encodeURIComponent(normalized)
               + "?size=" + GitHubConstants.avatarDefaultSizePx
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

    function isLikelyGitHubLogin(login) {
        var value = String(login || "").trim()
        if (!value)
            return false

        var base = value
        if (base.slice(-5) === "[bot]")
            base = base.slice(0, -5)

        return /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9])?$/.test(base)
    }

    function isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl) {
        if (!userLike || typeof userLike !== "object")
            return false

        var normalizedLogin = String(login || "").trim()
        if (!isLikelyGitHubLogin(normalizedLogin))
            return false

        var normalizedType = String(userLike.type || "").trim().toLowerCase()
        if (normalizedType === "user"
                || normalizedType === "bot"
                || normalizedType === "organization"
                || normalizedType === "mannequin")
            return true

        var normalizedAvatar = String(avatarUrl || "").trim().toLowerCase()
        if (normalizedAvatar.indexOf("https://avatars.githubusercontent.com/") === 0)
            return true
        if (normalizedAvatar.indexOf(GitHubConstants.githubWebBaseUrl + "/") === 0
                && normalizedAvatar.indexOf(".png") > 0)
            return true

        var normalizedHtml = String(htmlUrl || "").trim().toLowerCase()
        var lowerLogin = normalizedLogin.toLowerCase()
        if (normalizedHtml === GitHubConstants.githubWebBaseUrl + "/" + lowerLogin)
            return true
        if (normalizedHtml.indexOf(GitHubConstants.githubWebBaseUrl + "/" + lowerLogin + "/") === 0)
            return true

        return false
    }

    // =========================================================================
    //  Author List Operations
    // =========================================================================

    function pushAuthorCandidate(target, byKey, userLike) {
        if (!userLike || typeof userLike !== "object")
            return

        var login = String(userLike.login || "").trim()
        var avatarUrl = userLike.avatar_url || userLike.avatarUrl || ""
        var htmlUrl = userLike.html_url || userLike.htmlUrl || ""
        if (!isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl))
            return

        htmlUrl = String(htmlUrl || "").trim()
        if (!htmlUrl)
            htmlUrl = GitHubConstants.githubWebBaseUrl + "/" + encodeURIComponent(login)

        avatarUrl = authorAvatarUrl({ login: login, avatarUrl: avatarUrl })

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

    // =========================================================================
    //  Author Parsing from API Responses
    // =========================================================================

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
            if (!value || depth > GitHubConstants.authorWalkMaxDepth)
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
        var marker = "\n" + splitToken + "\n"
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
}
