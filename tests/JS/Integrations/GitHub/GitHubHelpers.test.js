// GitHubHelpers.test.js - verifies notification parsing and display policies.

"use strict";

const assert = require("node:assert/strict");
const { createRegistry, loadModule } = require("../../../../audit/QmlJavaScript");
const helpers = loadModule("src/JS/Integrations/GitHub/GitHubHelpers.js", createRegistry());

const makeNotification = (id, updatedAt, options = {}) => ({
    id,
    unread: options.unread === undefined ? true : options.unread,
    reason: options.reason || "mention",
    updated_at: updatedAt,
    subject: {
        type: options.type || "PullRequest",
        title: options.title || "Change title",
        url: options.subjectUrl || `https://api.github.com/repos/owner/repo/pulls/${id}`
    },
    repository: {
        full_name: "owner/repo",
        html_url: "https://github.com/owner/repo",
        owner: { login: "owner", avatar_url: "https://avatars.githubusercontent.com/u/1" }
    }
});

assert.equal(helpers.pluginDataBool("yes", false), true);
assert.equal(helpers.pluginDataBool("off", true), false);
assert.equal(helpers.pollIntervalMs("30", 120, 60), 120000);
assert.equal(helpers.pollIntervalMs("180", 120, 60), 180000);
assert.equal(helpers.isSafeGitHubLogin("renovate[bot]"), true);
assert.equal(helpers.isSafeGitHubLogin("../outside"), false);
assert.equal(helpers.isSafeGitHubApiUrl("https://api.github.com/repos/o/r/pulls/42?per_page=100"), true);
assert.equal(helpers.isSafeGitHubApiUrl("https://api.github.com.evil.test/repos/o/r/issues/42"), false);
assert.equal(helpers.isSafeGitHubApiUrl("https://api.github.com/repos/o/../private"), false);
assert.equal(helpers.isSafeGitHubApiUrl("https://api.github.com/repos/o/r/pulls/42?x=%0A"), false);
assert.equal(helpers.isSafeGitHubApiUrl("https://api.github.com/repos/o/r/pulls/42?x=%ZZ"), false);
assert.equal(helpers.isAllowedAvatarUrl("https://avatars.githubusercontent.com/u/123?v=4"), true);
assert.equal(helpers.isAllowedAvatarUrl("https://github.com/apps/copilot.png?size=128"), true);
assert.equal(helpers.isAllowedAvatarUrl("https://avatars.evil.test/u/123"), false);
assert.equal(helpers.isAllowedAvatarUrl("https://avatars.githubusercontent.com/../secret"), false);
assert.equal(helpers.isSafeGitHubWebUrl("https://github.com/o/r/pull/1"), true);
assert.equal(helpers.isSafeGitHubWebUrl("https://github.com.evil.test/o/r"), false);
assert.equal(helpers.isSafeGitHubWebUrl("https://github.com/o/../secret"), false);
const boundedAvatarQueue = helpers.appendBoundedAvatarRequests(
    [{ login: "queued", remoteUrl: "https://avatars.githubusercontent.com/u/1" }],
    [
        { login: "queued", remoteUrl: "https://avatars.githubusercontent.com/u/2" },
        { login: "active", remoteUrl: "https://avatars.githubusercontent.com/u/3" },
        { login: "bad/../login", remoteUrl: "https://avatars.githubusercontent.com/u/4" },
        { login: "next", remoteUrl: "https://avatars.githubusercontent.com/u/5" }
    ],
    { active: true },
    2
);
assert.deepEqual(
    Array.from(boundedAvatarQueue, (request) => request.login),
    ["queued", "next"]
);
assert.equal(
    helpers.appendBoundedAvatarRequests(
        [],
        [
            { login: "one", remoteUrl: "https://avatars.githubusercontent.com/u/1" },
            { login: "two", remoteUrl: "https://avatars.githubusercontent.com/u/2" }
        ],
        {},
        1
    ).length,
    1
);

const parsed = helpers.parseMessagesPayload(
    JSON.stringify([
        makeNotification("old", "2026-01-01T00:00:00Z"),
        makeNotification("new", "2026-01-03T00:00:00Z", { unread: false })
    ])
);
assert.equal(parsed.unreadCount, 1);
assert.deepEqual(
    Array.from(parsed.items, (item) => item.threadId),
    ["old", "new"]
);
assert.equal(parsed.items[0].webUrl, "https://github.com/owner/repo/pull/old");
assert.throws(
    () => helpers.parseMessagesPayload("{"),
    (error) => error.name === "PluginError" && /invalid JSON/i.test(error.userMessage)
);

const splitToken = "PAGE_BOUNDARY";
const allFirstPage = JSON.stringify([makeNotification("thread-8", "2026-01-08T00:00:00Z")]);
const allSecondPage = JSON.stringify([makeNotification("thread-7", "2026-01-07T00:00:00Z")]);
const participatingFirstPage = JSON.stringify([makeNotification("thread-7", "2026-01-07T00:00:00Z")]);
const participatingSecondPage = "[]";
const segmented = [allFirstPage, allSecondPage, participatingFirstPage, participatingSecondPage].join(
    `\n${splitToken}\n`
);
const merged = helpers.parseMessagesWithParticipationSegments(segmented, splitToken, 2);
assert.equal(merged.items.length, 2);
assert.equal(merged.items.find((item) => item.threadId === "thread-7").participated, true);
assert.equal(merged.items.find((item) => item.threadId === "thread-8").participated, false);
assert.throws(
    () => helpers.parseMessagesWithParticipationSegments(allFirstPage, splitToken, 1),
    (error) => error.name === "PluginError" && error.retryable && /incomplete/i.test(error.userMessage)
);

assert.equal(helpers.subjectDisplayLabel("CheckSuite"), "Workflow");
assert.equal(helpers.subjectDisplayLabel("PullRequest"), "PR");
assert.equal(
    helpers.subjectReferenceNumber("CheckSuite", "https://api.github.com/repos/o/r/actions/runs/3113", ""),
    "3113"
);
assert.equal(helpers.reasonLabel("review_requested"), "Review Requested");
assert.equal(helpers.resolveWebUrl(null), "https://github.com/notifications");

console.log("GitHubHelpers behavior tests passed");
