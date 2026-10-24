// CacheBackgroundWorker.test.js - verifies cache worker error and success paths.

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sourcePath = path.resolve(__dirname, "../../../src/JS/BackgroundWorkers/CacheBackgroundWorker.js");
const sentMessages = [];
const workerScript = { onMessage: null, sendMessage: (message) => sentMessages.push(message) };
const { createRegistry, loadModule } = require("../../../audit/QmlJavaScript");
loadModule("src/JS/BackgroundWorkers/CacheBackgroundWorker.js", createRegistry(), { WorkerScript: workerScript });

const validCache = {
    version: 1,
    lastFetched: 0,
    notifications: [],
    authorsByThread: {},
    authorFetchedAt: {},
    avatarMap: {},
    doneThreadState: {}
};
workerScript.onMessage({ action: "parseCache", seq: 1, text: JSON.stringify(validCache) });
assert.equal(sentMessages.pop().data.version, 1);

workerScript.onMessage({ action: "parseCache", seq: 2, text: "{" });
const parseError = sentMessages.pop();
assert.equal(parseError.action, "cacheError");
assert.equal(parseError.seq, 2);

workerScript.onMessage({
    action: "parseCache",
    seq: 5,
    text: JSON.stringify({ ...validCache, notifications: {} })
});
const invalidShapeError = sentMessages.pop();
assert.equal(invalidShapeError.action, "cacheError");
assert.match(invalidShapeError.failure.details, /notifications are invalid/);

workerScript.onMessage({
    action: "parseCache",
    seq: 6,
    text: JSON.stringify({ ...validCache, avatarMap: { "../../outside": { localFile: "outside.png" } } })
});
const unsafeAvatarLoginError = sentMessages.pop();
assert.equal(unsafeAvatarLoginError.action, "cacheError");
assert.match(unsafeAvatarLoginError.failure.details, /invalid avatar login/);

workerScript.onMessage({ action: "stringifyCache", seq: 3, payload: validCache });
assert.equal(JSON.parse(sentMessages.pop().text).version, 1);

workerScript.onMessage({ action: "stringifyCache", seq: 4, payload: undefined });
const stringifyError = sentMessages.pop();
assert.equal(stringifyError.action, "cacheError");
assert.equal(stringifyError.operation, "stringifyCache");

console.log("Cache worker behavior tests passed");
workerScript.onMessage({
    action: "parseCache",
    seq: 7,
    text: JSON.stringify({ ...validCache, notifications: [null] })
});
assert.equal(sentMessages.pop().failure.name, "PluginError");
