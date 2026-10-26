// ProviderApi.js - base API facade contract shared by resource providers.

.pragma library

var requiredMethods = [
    "validateTokenFormat",
    "createAuthorTools",
    "buildInboxUrl",
    "buildThreadActionRequest",
    "buildRepositoryReadRequest",
    "buildRepositoryApiUrl",
    "buildMarkAllReadRequest",
    "buildAvatarUrl",
    "buildAppAvatarUrl",
    "buildRepositoryWebUrl",
    "buildUserProfileUrl",
    "getRetryPolicy",
    "buildCurlRetryArguments",
    "isAllowedApiUrl",
    "isAllowedAvatarUrl",
    "isAllowedWebUrl",
    "parseInboxResponse",
    "isSafeLogin",
    "appendBoundedAvatarRequests",
    "pluginDataBool",
    "pollIntervalMs",
    "relativeTimeFromIso",
    "reasonLabel",
    "formatCountValue",
    "subjectIconName",
    "subjectDisplayLabel",
    "subjectReferenceLabel"
];

// Construct an independent value implementing this module's public contract.
function create() {
    return {
        providerId: "",
        properties: null,
        validateTokenFormat: null,
        createAuthorTools: null,
        buildInboxUrl: null,
        buildThreadActionRequest: null,
        buildRepositoryReadRequest: null,
        buildRepositoryApiUrl: null,
        buildMarkAllReadRequest: null,
        buildAvatarUrl: null,
        buildAppAvatarUrl: null,
        buildRepositoryWebUrl: null,
        buildUserProfileUrl: null,
        getRetryPolicy: null,
        buildCurlRetryArguments: null,
        isAllowedApiUrl: null,
        isAllowedAvatarUrl: null,
        isAllowedWebUrl: null,
        parseInboxResponse: null,
        isSafeLogin: null,
        appendBoundedAvatarRequests: null,
        pluginDataBool: null,
        pollIntervalMs: null,
        relativeTimeFromIso: null,
        reasonLabel: null,
        formatCountValue: null,
        subjectIconName: null,
        subjectDisplayLabel: null,
        subjectReferenceLabel: null
    };
}

// Return declaration errors before a provider is exposed to callers.
function validate(api, properties) {
    var errors = [];
    if (!api || typeof api !== "object") return ["Provider API must be an object."];
    if (api.providerId !== properties.providerId)
        errors.push("Provider API identifier does not match its declaration.");
    if (api.properties !== properties) errors.push("Provider API must use its validated properties declaration.");
    for (var methodIndex = 0; methodIndex < requiredMethods.length; methodIndex++) {
        var methodName = requiredMethods[methodIndex];
        if (typeof api[methodName] !== "function")
            errors.push("Provider API is missing required method " + methodName + ".");
    }
    return errors;
}
