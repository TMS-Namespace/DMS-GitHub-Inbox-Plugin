// ProviderProperties.js - creates and validates provider declaration data.

.pragma library

// Construct an independent value implementing this module's public contract.
function create() {
    return {
        providerId: "",
        displayName: "",
        apiBaseUrl: "",
        webBaseUrl: "",
        avatarsBaseUrl: "",
        inboxPath: "",
        threadPath: "",
        apiVersion: "",
        avatarSizePx: 0,
        messagesPerPage: 0,
        minPollIntervalSeconds: 0,
        defaultPollIntervalSeconds: 0,
        firstRunPageLimit: 0,
        maximumPageLimit: 0,
        maximumConcurrentRequests: 0,
        http2RetryCount: 0,
        http2RetryDelayBaseSeconds: 0,
        requestRetryCount: 0,
        requestRetryMaxTimeSeconds: 0
    };
}

// Return declaration errors before a provider is exposed to callers.
function validate(properties) {
    var expected = create();
    if (!properties || typeof properties !== "object" || Array.isArray(properties))
        return ["Provider properties must be an object."];

    var propertyNames = Object.keys(properties);
    var expectedNames = Object.keys(expected);
    var errors = [];
    for (var nameIndex = 0; nameIndex < propertyNames.length; nameIndex++)
        if (!expected.hasOwnProperty(propertyNames[nameIndex]))
            errors.push("Unknown provider property: " + propertyNames[nameIndex]);
    for (var expectedIndex = 0; expectedIndex < expectedNames.length; expectedIndex++)
        if (!properties.hasOwnProperty(expectedNames[expectedIndex]))
            errors.push("Missing provider property: " + expectedNames[expectedIndex]);

    var stringNames = [
        "providerId",
        "displayName",
        "apiBaseUrl",
        "webBaseUrl",
        "avatarsBaseUrl",
        "inboxPath",
        "threadPath",
        "apiVersion"
    ];
    for (var stringIndex = 0; stringIndex < stringNames.length; stringIndex++) {
        var stringName = stringNames[stringIndex];
        if (typeof properties[stringName] !== "string" || !properties[stringName])
            errors.push("Provider property " + stringName + " must be a non-empty string.");
    }

    var limitNames = [
        "avatarSizePx",
        "messagesPerPage",
        "minPollIntervalSeconds",
        "defaultPollIntervalSeconds",
        "firstRunPageLimit",
        "maximumPageLimit",
        "maximumConcurrentRequests",
        "http2RetryDelayBaseSeconds",
        "requestRetryMaxTimeSeconds"
    ];
    for (var limitIndex = 0; limitIndex < limitNames.length; limitIndex++) {
        var limitName = limitNames[limitIndex];
        if (!Number.isInteger(properties[limitName]) || properties[limitName] <= 0)
            errors.push("Provider property " + limitName + " must be a positive integer.");
    }

    if (
        !Number.isInteger(properties.requestRetryCount) ||
        properties.requestRetryCount < 0 ||
        properties.requestRetryCount > 5
    )
        errors.push("Provider property requestRetryCount must be an integer from 0 through 5.");
    if (
        !Number.isInteger(properties.http2RetryCount) ||
        properties.http2RetryCount < 0 ||
        properties.http2RetryCount > 5
    )
        errors.push("Provider property http2RetryCount must be an integer from 0 through 5.");
    if (properties.requestRetryMaxTimeSeconds > 120)
        errors.push("Provider property requestRetryMaxTimeSeconds cannot exceed 120 seconds.");

    if (properties.defaultPollIntervalSeconds < properties.minPollIntervalSeconds)
        errors.push("The default poll interval cannot be below the provider minimum.");
    if (properties.firstRunPageLimit > properties.maximumPageLimit)
        errors.push("The first-run page limit cannot exceed the provider maximum.");
    return errors;
}
