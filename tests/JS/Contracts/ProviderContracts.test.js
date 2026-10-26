// ProviderContracts.test.js - audits the GitHub provider declaration and facade.

"use strict";

const assert = require("node:assert/strict");
const { createRegistry, loadModule: loadQmlModule } = require("../../../audit/QmlJavaScript");
const registry = createRegistry();

// Preserve one module identity while exposing the requested test surface.
function loadModule(relativePath, exportedNames, dependencies = {}) {
    const module = loadQmlModule(relativePath, registry, dependencies);
    return Object.fromEntries(exportedNames.map((name) => [name, module[name]]));
}

const providerType = loadModule("src/JS/Contracts/ProviderType.js", ["GitHub"]);
const providerApi = loadModule("src/JS/Contracts/ProviderApi.js", ["create", "validate", "requiredMethods"]);
const providerProperties = loadModule("src/JS/Contracts/ProviderProperties.js", ["create", "validate"]);
const githubProperties = loadModule("src/JS/Integrations/GitHub/GitHubProviderProperties.js", ["create"]);
const githubHelpers = loadModule(
    "src/JS/Integrations/GitHub/GitHubHelpers.js",
    [
        "isSafeGitHubLogin",
        "isSafeGitHubApiUrl",
        "isAllowedAvatarUrl",
        "isSafeGitHubWebUrl",
        "parseMessagesPayload",
        "appendBoundedAvatarRequests",
        "pluginDataBool",
        "pollIntervalMs",
        "relativeTimeFromIso",
        "reasonLabel",
        "formatCountValue",
        "subjectIconName",
        "subjectDisplayLabel",
        "subjectReferenceLabel"
    ],
    { Date, JSON, parseInt, isNaN }
);
const githubApi = loadModule("src/JS/Integrations/GitHub/GitHubProviderApi.js", ["create"]);
const providerRegistry = loadModule("src/JS/Integrations/ProviderRegistry.js", [
    "supportedProviderTypes",
    "createProvider"
]);

const providerModules = {
    providerType,
    providerApi,
    providerProperties,
    githubApi,
    githubProperties,
    githubHelpers
};
const providerTypes = providerRegistry.supportedProviderTypes(providerType);
assert.deepEqual(Array.from(providerTypes), ["github"]);

const provider = providerRegistry.createProvider(providerType.GitHub, providerModules);
assert.equal(provider.error, "");
assert.equal(provider.api.providerId, provider.properties.providerId);
assert.deepEqual(Array.from(providerApi.validate(provider.api, provider.properties)), []);
assert.equal(provider.api.buildInboxUrl(), "https://api.github.com/notifications");
assert.equal(provider.api.buildThreadActionRequest("done", "42").method, "DELETE");
assert.equal(provider.api.buildThreadActionRequest("unread", "42").payloadJson, '{"read":false}');
assert.equal(provider.api.buildThreadActionRequest("read", "../42"), null);
assert.equal(provider.api.buildRepositoryReadRequest("owner/repo").method, "PUT");
assert.deepEqual(Array.from(provider.api.buildCurlRetryArguments()), [
    "--retry",
    "2",
    "--retry-connrefused",
    "--retry-max-time",
    "45"
]);
assert.deepEqual(JSON.parse(JSON.stringify(provider.api.getRetryPolicy())), {
    retryCount: 2,
    maximumRetryTimeSeconds: 45,
    http2RetryCount: 2,
    http2RetryDelayBaseSeconds: 1
});
assert.equal(provider.api.buildRepositoryReadRequest("owner/../repo"), null);
assert.equal(
    provider.api.buildRepositoryApiUrl("owner/repo", "pulls/42/reviews"),
    "https://api.github.com/repos/owner/repo/pulls/42/reviews"
);
assert.equal(provider.api.buildRepositoryApiUrl("owner/repo", "../notifications"), "");
assert.equal(
    provider.api.buildAvatarUrl("renovate[bot]"),
    "https://avatars.githubusercontent.com/renovate%5Bbot%5D?size=128"
);
assert.equal(provider.api.buildAvatarUrl("../unsafe"), "");
assert.equal(provider.api.isAllowedAvatarUrl(provider.api.buildAvatarUrl("renovate[bot]")), true);
assert.equal(provider.api.buildRepositoryWebUrl("owner/repo"), "https://github.com/owner/repo");
assert.equal(provider.api.buildRepositoryWebUrl("owner/../repo"), "");
assert.equal(provider.api.buildUserProfileUrl("octocat"), "https://github.com/octocat");
assert.equal(provider.api.isAllowedWebUrl("https://github.com/owner/repo/pull/42"), true);
assert.equal(provider.api.isAllowedWebUrl("https://github.com/owner/repo?query=user%3Aoctocat"), true);
assert.equal(provider.api.isAllowedWebUrl("https://github.com.evil.test/owner/repo"), false);
assert.equal(provider.api.isAllowedWebUrl("https://github.com/owner/../secret"), false);
assert.equal(provider.api.isSafeLogin("octocat"), true);
assert.equal(provider.api.reasonLabel("ci_activity"), "CI Activity");
assert.equal(provider.api.subjectDisplayLabel("PullRequest"), "PR");

const unsupportedProvider = providerRegistry.createProvider("unsupported", providerModules);
assert.equal(unsupportedProvider.api, null);
assert.match(unsupportedProvider.error, /Unsupported provider/);

const invalidProperties = { ...provider.properties, unexpected: true };
assert.match(providerProperties.validate(invalidProperties).join(" "), /Unknown provider property/);
const excessiveRetryProperties = { ...provider.properties, requestRetryCount: 6 };
assert.match(providerProperties.validate(excessiveRetryProperties).join(" "), /requestRetryCount/);

console.log("Provider contract and GitHub facade tests passed");
