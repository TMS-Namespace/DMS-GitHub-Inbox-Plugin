// InboxOperationRules.test.js - verifies thread selection and immutable inbox action results.

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.resolve(__dirname, "../../../src/JS/Helpers/InboxOperationRules.js"), "utf8");
const moduleObject = { exports: {} };
vm.runInNewContext(
    source.replace(/^\.pragma\s+library\s*$/m, "") +
        "\nmodule.exports = { collectThreadIds, applyMessageAction, reconcileReturnedDone, pruneDoneState };",
    { module: moduleObject }
);
const rules = moduleObject.exports;
const messages = [
    { threadId: "a", repository: "one", unread: true },
    { threadId: "b", repository: "one", unread: false },
    { threadId: "c", repository: "two", unread: true }
];
const clean = (value) => JSON.parse(JSON.stringify(value));
const apply = (action, thread, repository, ids) =>
    clean(rules.applyMessageAction(action, thread || "", repository || "", messages, ids || []));

assert.deepEqual(clean(rules.collectThreadIds([messages[0], messages[0], null, messages[1], messages[2]], true)), [
    "a",
    "c"
]);
assert.deepEqual(clean(rules.collectThreadIds(messages, false)), ["a", "b", "c"]);
assert.deepEqual(
    apply("all_read").items.map((item) => item.unread),
    [false, false, false]
);
assert.deepEqual(
    apply("repo_read", "", "one").items.map((item) => item.unread),
    [false, false, true]
);
assert.deepEqual(
    apply("threads_read", "", "", ["c"]).items.map((item) => item.unread),
    [true, false, false]
);
assert.deepEqual(
    apply("thread_read_pending", "a").items.map((item) => item.unread),
    [false, false, true]
);
assert.deepEqual(
    apply("thread_unread", "b").items.map((item) => item.unread),
    [true, true, true]
);
assert.deepEqual(
    apply("repo_done", "", "one", ["a", "c"]).items.map((item) => item.threadId),
    ["b", "c"]
);
assert.deepEqual(
    apply("threads_done", "", "", ["a", "c"]).items.map((item) => item.threadId),
    ["b"]
);
assert.deepEqual(
    apply("thread_done", "b").items.map((item) => item.threadId),
    ["a", "c"]
);
assert.deepEqual(
    messages.map((item) => item.unread),
    [true, false, true]
);
assert.equal(apply("thread_read", "a").unreadChanged, true);

const done = {
    inferred: { source: "github_missing_from_complete_refresh", savedAt: 10 },
    local: { source: "local", updatedAt: "2026-01-01T00:00:00Z", savedAt: 10 },
    unknown: { source: "local", updatedAt: "", savedAt: 0 }
};
const boundary = Date.parse(done.local.updatedAt);
assert.strictEqual(rules.reconcileReturnedDone(done, [{ threadId: "local", updatedAtMs: boundary }]), done);
assert.deepEqual(
    Object.keys(
        rules.reconcileReturnedDone(done, [{ threadId: "inferred" }, { threadId: "local", updatedAtMs: boundary + 1 }])
    ),
    ["unknown"]
);
assert.strictEqual(rules.pruneDoneState(done, 5), done);
assert.deepEqual(Object.keys(rules.pruneDoneState(done, boundary + 1)), ["unknown"]);
assert.deepEqual(Object.keys(done), ["inferred", "local", "unknown"]);

console.log("Inbox operation rule checks passed");
