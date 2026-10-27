// GitHubProviderProperties.js - declares GitHub API endpoints and limits.

.pragma library

// Fill the provider declaration with GitHub endpoints, request limits and retry policy.
function create(providerProperties) {
    var properties = providerProperties.create();
    properties.providerId = "github";
    properties.displayName = "GitHub";
    properties.apiBaseUrl = "https://api.github.com";
    properties.webBaseUrl = "https://github.com";
    properties.avatarsBaseUrl = "https://avatars.githubusercontent.com";
    properties.inboxPath = "/notifications";
    properties.threadPath = "/notifications/threads";
    properties.apiVersion = "2022-11-28";
    properties.avatarSizePx = 128;
    properties.messagesPerPage = 50;
    properties.minPollIntervalSeconds = 60;
    properties.defaultPollIntervalSeconds = 120;
    properties.firstRunPageLimit = 3;
    properties.maximumPageLimit = 20;
    properties.maximumConcurrentRequests = 3;
    properties.http2RetryCount = 2;
    properties.http2RetryDelayBaseSeconds = 1;
    properties.requestRetryCount = 2;
    properties.requestRetryMaxTimeSeconds = 45;
    return properties;
}
