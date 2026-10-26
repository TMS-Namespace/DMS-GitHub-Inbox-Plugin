// InboxParserBackgroundWorker.js - background parser for GitHub inbox messages

// Include stateless libraries in this worker context; QML uses their normal module imports.
Qt.include("../../Contracts/PluginError.js");
var PluginError = { create: create, isPluginError: isPluginError, fromException: fromException };
Qt.include("./NotificationParser.js");
var Notifications = createParser(PluginError);

// Local mirrors of src/QML/Tools/Constants.qml values.
// WorkerScript files cannot access QML singletons; constants are inlined here.
var _FETCH_PAYLOAD_SPLIT_TOKEN = "__GH_PARTICIPATING_SPLIT__";
var _MESSAGES_PARSE_CHUNK_SIZE = 40;
var _AVATAR_DEFAULT_SIZE_PX = 128;

WorkerScript.onMessage = function (message) {
    // ---- Author JSON parsing (offloaded from Widget.qml main thread) -------
    if (message.action === "parseAuthors") {
        var authors = [];
        var expansionUrls = [];
        var subjectWebUrl = "";
        var subjectReference = "";
        if (message.buffer) {
            authors = parseSubjectAuthorsMulti(message.buffer, message.splitToken || "");
            subjectWebUrl = parseSubjectWebUrlMulti(
                message.buffer,
                message.splitToken || "",
                message.subjectTitle || "",
                message.updatedAt || ""
            );
            subjectReference = parseSubjectReferenceMulti(
                message.buffer,
                message.splitToken || "",
                message.subjectTitle || "",
                message.updatedAt || ""
            );
            if (message.shouldExpand)
                expansionUrls = parseSubjectExpansionUrls(message.buffer, message.splitToken || "");
            if (isCiAuthorSubject(message.subjectType || "", message.reason || "")) {
                var runAuthors = parseBestActionRunAuthorsMulti(
                    message.buffer,
                    message.splitToken || "",
                    message.subjectTitle || "",
                    message.updatedAt || ""
                );
                if (runAuthors.length > 0) authors = runAuthors;
            }
        }
        WorkerScript.sendMessage({
            action: "authorsResult",
            generation: message.generation || 0,
            threadId: message.threadId || "",
            updatedAt: message.updatedAt || "",
            requestedUrls: message.requestedUrls || [],
            automaticPrefetch: !!message.automaticPrefetch,
            subjectType: message.subjectType || "",
            reason: message.reason || "",
            shouldExpand: !!message.shouldExpand,
            fallbackAuthor: message.fallbackAuthor || null,
            authors: authors,
            subjectWebUrl: subjectWebUrl,
            subjectReference: subjectReference,
            expansionUrls: expansionUrls
        });
        return;
    }
    // -----------------------------------------------------------------------
    try {
        var parsed = Notifications.parseMessagesWithParticipationSegments(
            message.payloadText || "",
            message.separator || _FETCH_PAYLOAD_SPLIT_TOKEN,
            message.allSegmentCount || 0,
            message.pageSize || 50,
            message.targetOldestVisibleUpdatedAtMs || 0
        );

        if (parsed.error) {
            WorkerScript.sendMessage({
                seq: message.seq || 0,
                error: parsed.error
            });
            return;
        }

        var filtered = [];
        var unread = 0;

        for (var index = 0; index < parsed.items.length; index++) {
            var item = parsed.items[index];
            item.participated = !!item.participated;
            if (item.unread) unread++;
            filtered.push(item);
        }

        var seq = message.seq || 0;
        var chunkSize = parseInt(message.chunkSize || _MESSAGES_PARSE_CHUNK_SIZE);
        if (isNaN(chunkSize) || chunkSize < 20) chunkSize = _MESSAGES_PARSE_CHUNK_SIZE;

        WorkerScript.sendMessage({
            seq: seq,
            phase: "begin",
            unreadCount: unread,
            totalCount: filtered.length,
            isComplete: !!parsed.isComplete
        });

        if (filtered.length === 0) {
            WorkerScript.sendMessage({
                seq: seq,
                phase: "chunk",
                items: [],
                isLast: true
            });
            return;
        }

        for (var offset = 0; offset < filtered.length; offset += chunkSize) {
            var end = Math.min(filtered.length, offset + chunkSize);
            WorkerScript.sendMessage({
                seq: seq,
                phase: "chunk",
                items: filtered.slice(offset, end),
                isLast: end >= filtered.length
            });
        }
    } catch (error) {
        let failure = PluginError.fromException(error, "Failed to parse inbox messages payload.");
        WorkerScript.sendMessage({
            seq: message.seq || 0,
            error: failure.userMessage,
            failure: failure
        });
    }
};

// ---- Author parsing helpers (mirror of Widget.qml, runs in worker thread) --

// Build a provider-specific destination from validated subject data.
function defaultAvatarUrlForLogin(login) {
    var normalized = String(login || "").trim();
    if (!normalized) return "";
    return (
        "https://avatars.githubusercontent.com/" + encodeURIComponent(normalized) + "?size=" + _AVATAR_DEFAULT_SIZE_PX
    );
}

// Retain recognized author data while deduplicating candidates and resources.
function authorAvatarUrl(authorLike) {
    if (!authorLike) return "";
    var avatarUrl = String(authorLike.avatarUrl || authorLike.avatar_url || "").trim();
    if (avatarUrl) return avatarUrl;
    var htmlUrl = String(authorLike.htmlUrl || authorLike.html_url || "").trim();
    if (isGitHubAppUrl(htmlUrl)) return htmlUrl + ".png?size=" + _AVATAR_DEFAULT_SIZE_PX;
    var login = String(authorLike.login || "").trim();
    if (login) return defaultAvatarUrlForLogin(login);
    return "";
}

// Retain recognized author data while deduplicating candidates and resources.
function appSlugFromHtmlUrl(htmlUrl) {
    var normalized = String(htmlUrl || "").trim();
    var prefix = "https://github.com/apps/";
    if (normalized.indexOf(prefix) !== 0) return "";
    var slug = normalized.substring(prefix.length).split(/[/?#]/)[0];
    return String(slug || "").trim();
}

// Check the relevant invariants before dependent work can proceed.
function isGitHubAppUrl(htmlUrl) {
    return appSlugFromHtmlUrl(htmlUrl) !== "";
}

// Retain recognized author data while deduplicating candidates and resources.
function authorKey(login, htmlUrl, avatarUrl) {
    var normalizedLogin = String(login || "")
        .trim()
        .toLowerCase();
    if (normalizedLogin) return normalizedLogin;
    var normalizedHtml = String(htmlUrl || "").trim();
    if (normalizedHtml) return normalizedHtml;
    return String(avatarUrl || "").trim();
}

// Check the relevant invariants before dependent work can proceed.
function isLikelyGitHubLogin(login) {
    var value = String(login || "").trim();
    if (!value) return false;
    var base = value;
    if (base.slice(-5) === "[bot]") base = base.slice(0, -5);
    return /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9])?$/.test(base);
}

// Check the relevant invariants before dependent work can proceed.
function isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl) {
    if (!userLike || typeof userLike !== "object") return false;
    var normalizedLogin = String(login || "").trim();
    if (!isLikelyGitHubLogin(normalizedLogin)) return false;
    var normalizedType = String(userLike.type || "")
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
    var normalizedAvatar = String(avatarUrl || "")
        .trim()
        .toLowerCase();
    if (normalizedAvatar.indexOf("https://avatars.githubusercontent.com/") === 0) return true;
    if (normalizedAvatar.indexOf("https://github.com/") === 0 && normalizedAvatar.indexOf(".png") > 0) return true;
    var normalizedHtml = String(htmlUrl || "")
        .trim()
        .toLowerCase();
    var lowerLogin = normalizedLogin.toLowerCase();
    if (appSlugFromHtmlUrl(normalizedHtml) === lowerLogin) return true;
    if (normalizedHtml === "https://github.com/" + lowerLogin) return true;
    if (normalizedHtml.indexOf("https://github.com/" + lowerLogin + "/") === 0) return true;
    return false;
}

// Retain recognized author data while deduplicating candidates and resources.
function pushAuthorCandidate(target, byKey, userLike) {
    if (!userLike || typeof userLike !== "object") return;
    var htmlUrl = userLike.html_url || userLike.htmlUrl || "";
    var login = String(userLike.login || userLike.slug || appSlugFromHtmlUrl(htmlUrl) || "").trim();
    var avatarUrl = userLike.avatar_url || userLike.avatarUrl || "";
    if (!isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl)) return;
    htmlUrl = String(htmlUrl || "").trim();
    if (!htmlUrl && String(userLike.slug || "").trim())
        htmlUrl = "https://github.com/apps/" + encodeURIComponent(String(userLike.slug).trim());
    if (!htmlUrl) htmlUrl = "https://github.com/" + encodeURIComponent(login);
    avatarUrl = authorAvatarUrl({ login: login, avatarUrl: avatarUrl, htmlUrl: htmlUrl });
    var key = authorKey(login, htmlUrl, avatarUrl);
    if (!key) return;
    if (byKey.hasOwnProperty(key)) {
        var existing = target[byKey[key]];
        if (!existing.login && login) existing.login = login;
        if (!existing.avatarUrl && avatarUrl) existing.avatarUrl = avatarUrl;
        if (!existing.htmlUrl && htmlUrl) existing.htmlUrl = htmlUrl;
        return;
    }
    byKey[key] = target.length;
    target.push({ login: login, avatarUrl: avatarUrl, htmlUrl: htmlUrl });
}

// Decode only recognized response fields while preserving notification context.
function parseSubjectAuthors(payloadText) {
    var authors = [];
    var byKey = {};
    var parsed;
    try {
        parsed = JSON.parse(payloadText || "{}");
    } catch (error) {
        // Optional author sections may be missing or invalid; keep other participants and the message usable.
        // Malformed optional author details should not discard the inbox item.
        return [];
    }

    if (isPreExtractedAuthorPayload(parsed)) {
        for (var extractedIndex = 0; extractedIndex < parsed.authors.length; extractedIndex++)
            pushAuthorCandidate(authors, byKey, parsed.authors[extractedIndex]);
        return authors;
    }

    // Accept either a candidate object or a list without losing individual authors.
    function pushAuthorValue(value) {
        if (!value) return;
        if (Array.isArray(value)) {
            for (var i = 0; i < value.length; i++) pushAuthorValue(value[i]);
            return;
        }
        pushAuthorCandidate(authors, byKey, value);
    }

    // Read only recognized actor fields instead of treating every nested user as an author.
    function collectFromNode(value) {
        if (!value || typeof value !== "object") return;
        pushAuthorValue(value.actor);
        pushAuthorValue(value.triggering_actor);

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
            for (var i = value.length - 1; i >= 0; i--) walk(value[i], depth + 1);
            return;
        }
        if (typeof value !== "object") return;
        collectFromNode(value);
        for (var propertyName in value) {
            if (!value.hasOwnProperty(propertyName)) continue;
            if (
                propertyName === "owner" ||
                propertyName === "repository" ||
                propertyName === "repo" ||
                propertyName === "head_repository" ||
                propertyName === "base_repository" ||
                propertyName === "head_repo" ||
                propertyName === "base_repo"
            )
                continue;
            var child = value[propertyName];
            if (!child || typeof child !== "object") continue;
            walk(child, depth + 1);
        }
    }
    walk(parsed, 0);
    return authors;
}

// Check the relevant invariants before dependent work can proceed.
function isPreExtractedAuthorPayload(value) {
    return (
        value &&
        typeof value === "object" &&
        !Array.isArray(value) &&
        Array.isArray(value.authors) &&
        (value.hasOwnProperty("subjectWebUrl") || value.hasOwnProperty("actionRuns") || value.hasOwnProperty("release"))
    );
}

// Decode only recognized response fields while preserving notification context.
function parseSubjectAuthorsMulti(payloadText, splitToken) {
    var marker = "\n" + (splitToken || "") + "\n";
    var normalized = String(payloadText || "");
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n") normalized += "\n";
    var parts = normalized.split(marker);
    var merged = [];
    var mergedByKey = {};
    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim();
        if (!part) continue;
        var partAuthors = parseSubjectAuthors(part);
        for (var j = 0; j < partAuthors.length; j++) pushAuthorCandidate(merged, mergedByKey, partAuthors[j]);
    }
    return merged;
}

// Check the relevant invariants before dependent work can proceed.
function isCiAuthorSubject(subjectType, reason) {
    var normalizedType = String(subjectType || "").toLowerCase();
    var normalizedReason = String(reason || "").toLowerCase();
    return (
        normalizedReason === "ci_activity" ||
        normalizedType === "checksuite" ||
        normalizedType === "checkrun" ||
        normalizedType === "workflowrun"
    );
}

// Decode only recognized response fields while preserving notification context.
function parseBestActionRunAuthorsMulti(payloadText, splitToken, subjectTitle, updatedAt) {
    var marker = "\n" + (splitToken || "") + "\n";
    var normalized = String(payloadText || "");
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n") normalized += "\n";

    var parts = normalized.split(marker);
    var best = { score: -1, url: "", reference: "", run: null };
    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim();
        if (!part) continue;
        var parsed;
        try {
            parsed = JSON.parse(part);
        } catch (error) {
            // Optional author sections may be missing or invalid; keep other participants and the message usable.
            // Continue checking other response pages when one detail payload is malformed.
            continue;
        }
        best = chooseBestActionRunUrl(parsed, subjectTitle, updatedAt, best);
    }

    var authors = [];
    var byKey = {};
    var run = best.run || null;
    if (!run) return authors;

    pushAuthorCandidate(authors, byKey, run.triggeringActor || run.triggering_actor);
    if (authors.length === 0) pushAuthorCandidate(authors, byKey, run.actor);
    if (authors.length === 0) pushAuthorCandidate(authors, byKey, run.user);
    return authors;
}

// Apply the owning module's rules before exposing data to dependent components.
function normalizeApiUrlWorker(url) {
    var normalized = String(url || "").trim();
    if (!normalized) return "";
    var prefix = "https://api.github.com/repos/";
    if (normalized.indexOf(prefix) !== 0 || /[\s'"<>\\#`]/.test(normalized)) return "";
    var queryIndex = normalized.indexOf("?");
    var pathAndQuery = normalized.substring(prefix.length);
    var query = queryIndex < 0 ? "" : normalized.substring(queryIndex + 1);
    if (queryIndex >= 0 && !/^[A-Za-z0-9._~=&-]*$/.test(query)) return "";
    var path = queryIndex < 0 ? pathAndQuery : pathAndQuery.substring(0, pathAndQuery.indexOf("?"));
    var pathSegments = path.split("/");
    if (pathSegments.length < 3) return "";
    for (var segmentIndex = 0; segmentIndex < pathSegments.length; segmentIndex++) {
        var segment = pathSegments[segmentIndex];
        if (!segment || segment === "." || segment === ".." || !/^[A-Za-z0-9._-]+$/.test(segment)) return "";
    }
    if (queryIndex >= 0) normalized = normalized.substring(0, queryIndex);
    return normalized;
}

// Check the relevant invariants before dependent work can proceed.
function isThreadParentApiUrlWorker(url) {
    var normalized = normalizeApiUrlWorker(url);
    if (!normalized) return false;
    var parts = normalized.split("/");
    if (parts.length !== 8) return false;
    if (parts[0] !== "https:" || parts[2] !== "api.github.com" || parts[3] !== "repos") return false;
    if (parts[6] !== "issues" && parts[6] !== "pulls") return false;
    return /^[0-9]+$/.test(parts[7]);
}

// Retain recognized author data while deduplicating candidates and resources.
function collectSubjectExpansionUrlsWorker(value, target, seen) {
    if (!value || typeof value !== "object") return;
    // Deduplicate a candidate before adding it to the bounded result set.
    function push(url) {
        var normalized = normalizeApiUrlWorker(url);
        if (!normalized || !isThreadParentApiUrlWorker(normalized) || seen[normalized]) return;
        seen[normalized] = true;
        target.push(normalized);
    }
    push(value.issue_url);
    push(value.pull_request_url);
    push(value.url);
}

// Decode only recognized response fields while preserving notification context.
function parseSubjectExpansionUrls(payloadText, splitToken) {
    var marker = "\n" + (splitToken || "") + "\n";
    var normalized = String(payloadText || "");
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n") normalized += "\n";
    var parts = normalized.split(marker);
    var urls = [];
    var seen = {};
    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim();
        if (!part) continue;
        var parsed;
        try {
            parsed = JSON.parse(part);
        } catch (error) {
            // Optional author sections may be missing or invalid; keep other participants and the message usable.
            // Ignore malformed response pages and retain valid expansion URLs from the rest.
            continue;
        }
        if (Array.isArray(parsed)) {
            for (var j = 0; j < parsed.length; j++) collectSubjectExpansionUrlsWorker(parsed[j], urls, seen);
        } else {
            collectSubjectExpansionUrlsWorker(parsed, urls, seen);
        }
    }
    return urls;
}

// Decode only recognized response fields while preserving notification context.
function parseSubjectWebUrlMulti(payloadText, splitToken, subjectTitle, updatedAt) {
    var marker = "\n" + (splitToken || "") + "\n";
    var normalized = String(payloadText || "");
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n") normalized += "\n";
    var parts = normalized.split(marker);
    var best = { score: -1, url: "" };

    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim();
        if (!part) continue;
        var parsed;
        try {
            parsed = JSON.parse(part);
        } catch (error) {
            // Optional author sections may be missing or invalid; keep other participants and the message usable.
            // A malformed detail payload may still be followed by one with a valid subject URL.
            continue;
        }

        var directUrl = directSubjectWebUrlFromObject(parsed);
        if (directUrl) return directUrl;

        best = chooseBestActionRunUrl(parsed, subjectTitle, updatedAt, best);
    }

    return best.url || "";
}

// Decode only recognized response fields while preserving notification context.
function parseSubjectReferenceMulti(payloadText, splitToken, subjectTitle, updatedAt) {
    var marker = "\n" + (splitToken || "") + "\n";
    var normalized = String(payloadText || "");
    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) !== "\n") normalized += "\n";
    var parts = normalized.split(marker);
    var best = { score: -1, url: "", reference: "" };

    for (var i = 0; i < parts.length; i++) {
        var part = String(parts[i] || "").trim();
        if (!part) continue;
        var parsed;
        try {
            parsed = JSON.parse(part);
        } catch (error) {
            // Optional author sections may be missing or invalid; keep other participants and the message usable.
            // A malformed detail payload may still be followed by one with a valid reference.
            continue;
        }

        var directReference = directSubjectReferenceFromObject(parsed);
        if (directReference) return directReference;

        best = chooseBestActionRunUrl(parsed, subjectTitle, updatedAt, best);
    }

    return best.reference || "";
}

// Decode only recognized response fields while preserving notification context.
function directSubjectWebUrlFromObject(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return "";

    var subjectWebUrl = String(value.subjectWebUrl || value.subject_web_url || "").trim();
    if (subjectWebUrl) return subjectWebUrl;

    var tagName = String(value.tagName || value.tag_name || "").trim();
    var htmlUrl = String(value.htmlUrl || value.html_url || "").trim();
    if (tagName && htmlUrl) return htmlUrl;
    if (htmlUrl && isLikelySubjectObject(value)) return htmlUrl;

    if (value.release && typeof value.release === "object") return directSubjectWebUrlFromObject(value.release);

    return "";
}

// Decode only recognized response fields while preserving notification context.
function directSubjectReferenceFromObject(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return "";

    var subjectReference = String(value.subjectReference || value.subject_reference || "").trim();
    if (subjectReference) return subjectReference.replace(/^#/, "");

    var runNumber = String(value.runNumber || value.run_number || "").trim();
    if (runNumber) return runNumber.replace(/^#/, "");

    return "";
}

// Check the relevant invariants before dependent work can proceed.
function isLikelySubjectObject(value) {
    if (!value || typeof value !== "object") return false;
    if (value.url || value.node_id || value.id || value.number || value.sha) return true;
    if (value.tag_name || value.name || value.title || value.state) return true;
    return false;
}

// Match workflow, branch, conclusion and notification time before choosing a run.
function chooseBestActionRunUrl(value, subjectTitle, updatedAt, currentBest) {
    var best = currentBest || { score: -1, url: "" };
    var runs = [];

    if (value && typeof value === "object") {
        if (value.actionRunUrl)
            return { score: 1000000, url: String(value.actionRunUrl), reference: String(value.actionRunNumber || "") };
        if (isWorkflowRunObject(value)) runs.push(value);
        if (Array.isArray(value.actionRuns)) runs = runs.concat(value.actionRuns);
        if (Array.isArray(value.workflow_runs)) runs = runs.concat(value.workflow_runs);
    }

    var expectedName = workflowNameFromNotificationTitle(subjectTitle);
    var expectedBranch = branchFromNotificationTitle(subjectTitle);
    var expectedConclusion = conclusionFromNotificationTitle(subjectTitle);
    var expectedTime = Date.parse(updatedAt || "") || 0;

    for (var index = 0; index < runs.length; index++) {
        var run = runs[index] || {};
        var url = String(run.htmlUrl || run.html_url || "").trim();
        if (!url) continue;

        var score = 0;
        var runName = String(run.name || "").trim();
        var displayTitle = String(run.displayTitle || run.display_title || "").trim();
        var headBranch = String(run.headBranch || run.head_branch || "").trim();
        var conclusion = String(run.conclusion || "")
            .trim()
            .toLowerCase();
        var runNumber = String(run.runNumber || run.run_number || "").trim();

        if (expectedName) {
            if (runName.toLowerCase() === expectedName.toLowerCase()) score += 100;
            else if (displayTitle.toLowerCase().indexOf(expectedName.toLowerCase()) >= 0) score += 40;
            else score -= 100;
        }

        if (expectedBranch) {
            if (headBranch === expectedBranch) score += 100;
            else score -= 100;
        }

        if (expectedConclusion) {
            if (conclusion === expectedConclusion) score += 50;
            else score -= 40;
        }

        var runTime = Date.parse(run.updatedAt || run.updated_at || "") || 0;
        if (expectedTime && runTime) {
            var deltaMinutes = Math.abs(runTime - expectedTime) / 60000;
            if (deltaMinutes <= 10) score += 40;
            else if (deltaMinutes <= 120) score += 20;
            else score -= Math.min(40, Math.floor(deltaMinutes / 60));
        } else {
            score += Math.max(0, runs.length - index);
        }

        if (score > best.score) best = { score: score, url: url, reference: runNumber.replace(/^#/, ""), run: run };
    }

    return best;
}

// Check the relevant invariants before dependent work can proceed.
function isWorkflowRunObject(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    var url = String(value.htmlUrl || value.html_url || "").trim();
    if (url.indexOf("/actions/runs/") < 0) return false;
    return (
        value.runNumber !== undefined ||
        value.run_number !== undefined ||
        value.actor !== undefined ||
        value.triggeringActor !== undefined ||
        value.triggering_actor !== undefined
    );
}

// Decode only recognized response fields while preserving notification context.
function workflowNameFromNotificationTitle(title) {
    var match = String(title || "").match(/^(.+?) workflow run/i);
    return match ? match[1].trim() : "";
}

// Decode only recognized response fields while preserving notification context.
function branchFromNotificationTitle(title) {
    var match = String(title || "").match(/ for (.+) branch$/i);
    return match ? match[1].trim() : "";
}

// Decode only recognized response fields while preserving notification context.
function conclusionFromNotificationTitle(title) {
    var normalized = String(title || "").toLowerCase();
    if (normalized.indexOf(" failed ") >= 0) return "failure";
    if (normalized.indexOf(" succeeded ") >= 0) return "success";
    if (normalized.indexOf(" cancelled ") >= 0 || normalized.indexOf(" canceled ") >= 0) return "cancelled";
    if (normalized.indexOf(" skipped ") >= 0) return "skipped";
    return "";
}
