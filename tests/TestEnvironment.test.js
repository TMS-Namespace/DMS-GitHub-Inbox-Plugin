// TestEnvironment.test.js - verifies command substitution and cache isolation without external services.

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const { spawnSync } = require("node:child_process");
const { createTestEnvironment } = require("./TestEnvironment");

const testEnvironment = createTestEnvironment();
try {
    const environment = testEnvironment.environment;
    assert.notEqual(environment.XDG_CACHE_HOME, process.env.XDG_CACHE_HOME);
    assert.equal(environment.HOME, process.env.HOME);
    assert.equal(environment.QT_FATAL_WARNINGS, "0");
    assert.equal(spawnSync("secret-tool", ["lookup"], { env: environment }).status, 1);
    assert.equal(spawnSync("secret-tool", ["store"], { env: environment, input: "test-only" }).status, 0);
    assert.equal(spawnSync("dms", ["notify", "Test"], { env: environment }).status, 0);
    assert.equal(spawnSync("curl", ["https://example.invalid"], { env: environment }).status, 99);
    assert.equal(testEnvironment.blockedRequests(), "curl");
    assert.equal(spawnSync("dms", ["dl", "https://example.invalid"], { env: environment }).status, 99);
    assert.equal(testEnvironment.blockedRequests(), "curl\ndms dl");
} finally {
    testEnvironment.dispose();
}
assert.equal(fs.existsSync(testEnvironment.directory), false);
console.log("Test environment isolation checks passed");
