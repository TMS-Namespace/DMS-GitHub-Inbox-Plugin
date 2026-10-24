// CacheSerialization.test.js - covers cache format adapters and legacy migration.

"use strict";

const assert = require("node:assert/strict");
const { createRegistry, loadModule } = require("../../../audit/QmlJavaScript");
const cache = loadModule("src/JS/Storage/CacheSerialization.js", createRegistry());

const migrated = cache.normalizeDoneThreadState([" thread-a ", "", "thread-b", "thread-a"]);
assert.deepEqual(Object.keys(migrated).sort(), ["thread-a", "thread-b"]);
assert.deepEqual(JSON.parse(JSON.stringify(migrated["thread-a"])), {
    source: "local",
    updatedAt: "",
    savedAt: 0
});

const normalized = cache.normalizeDoneThreadState({
    " thread-c ": { source: "github", updatedAt: "2026-10-22T12:00:00Z", savedAt: 9 },
    invalid: null,
    array: []
});
assert.deepEqual(Object.keys(normalized), ["thread-c"]);
assert.equal(normalized["thread-c"].source, "github");

const payload = cache.decodePayload(
    {
        ...cache.emptyPayload(),
        version: 1,
        lastFetched: 42,
        notifications: [{ threadId: "thread-a" }],
        doneThreadState: ["thread-a"]
    },
    1
);
assert.equal(payload.lastFetched, 42);
assert.equal(payload.doneThreadState["thread-a"].source, "local");
const scheduled = cache.decodePayload(
    { ...cache.emptyPayload(), version: 1, lastFetched: 1000, pollIntervalMs: 120000 },
    1
);
assert.equal(scheduled.pollIntervalMs, 120000);
assert.equal(cache.serializePayload(scheduled).pollIntervalMs, 120000);
assert.equal(cache.decodePayload({ ...scheduled, pollIntervalMs: "120000" }, 1).pollIntervalMs, 0);
assert.throws(
    () => cache.decodePayload({ version: 2, notifications: [{ threadId: "new" }] }, 1),
    (error) => error.name === "PluginError"
);
for (const notification of [null, [], {}, { threadId: 42 }, { threadId: "" }])
    assert.throws(
        () => cache.decodePayload({ ...payload, notifications: [notification] }, 1),
        (error) => error.name === "PluginError" && /notification record/.test(error.details)
    );
for (const avatarMap of [{ "../outside": { localFile: "outside.png" } }, { octo: { localFile: "../outside.png" } }])
    assert.throws(
        () => cache.decodePayload({ ...payload, avatarMap }, 1),
        (error) => error.name === "PluginError" && /avatar/.test(error.details)
    );
assert.equal(
    cache.avatarLocalUrl({ localFile: "octo.png" }, "/cache/root", "avatars"),
    "file:///cache/root/avatars/octo.png"
);
// Accept current and legacy cache records, but never resolve paths outside the avatar directory.
assert.equal(
    cache.avatarLocalUrl({ localFile: "renovate[bot].png" }, "/cache/root", "avatars"),
    "file:///cache/root/avatars/renovate[bot].png"
);
assert.equal(
    cache.avatarLocalUrl({ localUrl: "file:///cache/root/avatars/octo.png" }, "/cache/root", "avatars"),
    "file:///cache/root/avatars/octo.png"
);
for (const filename of [
    "../../outside.png",
    "/outside.png",
    "%2e%2e.png",
    "octo.png?secret",
    "octo.png#fragment",
    "bad name.png",
    "octo.svg"
])
    assert.equal(cache.avatarLocalUrl({ localFile: filename }, "/cache/root", "avatars"), "");
assert.equal(cache.avatarLocalUrl({ localUrl: "file:///outside/octo.png" }, "/cache/root", "avatars"), "");
assert.equal(
    cache.avatarLocalUrl({ localUrl: "file:///cache/root/avatars/../outside.png" }, "/cache/root", "avatars"),
    ""
);
assert.deepEqual(
    JSON.parse(JSON.stringify(cache.serializePayload({ ...payload, doneThreadState: ["thread-b"] }))).doneThreadState,
    {
        "thread-b": { source: "local", updatedAt: "", savedAt: 0 }
    }
);

console.log("Cache serialization tests passed.");
