// GitHubProviderApi.js - builds GitHub requests and parses inbox responses.

.pragma library

.import "AuthorTools.js" as AuthorTools

// Construct an independent value implementing this module's public contract.
function create(providerApi, properties, helpers) {
    var api = providerApi.create();
    api.providerId = properties.providerId;
    api.properties = properties;

    api.validateTokenFormat = function (value) {
        return helpers.validateTokenFormat(value);
    };

    api.createAuthorTools = function (perPageQuery) {
        return AuthorTools.create(api, properties, perPageQuery);
    };

    api.buildInboxUrl = function () {
        return properties.apiBaseUrl + properties.inboxPath;
    };

    api.buildThreadActionRequest = function (action, threadId) {
        var thread = String(threadId || "");
        if (!/^[0-9]+$/.test(thread)) return null;

        if (action === "read")
            return {
                method: "PATCH",
                url: properties.apiBaseUrl + properties.threadPath + "/" + thread,
                payloadJson: ""
            };
        if (action === "unread")
            return {
                method: "PATCH",
                url: properties.apiBaseUrl + properties.threadPath + "/" + thread,
                payloadJson: '{"read":false}'
            };
        if (action === "done")
            return {
                method: "DELETE",
                url: properties.apiBaseUrl + properties.threadPath + "/" + thread,
                payloadJson: ""
            };
        return null;
    };

    api.buildRepositoryReadRequest = function (repositoryFullName) {
        var url = api.buildRepositoryApiUrl(repositoryFullName, "notifications");
        if (!url) return null;

        return {
            method: "PUT",
            url: url,
            payloadJson: ""
        };
    };

    api.buildRepositoryApiUrl = function (repositoryFullName, resourcePath) {
        var parts = String(repositoryFullName || "").split("/");
        var path = String(resourcePath || "").replace(/^\/+|\/+$/g, "");
        if (
            parts.length !== 2 ||
            !/^[A-Za-z0-9_.-]+$/.test(parts[0]) ||
            !/^[A-Za-z0-9_.-]+$/.test(parts[1]) ||
            parts[0] === "." ||
            parts[0] === ".." ||
            parts[1] === "." ||
            parts[1] === ".." ||
            !/^[A-Za-z0-9_./-]+$/.test(path)
        )
            return "";
        var pathSegments = path.split("/");
        for (var index = 0; index < pathSegments.length; index++)
            if (!pathSegments[index] || pathSegments[index] === "." || pathSegments[index] === "..") return "";

        return (
            properties.apiBaseUrl +
            "/repos/" +
            encodeURIComponent(parts[0]) +
            "/" +
            encodeURIComponent(parts[1]) +
            "/" +
            path
        );
    };

    api.buildMarkAllReadRequest = function () {
        return { method: "PUT", url: api.buildInboxUrl(), payloadJson: "" };
    };

    api.buildAvatarUrl = function (login) {
        if (!helpers.isSafeGitHubLogin(login)) return "";
        return (
            properties.avatarsBaseUrl +
            "/" +
            encodeURIComponent(String(login).trim()) +
            "?size=" +
            properties.avatarSizePx
        );
    };

    api.buildAppAvatarUrl = function (slug) {
        var normalizedSlug = String(slug || "").trim();
        if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(normalizedSlug)) return "";
        return (
            properties.webBaseUrl +
            "/apps/" +
            encodeURIComponent(normalizedSlug) +
            ".png?size=" +
            properties.avatarSizePx
        );
    };

    api.buildRepositoryWebUrl = function (repositoryFullName) {
        var parts = String(repositoryFullName || "").split("/");
        if (
            parts.length !== 2 ||
            !/^[A-Za-z0-9_.-]+$/.test(parts[0]) ||
            !/^[A-Za-z0-9_.-]+$/.test(parts[1]) ||
            parts[0] === "." ||
            parts[0] === ".." ||
            parts[1] === "." ||
            parts[1] === ".."
        )
            return "";
        return properties.webBaseUrl + "/" + encodeURIComponent(parts[0]) + "/" + encodeURIComponent(parts[1]);
    };

    api.buildUserProfileUrl = function (login) {
        if (!helpers.isSafeGitHubLogin(login)) return "";
        return properties.webBaseUrl + "/" + encodeURIComponent(String(login).trim());
    };

    api.getRetryPolicy = function () {
        return {
            retryCount: properties.requestRetryCount,
            maximumRetryTimeSeconds: properties.requestRetryMaxTimeSeconds,
            http2RetryCount: properties.http2RetryCount,
            http2RetryDelayBaseSeconds: properties.http2RetryDelayBaseSeconds
        };
    };

    api.buildCurlRetryArguments = function () {
        var retryPolicy = api.getRetryPolicy();
        return [
            "--retry",
            String(retryPolicy.retryCount),
            "--retry-connrefused",
            "--retry-max-time",
            String(retryPolicy.maximumRetryTimeSeconds)
        ];
    };

    api.isAllowedApiUrl = function (url) {
        return helpers.isSafeGitHubApiUrl(url);
    };

    api.isAllowedAvatarUrl = function (url) {
        return helpers.isAllowedAvatarUrl(url);
    };

    api.isAllowedWebUrl = function (url) {
        return helpers.isSafeGitHubWebUrl(url);
    };

    api.parseInboxResponse = function (payloadText) {
        return helpers.parseMessagesPayload(payloadText);
    };

    api.isSafeLogin = function (value) {
        return helpers.isSafeGitHubLogin(value);
    };

    api.appendBoundedAvatarRequests = function (currentQueue, incomingRequests, blockedLogins, maximumQueueLength) {
        return helpers.appendBoundedAvatarRequests(currentQueue, incomingRequests, blockedLogins, maximumQueueLength);
    };

    api.pluginDataBool = function (value, defaultValue) {
        return helpers.pluginDataBool(value, defaultValue);
    };

    api.pollIntervalMs = function (value, defaultIntervalSeconds, minimumIntervalSeconds) {
        return helpers.pollIntervalMs(value, defaultIntervalSeconds, minimumIntervalSeconds);
    };

    api.relativeTimeFromIso = function (isoDate) {
        return helpers.relativeTimeFromIso(isoDate);
    };

    api.reasonLabel = function (reason) {
        return helpers.reasonLabel(reason);
    };

    api.formatCountValue = function (value) {
        return helpers.formatCountValue(value);
    };

    api.subjectIconName = function (subjectType) {
        return helpers.subjectIconName(subjectType);
    };

    api.subjectDisplayLabel = function (subjectType) {
        return helpers.subjectDisplayLabel(subjectType);
    };

    api.subjectReferenceLabel = function (subjectType, subjectApiUrl, webUrl, explicitReference) {
        return helpers.subjectReferenceLabel(subjectType, subjectApiUrl, webUrl, explicitReference);
    };

    return api;
}
