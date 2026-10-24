// AuthorTools.test.js - verifies participant helpers through the public provider facade.

"use strict";

const assert = require("node:assert/strict");
const { createRegistry, loadModule } = require("../../../../audit/QmlJavaScript");
const registry = createRegistry();
const baseApi = loadModule("src/JS/Contracts/ProviderApi.js", registry);
const baseProperties = loadModule("src/JS/Contracts/ProviderProperties.js", registry);
const properties = loadModule("src/JS/Integrations/GitHub/GitHubProviderProperties.js", registry).create(
    baseProperties
);
const helpers = loadModule("src/JS/Integrations/GitHub/GitHubHelpers.js", registry);
const facade = loadModule("src/JS/Integrations/GitHub/GitHubProviderApi.js", registry).create(
    baseApi,
    properties,
    helpers
);
const authors = facade.createAuthorTools("per_page=100");
const repositoryApi = "https://api.github.com/repos/owner/repository";
const pullApi = repositoryApi + "/pulls/42";

assert.equal(authors.apiUrlFromWebUrl("https://github.com/owner/repository/pull/42#discussion"), pullApi);
assert.equal(
    authors.apiUrlFromWebUrl("https://github.com/owner/repository/actions/runs/123"),
    repositoryApi + "/actions/runs/123"
);
assert.equal(authors.apiUrlFromWebUrl("https://github.com.evil.test/owner/repository/pull/42"), "");
assert.equal(authors.apiUrlFromWebUrl("https://github.com/owner/../pull/42"), "");
assert.equal(authors.normalizeApiUrl(pullApi + "?per_page=100"), pullApi);
assert.equal(authors.normalizeApiUrl("https://api.github.com.evil.test/repos/owner/repository/pulls/42"), "");
assert.deepEqual(Array.from(authors.buildAuthorFetchUrls(pullApi, "PullRequest", false)), [pullApi]);
assert.deepEqual(Array.from(authors.buildAuthorFetchUrls(pullApi, "PullRequest", true)), [
    pullApi,
    repositoryApi + "/issues/42/timeline?per_page=100"
]);
assert.deepEqual(Array.from(authors.buildAuthorFetchUrls(repositoryApi + "/check-suites/7", "CheckSuite", true)), [
    repositoryApi + "/check-suites/7",
    repositoryApi + "/check-suites/7/check-runs?per_page=100",
    repositoryApi + "/actions/runs?per_page=5"
]);
assert.equal(
    authors.resolveSubjectApiUrlForAuthors({ webUrl: "https://github.com/owner/repository/pull/42" }),
    pullApi
);
assert.equal(
    authors.resolveSubjectApiUrlForAuthors({ repository: "owner/repository", subjectType: "CheckSuite" }),
    repositoryApi + "/actions/runs"
);
assert.equal(authors.resolveSubjectApiUrlForAuthors(null), "");

const firstAuthor = { login: "Alice", type: "User", html_url: "https://github.com/Alice" };
const secondAuthor = { login: "Bob", type: "User", html_url: "https://github.com/Bob" };
const parsed = authors.parseSubjectAuthors(
    JSON.stringify({
        user: firstAuthor,
        comments: [{ user: secondAuthor }, { user: firstAuthor }],
        repository: { owner: { login: "organization", type: "Organization" } }
    })
);
assert.deepEqual(
    Array.from(parsed, (author) => author.login),
    ["Alice", "Bob"]
);
assert.deepEqual(Array.from(authors.parseSubjectAuthors("{")), []);
assert.equal(authors.isLikelyGitHubUserObject({ type: "Organization" }, "organization", "", ""), false);
assert.equal(authors.isLikelyGitHubLogin("../invalid"), false);
assert.equal(authors.authorKey(" ALICE ", "", ""), "alice");
assert.equal(authors.authorAvatarUrl({ login: "Alice" }), facade.buildAvatarUrl("Alice"));
assert.equal(
    authors.authorAvatarUrl({ htmlUrl: "https://github.com/apps/copilot" }),
    facade.buildAppAvatarUrl("copilot")
);
const merged = authors.mergeAuthorLists(parsed, [
    { login: "alice", type: "User" },
    { login: "Carol", type: "User" }
]);
assert.deepEqual(
    Array.from(merged, (author) => author.login),
    ["Alice", "Bob", "Carol"]
);

const splitToken = "AUTHOR_SECTION";
const sections = [JSON.stringify({ user: firstAuthor }), "{", JSON.stringify({ user: secondAuthor })].join(
    "\n" + splitToken + "\n"
);
assert.deepEqual(
    Array.from(authors.parseSubjectAuthorsMulti(sections, splitToken), (author) => author.login),
    ["Alice", "Bob"]
);
const expansionSections = [
    JSON.stringify({ issue_url: repositoryApi + "/issues/42" }),
    JSON.stringify({ pull_request_url: pullApi }),
    JSON.stringify({ url: pullApi })
].join("\n" + splitToken + "\n");
assert.deepEqual(Array.from(authors.parseSubjectExpansionUrls(expansionSections, splitToken)), [
    repositoryApi + "/issues/42",
    pullApi
]);
assert.equal(
    facade.createAuthorTools("per_page=20").buildAuthorFetchUrls(pullApi, "PullRequest", true)[1],
    repositoryApi + "/issues/42/timeline?per_page=20"
);
assert.equal(
    authors.buildAuthorFetchUrls(pullApi, "PullRequest", true)[1],
    repositoryApi + "/issues/42/timeline?per_page=100"
);

console.log("Author participant helper tests passed");
