// GitHubHelpers.js - utility helpers for GitHub Inbox plugin
//
// Usage:
//   import "../Integrations/GitHub/GitHubHelpers.js" as GitHub

.pragma library
.import "NotificationParser.js" as Notifications
.import "../../Contracts/PluginError.js" as PluginError
.import "../../Helpers/CalendarTime.js" as CalendarTime

var _notifications = Notifications.createParser(PluginError);

// Display and token-syntax bounds; request limits come from the provider declarations.
var _UNREAD_COUNT_DISPLAY_MAX = 999;
var _CLASSIC_TOKEN_MIN_LENGTH = 40;
var _TOKEN_MAX_LENGTH = 255;

// Validate syntax only; GitHub still determines validity, expiry and granted permissions.
function validateTokenFormat(value) {
    var token = String(value || "").trim();
    if (!token) return "";
    if (!/^[A-Za-z0-9_]+$/.test(token))
        return "Token must contain only ASCII letters, digits and underscores, with no internal whitespace.";
    if (/^[a-fA-F0-9]{40}$/.test(token)) return "";
    if (token.indexOf("ghp_") !== 0) return "Use a classic personal access token beginning with ghp_.";
    if (token.length < _CLASSIC_TOKEN_MIN_LENGTH || token.length > _TOKEN_MAX_LENGTH)
        return (
            "Classic tokens must be between " +
            _CLASSIC_TOKEN_MIN_LENGTH +
            " and " +
            _TOKEN_MAX_LENGTH +
            " characters, including ghp_."
        );
    return "";
}

// Allow account names and the optional [bot] suffix before constructing account URLs.
function isSafeGitHubLogin(value) {
    var login = String(value || "").trim();
    if (!login) return false;

    var baseLogin = login.slice(-5) === "[bot]" ? login.slice(0, -5) : login;
    return /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9])?$/.test(baseLogin);
}

// Accept repository API URLs with safe path segments and simple query parameters.
function isSafeGitHubApiUrl(value) {
    var url = String(value || "").trim();
    var prefix = "https://api.github.com/repos/";
    if (url.indexOf(prefix) !== 0 || /[\s'"<>\\#`]/.test(url)) return false;

    var pathAndQuery = url.substring(prefix.length);
    var queryIndex = pathAndQuery.indexOf("?");
    var path = queryIndex < 0 ? pathAndQuery : pathAndQuery.substring(0, queryIndex);
    var query = queryIndex < 0 ? "" : pathAndQuery.substring(queryIndex + 1);
    if (queryIndex >= 0 && !/^[A-Za-z0-9._~=&-]*$/.test(query)) return false;

    var pathSegments = path.split("/");
    if (pathSegments.length < 3) return false;
    for (var index = 0; index < pathSegments.length; index++) {
        var segment = pathSegments[index];
        if (!segment || segment === "." || segment === ".." || !/^[A-Za-z0-9._-]+$/.test(segment)) return false;
    }
    return true;
}

// Allow GitHub app icons and avatar-host URLs, rejecting unsafe paths and encoded characters.
function isAllowedAvatarUrl(value) {
    var url = String(value || "").trim();
    if (/^https:\/\/github\.com\/apps\/[A-Za-z0-9][A-Za-z0-9._-]*\.png(?:\?size=[0-9]{1,4})?$/.test(url)) return true;

    var prefix = "https://avatars.githubusercontent.com/";
    if (url.indexOf(prefix) !== 0 || /[\s'"<>\\#`]/.test(url)) return false;

    var pathAndQuery = url.substring(prefix.length);
    var queryIndex = pathAndQuery.indexOf("?");
    var avatarPath = queryIndex < 0 ? pathAndQuery : pathAndQuery.substring(0, queryIndex);
    var query = queryIndex < 0 ? "" : pathAndQuery.substring(queryIndex + 1);
    if (!avatarPath || (queryIndex >= 0 && !/^[A-Za-z0-9._~=&-]*$/.test(query))) return false;
    if (
        !/^[A-Za-z0-9._~%/-]+$/.test(avatarPath) ||
        /%(?![A-Fa-f0-9]{2})/.test(avatarPath) ||
        /%(?:0[0-9A-Fa-f]|1[0-9A-Fa-f]|7[Ff]|22|27|23|25|2[Ff]|5[Cc]|3[Cc]|3[Ee]|60)/.test(avatarPath)
    )
        return false;

    var pathSegments = avatarPath.split("/");
    for (var index = 0; index < pathSegments.length; index++)
        if (!pathSegments[index] || pathSegments[index] === "." || pathSegments[index] === "..") return false;
    return true;
}

// Restrict browser links to github.com paths and queries without unsafe URL characters.
function isSafeGitHubWebUrl(value) {
    var url = String(value || "").trim();
    var prefix = "https://github.com/";
    if (url.indexOf(prefix) !== 0 || /[\s'"<>\\#`]/.test(url)) return false;

    var pathAndQuery = url.substring(prefix.length);
    var queryIndex = pathAndQuery.indexOf("?");
    var path = queryIndex < 0 ? pathAndQuery : pathAndQuery.substring(0, queryIndex);
    var query = queryIndex < 0 ? "" : pathAndQuery.substring(queryIndex + 1);
    if (
        queryIndex >= 0 &&
        (!/^[A-Za-z0-9._~%=&+-]*$/.test(query) ||
            /%(?![A-Fa-f0-9]{2})|%(?:0[0-9A-Fa-f]|1[0-9A-Fa-f]|7[Ff]|22|27|23|25|2[Ff]|5[Cc]|3[Cc]|3[Ee]|60)/.test(
                query
            ))
    )
        return false;

    if (
        !/^[A-Za-z0-9._~%/-]+$/.test(path) ||
        /%(?![A-Fa-f0-9]{2})|%(?:0[0-9A-Fa-f]|1[0-9A-Fa-f]|7[Ff]|22|27|23|25|2[Ff]|5[Cc]|3[Cc]|3[Ee]|60)/.test(path)
    )
        return false;

    var pathSegments = path.split("/");
    for (var index = 0; index < pathSegments.length; index++)
        if (!pathSegments[index] || pathSegments[index] === "." || pathSegments[index] === "..") return false;
    return true;
}

// Deduplicate queued and active avatars before applying the queue capacity.
function appendBoundedAvatarRequests(currentQueue, incomingRequests, blockedLogins, maximumQueueLength) {
    var nextQueue = Array.isArray(currentQueue) ? currentQueue.slice(0) : [];
    var maximumLength = Math.max(0, parseInt(maximumQueueLength) || 0);
    var queuedLogins = {};
    var blocked = blockedLogins || {};

    for (var queuedIndex = 0; queuedIndex < nextQueue.length; queuedIndex++) {
        var queuedLogin = String((nextQueue[queuedIndex] && nextQueue[queuedIndex].login) || "");
        if (queuedLogin) queuedLogins[queuedLogin] = true;
    }

    var requests = incomingRequests || [];
    for (var requestIndex = 0; requestIndex < requests.length; requestIndex++) {
        if (nextQueue.length >= maximumLength) break;

        var request = requests[requestIndex] || {};
        var login = String(request.login || "").trim();
        var remoteUrl = String(request.remoteUrl || "").trim();
        if (!isSafeGitHubLogin(login) || !isAllowedAvatarUrl(remoteUrl) || blocked[login] || queuedLogins[login])
            continue;

        queuedLogins[login] = true;
        nextQueue.push({ login: login, remoteUrl: remoteUrl });
    }

    return nextQueue;
}

// Accept the host's persisted boolean forms and fall back for missing values.
function pluginDataBool(value, defaultValue) {
    if (value === undefined || value === "") return !!defaultValue;
    if (typeof value === "boolean") return value;
    var normalized = String(value).toLowerCase();
    return normalized === "true" || normalized === "1" || normalized === "yes";
}

// Respect the provider minimum when converting saved polling preferences.
function pollIntervalMs(value, defaultIntervalSeconds, minimumIntervalSeconds) {
    var fallbackSeconds = Math.max(1, parseInt(defaultIntervalSeconds) || 120);
    var minimumSeconds = Math.max(1, parseInt(minimumIntervalSeconds) || fallbackSeconds);
    var seconds = parseInt(value || String(fallbackSeconds));
    if (isNaN(seconds) || seconds < minimumSeconds) return fallbackSeconds * 1000;
    return seconds * 1000;
}

// Decode one notification list using the shared inbox parser.
function parseMessagesPayload(payloadText) {
    return _notifications.parseMessagesPayload(payloadText);
}

// Decode a paired inbox/participation payload using the shared inbox parser.
function parseMessagesWithParticipation(payloadText, separator) {
    return _notifications.parseMessagesWithParticipation(payloadText, separator);
}

// Merge paginated inbox and participation lists using the supplied inbox page count.
function parseMessagesWithParticipationSegments(payloadText, separator, allSegmentCount) {
    return _notifications.parseMessagesWithParticipationSegments(payloadText, separator, allSegmentCount);
}

// Resolve a notification's browser destination through the shared inbox parser.
function resolveWebUrl(notification) {
    return _notifications.resolveWebUrl(notification);
}

// Translate a subject API endpoint into a browser link using its type and title.
function apiToWebUrl(apiUrl, subjectType, subjectTitle) {
    return _notifications.apiToWebUrl(apiUrl, subjectType, subjectTitle);
}

// Share UTC calendar boundaries with notification grouping instead of approximating durations.
function relativeTimeFromIso(isoDate, referenceMs) {
    return CalendarTime.relativeTimeFromIso(isoDate, referenceMs);
}

// Map API reason identifiers to readable labels without changing filter semantics.
function reasonLabel(reason) {
    if (!reason) return "Activity";

    var normalized = String(reason).trim().toLowerCase();
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
    };
    if (labels[normalized]) return labels[normalized];

    var words = normalized.replace(/_/g, " ").split(" ");
    for (var index = 0; index < words.length; index++) {
        if (!words[index]) continue;
        words[index] = words[index].charAt(0).toUpperCase() + words[index].substring(1);
    }
    return words.join(" ");
}

// Keep the bar count compact without changing the underlying count.
function formatCountValue(value) {
    var safe = Math.max(0, parseInt(value || 0));
    if (safe > _UNREAD_COUNT_DISPLAY_MAX) return _UNREAD_COUNT_DISPLAY_MAX + "+";
    return String(safe);
}

// Choose the visible count from the caller's read-filter policy.
function formatBarCount(unreadCount, totalCount, includeRead) {
    var unread = Math.max(0, parseInt(unreadCount || 0));
    var total = Math.max(0, parseInt(totalCount || 0));
    var read = Math.max(0, total - unread);

    if (includeRead) return formatCountValue(unread) + "/" + formatCountValue(read) + "/" + formatCountValue(total);
    return formatCountValue(unread) + "/" + formatCountValue(total);
}

// Choose a subject icon with a usable fallback for unknown notification types.
function subjectIconName(subjectType) {
    var type = String(subjectType || "").toLowerCase();

    if (type === "pullrequest") return "call_split";
    if (type === "issue") return "error_outline";
    if (type === "discussion") return "forum";
    if (type === "release") return "new_releases";
    if (type === "commit") return "account_tree";
    if (
        type === "repositoryvulnerabilityalert" ||
        type === "repositoryadvisory" ||
        type === "repositorydependabotalert" ||
        type === "vulnerabilityalert" ||
        type === "dependabotalert" ||
        type === "codescanningalert"
    )
        return "shield";
    if (type === "checksuite") return "fact_check";

    return "notifications";
}

// Keep supported type labels readable while preserving unknown subject names.
function subjectDisplayLabel(subjectType) {
    var type = String(subjectType || "").toLowerCase();

    if (type === "pullrequest") return "PR";
    if (type === "checksuite" || type === "checkrun" || type === "workflowrun") return "Workflow";
    if (type === "release") return "Release";
    if (type === "issue") return "Issue";
    if (type === "discussion") return "Discussion";
    if (type === "commit") return "Commit";
    if (
        type === "repositoryvulnerabilityalert" ||
        type === "repositoryadvisory" ||
        type === "repositorydependabotalert" ||
        type === "vulnerabilityalert" ||
        type === "dependabotalert" ||
        type === "codescanningalert"
    )
        return "Security";

    return splitCamelCase(subjectType || "Message");
}

// Prefer the resolved reference and retain its visible hash prefix.
function subjectReferenceLabel(subjectType, subjectApiUrl, webUrl, explicitReference) {
    var number = String(explicitReference || "")
        .trim()
        .replace(/^#/, "");
    if (!number) number = subjectReferenceNumber(subjectType, subjectApiUrl, webUrl);
    return number ? "#" + number : "";
}

// Extract a subject identifier without confusing workflow run IDs with run numbers.
function subjectReferenceNumber(subjectType, subjectApiUrl, webUrl) {
    var type = String(subjectType || "").toLowerCase();
    var apiUrl = String(subjectApiUrl || "");
    var pageUrl = String(webUrl || "");
    var match;

    if (type === "pullrequest") {
        match = apiUrl.match(/\/pulls\/([0-9]+)(?:$|[?#])/) || pageUrl.match(/\/pull\/([0-9]+)(?:$|[?#])/);
        return match ? match[1] : "";
    }

    if (type === "issue") {
        match = apiUrl.match(/\/issues\/([0-9]+)(?:$|[?#])/) || pageUrl.match(/\/issues\/([0-9]+)(?:$|[?#])/);
        return match ? match[1] : "";
    }

    if (type === "discussion") {
        match = apiUrl.match(/\/discussions\/([0-9]+)(?:$|[?#])/) || pageUrl.match(/\/discussions\/([0-9]+)(?:$|[?#])/);
        return match ? match[1] : "";
    }

    if (type === "checksuite" || type === "checkrun" || type === "workflowrun") {
        match =
            apiUrl.match(/\/actions\/runs\/([0-9]+)(?:$|[?#])/) ||
            apiUrl.match(/\/check-(?:suites|runs)\/([0-9]+)(?:$|[?#])/);
        return match ? match[1] : "";
    }

    return "";
}

// Give unknown API identifiers a readable fallback label.
function splitCamelCase(value) {
    var text = String(value || "").trim();
    if (!text) return "Message";
    return text.replace(/([a-z0-9])([A-Z])/g, "$1 $2");
}
