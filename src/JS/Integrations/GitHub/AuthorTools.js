// AuthorTools.js - pure participant normalization and bounded GitHub author endpoint planning.
// Receives a JavaScript facade and plain declarations; never accesses QML or shared state.

.pragma library

// Construct stateless author operations using validated provider declarations.
function create(providerApi, properties, perPageQuery) {
    // Convert recognized GitHub subject links into validated API endpoints.
    function apiUrlFromWebUrl(webUrl) {
        let normalized = String(webUrl || "").trim();

        if (!providerApi || !normalized || normalized.indexOf(properties.webBaseUrl + "/") !== 0) return "";

        let pathOnly = normalized.split("#")[0].split("?")[0];
        let path = pathOnly.substring((properties.webBaseUrl + "/").length);
        let parts = path.split("/");
        if (parts.length < 4) return "";

        let owner = parts[0];
        let repo = parts[1];
        let section = parts[2];
        let subjectId = parts[3];
        if (!owner || !repo || !section || !subjectId) return "";

        if (section === "pull") section = "pulls";

        if (section === "issues" || section === "pulls" || section === "discussions") {
            if (!/^[0-9]+$/.test(subjectId)) return "";
            return providerApi.buildRepositoryApiUrl(owner + "/" + repo, section + "/" + subjectId);
        }

        if (section === "commit") return providerApi.buildRepositoryApiUrl(owner + "/" + repo, "commits/" + subjectId);

        if (section === "actions" && subjectId === "runs" && parts.length >= 5) {
            let runId = parts[4];
            if (!/^[0-9]+$/.test(runId)) return "";
            return providerApi.buildRepositoryApiUrl(owner + "/" + repo, "actions/runs/" + runId);
        }

        return "";
    }
    // Read the app slug only from the declared GitHub app URL prefix.
    function appSlugFromHtmlUrl(htmlUrl) {
        let normalized = String(htmlUrl || "").trim();
        let prefix = properties.webBaseUrl + "/apps/";
        if (normalized.indexOf(prefix) !== 0) return "";

        let slug = normalized.substring(prefix.length).split(/[/?#]/)[0];
        return String(slug || "").trim();
    }
    // Append query options without dropping an endpoint's existing query string.
    function appendAuthorQuery(url, query) {
        if (!url) return "";
        return url + (url.indexOf("?") >= 0 ? "&" : "?") + query;
    }
    // Choose a validated avatar URL, falling back to the app or account endpoint.
    function authorAvatarUrl(authorLike) {
        if (!authorLike) return "";

        let avatarUrl = String(authorLike.avatarUrl || authorLike.avatar_url || "").trim();

        if (avatarUrl && providerApi && providerApi.isAllowedAvatarUrl(avatarUrl)) return avatarUrl;

        let htmlUrl = String(authorLike.htmlUrl || authorLike.html_url || "").trim();
        if (isGitHubAppUrl(htmlUrl)) {
            let appAvatarUrl = providerApi.buildAppAvatarUrl(appSlugFromHtmlUrl(htmlUrl));
            return appAvatarUrl;
        }

        let login = String(authorLike.login || "").trim();
        if (login) return defaultAvatarUrlForLogin(login);

        return "";
    }
    // Deduplicate accounts by login, falling back to their profile or avatar URL.
    function authorKey(login, htmlUrl, avatarUrl) {
        let normalizedLogin = String(login || "")
            .trim()
            .toLowerCase();
        if (normalizedLogin) return normalizedLogin;

        let normalizedHtml = String(htmlUrl || "").trim();
        if (normalizedHtml) return normalizedHtml;

        return String(avatarUrl || "").trim();
    }

    // =========================================================================
    //  Author Fetch URL Building
    // =========================================================================

    // Plan subject and optional timeline endpoints without duplicate requests.
    function buildAuthorFetchUrls(subjectApiUrl, subjectType, includeDetails, reason) {
        let urls = [];

        // Deduplicate a candidate before adding it to the bounded result set.
        function push(url) {
            if (!url || urls.indexOf(url) >= 0) return;
            urls.push(url);
        }

        let threadParentUrl = isThreadParentApiUrl(subjectApiUrl);
        push(subjectApiUrl);

        if (includeDetails === false) return urls;

        if (threadParentUrl) {
            let isPR = subjectApiUrl.indexOf("/pulls/") >= 0;
            let issueApiUrl = isPR ? subjectApiUrl.replace("/pulls/", "/issues/") : subjectApiUrl;

            push(appendAuthorQuery(issueApiUrl + "/timeline", perPageQuery));
        }

        if (subjectApiUrl.indexOf("/discussions/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery));

        if (subjectApiUrl.indexOf("/commits/") >= 0) push(appendAuthorQuery(subjectApiUrl + "/comments", perPageQuery));

        if (subjectApiUrl.indexOf("/check-suites/") >= 0) {
            push(appendAuthorQuery(subjectApiUrl + "/check-runs", perPageQuery));
            let checkSuiteRepoRunsUrl = repoActionsRunsUrlFromSubjectApiUrl(subjectApiUrl);
            if (checkSuiteRepoRunsUrl) push(appendAuthorQuery(checkSuiteRepoRunsUrl, "per_page=5"));
        }

        if (subjectApiUrl.indexOf("/actions/runs") >= 0 && subjectApiUrl.indexOf("/actions/runs/") < 0)
            push(appendAuthorQuery(subjectApiUrl, "per_page=5"));

        if (subjectApiUrl.indexOf("/actions/runs/") >= 0)
            push(appendAuthorQuery(subjectApiUrl + "/jobs", perPageQuery));

        return urls;
    }
    // Build the repository workflow endpoint only for recognized CI subject types.
    function buildCiApiUrl(repoFullName, subjectType) {
        if (!repoFullName) return "";
        let normalizedType = String(subjectType || "").toLowerCase();
        if (normalizedType !== "checksuite" && normalizedType !== "workflowrun") return "";

        return providerApi ? providerApi.buildRepositoryApiUrl(repoFullName, "actions/runs") : "";
    }

    // =========================================================================
    //  Subject Expansion URL Parsing
    // =========================================================================

    // Collect distinct issue and pull-request roots from recognized response fields.
    function collectSubjectExpansionUrls(value, target, seen) {
        if (!value || typeof value !== "object") return;
        // Deduplicate a candidate before adding it to the bounded result set.
        function push(url) {
            let normalized = normalizeApiUrl(url);
            if (!normalized || !isThreadParentApiUrl(normalized) || seen[normalized]) return;
            seen[normalized] = true;
            target.push(normalized);
        }

        push(value.issue_url);
        push(value.pull_request_url);
        push(value.url);
    }

    // =========================================================================
    //  Author Validation & Key Building
    // =========================================================================

    // Delegate account avatar URL validation to the provider facade.
    function defaultAvatarUrlForLogin(login) {
        return providerApi ? providerApi.buildAvatarUrl(login) : "";
    }
    // Recognize app profiles using the declared GitHub URL prefix.
    function isGitHubAppUrl(htmlUrl) {
        return appSlugFromHtmlUrl(htmlUrl) !== "";
    }
    // Reject unsupported account names before constructing account URLs.
    function isLikelyGitHubLogin(login) {
        let value = String(login || "").trim();
        if (!value) return false;

        let base = value;
        if (base.slice(-5) === "[bot]") base = base.slice(0, -5);

        return /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9])?$/.test(base);
    }
    // Accept account-like actors while excluding repository organizations.
    function isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl) {
        if (!userLike || typeof userLike !== "object") return false;

        let normalizedLogin = String(login || "").trim();
        if (!isLikelyGitHubLogin(normalizedLogin)) return false;

        let normalizedType = String(userLike.type || "")
            .trim()
            .toLowerCase();
        if (
            normalizedType === "user" ||
            normalizedType === "bot" ||
            normalizedType === "app" ||
            normalizedType === "mannequin"
        )
            return true;
        if (normalizedType === "organization") return false;

        let normalizedAvatar = String(avatarUrl || "")
            .trim()
            .toLowerCase();
        if (providerApi && providerApi.isAllowedAvatarUrl(normalizedAvatar)) return true;

        let normalizedHtml = String(htmlUrl || "")
            .trim()
            .toLowerCase();
        let lowerLogin = normalizedLogin.toLowerCase();
        if (appSlugFromHtmlUrl(normalizedHtml) === lowerLogin) return true;
        if (normalizedHtml === properties.webBaseUrl + "/" + lowerLogin) return true;
        if (normalizedHtml.indexOf(properties.webBaseUrl + "/" + lowerLogin + "/") === 0) return true;

        return false;
    }
    // Recognize the worker's author envelope before traversing raw API data.
    function isPreExtractedAuthorPayload(value) {
        return (
            value &&
            typeof value === "object" &&
            !Array.isArray(value) &&
            Array.isArray(value.authors) &&
            (value.hasOwnProperty("subjectWebUrl") ||
                value.hasOwnProperty("actionRuns") ||
                value.hasOwnProperty("release"))
        );
    }
    // Recognize validated issue and pull-request root endpoints.
    function isThreadParentApiUrl(url) {
        let normalized = normalizeApiUrl(url);
        if (!normalized) return false;

        let parts = normalized.split("/");
        if (parts.length !== 8) return false;

        if (parts[0] !== "https:" || parts[2] !== "api.github.com" || parts[3] !== "repos") return false;

        if (parts[6] !== "issues" && parts[6] !== "pulls") return false;

        return /^[0-9]+$/.test(parts[7]);
    }
    // Merge existing and incoming participants in order, keeping each account once.
    function mergeAuthorLists(existingAuthors, incomingAuthors) {
        let merged = [];
        let byKey = {};

        let existing = existingAuthors || [];
        for (let existingIndex = 0; existingIndex < existing.length; existingIndex++)
            pushAuthorCandidate(merged, byKey, existing[existingIndex]);

        let incoming = incomingAuthors || [];
        for (let incomingIndex = 0; incomingIndex < incoming.length; incomingIndex++)
            pushAuthorCandidate(merged, byKey, incoming[incomingIndex]);

        return merged;
    }

    // =========================================================================
    //  URL Normalization
    // =========================================================================

    // Strip request options and reject endpoints outside the provider allowlist.
    function normalizeApiUrl(url) {
        let normalized = String(url || "").trim();
        if (!normalized) return "";

        let queryIndex = normalized.indexOf("?");
        if (queryIndex >= 0) normalized = normalized.substring(0, queryIndex);

        if (!providerApi || !providerApi.isAllowedApiUrl(normalized)) return "";

        return normalized;
    }

    // =========================================================================
    //  Author Parsing from API Responses
    // =========================================================================

    // Extract recognized actor fields without including repository owners.
    function parseSubjectAuthors(payloadText) {
        let authors = [];
        let byKey = {};
        let parsed;

        try {
            parsed = JSON.parse(payloadText || "{}");
        } catch (error) {
            // Optional author sections may be missing or invalid; keep other participants and the message usable.
            return [];
        }

        if (isPreExtractedAuthorPayload(parsed)) {
            for (let extractedIndex = 0; extractedIndex < parsed.authors.length; extractedIndex++)
                pushAuthorCandidate(authors, byKey, parsed.authors[extractedIndex]);
            return authors;
        }

        // Accept either a candidate object or a list without losing individual authors.
        function pushAuthorValue(value) {
            if (!value) return;
            if (Array.isArray(value)) {
                for (let arrayIndex = 0; arrayIndex < value.length; arrayIndex++) pushAuthorValue(value[arrayIndex]);
                return;
            }

            pushAuthorCandidate(authors, byKey, value);
        }

        // Read only recognized actor fields instead of treating every nested user as an author.
        function collectFromNode(value) {
            if (typeof value !== "object") return;
            if (value.triggering_actor) pushAuthorValue(value.triggering_actor);
            else pushAuthorValue(value.actor);

            pushAuthorValue(value.user);
            pushAuthorValue(value.author);
            pushAuthorValue(value.sender);
            pushAuthorValue(value.creator);
            pushAuthorValue(value.merged_by);
            pushAuthorValue(value.closed_by);
            pushAuthorValue(value.dismissed_by);
        }

        // Bound recursive author discovery so deeply nested responses cannot monopolize the worker.
        function walk(value, depth) {
            if (!value || depth > 4) return;
            if (Array.isArray(value)) {
                for (let arrayIndex = 0; arrayIndex < value.length; arrayIndex++) walk(value[arrayIndex], depth + 1);
                return;
            }

            if (typeof value !== "object") return;
            collectFromNode(value);

            for (let key in value) {
                if (!value.hasOwnProperty(key)) continue;
                if (
                    key === "owner" ||
                    key === "repository" ||
                    key === "repo" ||
                    key === "head_repository" ||
                    key === "base_repository" ||
                    key === "head_repo" ||
                    key === "base_repo"
                )
                    continue;
                let child = value[key];
                if (!child || typeof child !== "object") continue;
                walk(child, depth + 1);
            }
        }

        walk(parsed, 0);
        return authors;
    }
    // Merge authors from successful response sections, skipping optional failures.
    function parseSubjectAuthorsMulti(payloadText, splitToken) {
        let marker = "\n" + splitToken + "\n";
        let normalized = String(payloadText || "");
        if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n") normalized += "\n";

        let parts = normalized.split(marker);
        let merged = [];
        let mergedByKey = {};

        for (let partIndex = 0; partIndex < parts.length; partIndex++) {
            let part = String(parts[partIndex] || "").trim();
            if (!part) continue;
            let partAuthors = parseSubjectAuthors(part);
            for (let authorIndex = 0; authorIndex < partAuthors.length; authorIndex++)
                pushAuthorCandidate(merged, mergedByKey, partAuthors[authorIndex]);
        }

        return merged;
    }
    // Read distinct subject roots from valid optional response sections.
    function parseSubjectExpansionUrls(payloadText, splitToken) {
        let marker = "\n" + splitToken + "\n";
        let normalized = String(payloadText || "");
        if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n") normalized += "\n";

        let parts = normalized.split(marker);
        let urls = [];
        let seen = {};

        for (let partIndex = 0; partIndex < parts.length; partIndex++) {
            let part = String(parts[partIndex] || "").trim();
            if (!part) continue;
            let parsed;
            try {
                parsed = JSON.parse(part);
            } catch (error) {
                // Optional author sections may be missing or invalid; keep other participants and the message usable.
                continue;
            }

            if (Array.isArray(parsed)) {
                for (let itemIndex = 0; itemIndex < parsed.length; itemIndex++)
                    collectSubjectExpansionUrls(parsed[itemIndex], urls, seen);
            } else {
                collectSubjectExpansionUrls(parsed, urls, seen);
            }
        }

        return urls;
    }

    // =========================================================================
    //  Author List Operations
    // =========================================================================

    // Normalize a participant and enrich an existing record rather than duplicating it.
    function pushAuthorCandidate(target, byKey, userLike) {
        if (!userLike || typeof userLike !== "object") return;
        let htmlUrl = userLike.html_url || userLike.htmlUrl || "";
        let login = String(userLike.login || userLike.slug || appSlugFromHtmlUrl(htmlUrl) || "").trim();
        let avatarUrl = userLike.avatar_url || userLike.avatarUrl || "";
        if (!isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl)) return;
        htmlUrl = String(htmlUrl || "").trim();
        if (!htmlUrl && String(userLike.slug || "").trim())
            htmlUrl = properties.webBaseUrl + "/apps/" + encodeURIComponent(String(userLike.slug).trim());
        if (!htmlUrl) htmlUrl = properties.webBaseUrl + "/" + encodeURIComponent(login);

        avatarUrl = authorAvatarUrl({
            login: login,
            avatarUrl: avatarUrl,
            htmlUrl: htmlUrl
        });

        let key = authorKey(login, htmlUrl, avatarUrl);
        if (!key) return;
        if (byKey.hasOwnProperty(key)) {
            let existing = target[byKey[key]];
            if (!existing.login && login) existing.login = login;
            if (!existing.avatarUrl && avatarUrl) existing.avatarUrl = avatarUrl;
            if (!existing.htmlUrl && htmlUrl) existing.htmlUrl = htmlUrl;
            return;
        }

        byKey[key] = target.length;
        target.push({
            login: login,
            avatarUrl: avatarUrl,
            htmlUrl: htmlUrl
        });
    }
    // Derive the repository workflow endpoint from a validated check-suite subject.
    function repoActionsRunsUrlFromSubjectApiUrl(subjectApiUrl) {
        let normalized = normalizeApiUrl(subjectApiUrl);
        if (!normalized) return "";

        if (!providerApi) return "";
        let prefix = properties.apiBaseUrl + "/repos/";
        let path = normalized.substring(prefix.length);
        let parts = path.split("/");
        if (parts.length < 4 || parts[2] !== "check-suites") return "";

        return providerApi.buildRepositoryApiUrl(parts[0] + "/" + parts[1], "actions/runs");
    }
    // Prefer a validated subject endpoint, then its web link, then a CI fallback.
    function resolveSubjectApiUrlForAuthors(item) {
        if (!item) return "";

        let directUrl = normalizeApiUrl(item.subjectApiUrl || "");
        if (directUrl) return directUrl;

        let fromWeb = normalizeApiUrl(apiUrlFromWebUrl(item.webUrl || ""));
        if (fromWeb) return fromWeb;

        return buildCiApiUrl(item.repository || "", item.subjectType || "");
    }

    return {
        apiUrlFromWebUrl: apiUrlFromWebUrl,
        appSlugFromHtmlUrl: appSlugFromHtmlUrl,
        appendAuthorQuery: appendAuthorQuery,
        authorAvatarUrl: authorAvatarUrl,
        authorKey: authorKey,
        buildAuthorFetchUrls: buildAuthorFetchUrls,
        buildCiApiUrl: buildCiApiUrl,
        collectSubjectExpansionUrls: collectSubjectExpansionUrls,
        defaultAvatarUrlForLogin: defaultAvatarUrlForLogin,
        isGitHubAppUrl: isGitHubAppUrl,
        isLikelyGitHubLogin: isLikelyGitHubLogin,
        isLikelyGitHubUserObject: isLikelyGitHubUserObject,
        isPreExtractedAuthorPayload: isPreExtractedAuthorPayload,
        isThreadParentApiUrl: isThreadParentApiUrl,
        mergeAuthorLists: mergeAuthorLists,
        normalizeApiUrl: normalizeApiUrl,
        parseSubjectAuthors: parseSubjectAuthors,
        parseSubjectAuthorsMulti: parseSubjectAuthorsMulti,
        parseSubjectExpansionUrls: parseSubjectExpansionUrls,
        pushAuthorCandidate: pushAuthorCandidate,
        repoActionsRunsUrlFromSubjectApiUrl: repoActionsRunsUrlFromSubjectApiUrl,
        resolveSubjectApiUrlForAuthors: resolveSubjectApiUrlForAuthors
    };
}
