// InboxParserBackgroundWorker.test.js - exercises WorkerScript parser behavior.

"use strict";

const assert = require("node:assert/strict");
const sentMessages = [];
const workerScript = { onMessage: null, sendMessage: (message) => sentMessages.push(message) };
const { createRegistry, loadModule } = require("../../../../audit/QmlJavaScript");
const context = loadModule("src/JS/Integrations/GitHub/InboxParserBackgroundWorker.js", createRegistry(), {
    WorkerScript: workerScript
});
assert.equal(
    context.normalizeApiUrlWorker("https://api.github.com/repos/o/r/issues/42?per_page=100"),
    "https://api.github.com/repos/o/r/issues/42"
);
assert.equal(context.normalizeApiUrlWorker("https://api.github.com/repos/o/../secret"), "");

const notification = (threadId, updatedAt) => ({
    id: threadId,
    unread: true,
    updated_at: updatedAt,
    subject: { type: "PullRequest", title: "Update", url: `https://api.github.com/repos/o/r/pulls/${threadId}` },
    repository: { full_name: "o/r", html_url: "https://github.com/o/r", owner: { login: "o" } }
});

const boundary = "PAGE_BOUNDARY";
workerScript.onMessage({
    seq: 4,
    payloadText: [
        JSON.stringify([notification("42", "2026-04-03T00:00:00Z")]),
        JSON.stringify([notification("41", "2026-04-02T00:00:00Z")]),
        JSON.stringify([notification("41", "2026-04-02T00:00:00Z")]),
        "[]"
    ].join(`\n${boundary}\n`),
    separator: boundary,
    allSegmentCount: 2,
    pageSize: 2,
    chunkSize: 40
});

assert.equal(sentMessages[0].phase, "begin");
assert.equal(sentMessages[0].totalCount, 2);
assert.equal(sentMessages[0].isComplete, true);
assert.equal(sentMessages[1].phase, "chunk");
assert.equal(sentMessages[1].isLast, true);
assert.equal(sentMessages[1].items.find((item) => item.threadId === "41").participated, true);
assert.equal(sentMessages[1].items.find((item) => item.threadId === "42").participated, false);
assert.equal(sentMessages[1].items.find((item) => item.threadId === "42").updatedAt, "2026-04-03T00:00:00Z");
assert.equal(
    sentMessages[1].items.find((item) => item.threadId === "42").updatedAtMs,
    Date.parse("2026-04-03T00:00:00Z")
);

sentMessages.length = 0;
workerScript.onMessage({ seq: 5, payloadText: "[]", allSegmentCount: 1, separator: boundary });
assert.match(sentMessages[0].error, /incomplete/i);
assert.equal(sentMessages[0].failure.name, "PluginError");
assert.equal(sentMessages[0].failure.retryable, true);

console.log("Inbox parser behavior tests passed");
