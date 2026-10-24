// Notifications.live.test.js - performs a read-only authenticated GitHub inbox request.

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "../../../../");
const token = process.env.GITHUB_TOKEN;

// Exercise the same module graph as the runtime provider facade.
function loadGitHubHelpers() {
    const { createRegistry, loadModule } = require("../../../../audit/QmlJavaScript");
    return loadModule("src/JS/Integrations/GitHub/GitHubHelpers.js", createRegistry());
}

async function main() {
    const response = await fetch("https://api.github.com/notifications?per_page=5", {
        headers: {
            Accept: "application/vnd.github+json",
            Authorization: `Bearer ${token}`,
            "X-GitHub-Api-Version": "2022-11-28"
        },
        signal: AbortSignal.timeout(20000)
    });
    assert.equal(response.status, 200, `GitHub returned HTTP ${response.status}.`);

    const payloadText = await response.text();
    const parsed = loadGitHubHelpers().parseMessagesPayload(payloadText);
    assert.equal(typeof parsed.error, "undefined", "GitHub inbox response did not parse.");
    assert.ok(Array.isArray(parsed.items), "Parsed notifications should be a list.");
    assert.ok(parsed.items.length <= 5, "The test must keep its response bounded.");
    process.stdout.write(`Live GitHub inbox request passed (${parsed.items.length} notifications).\n`);
}

if (!token) {
    process.stderr.write("Set GITHUB_TOKEN to run the opt-in GitHub integration test.\n");
    process.exitCode = 1;
} else {
    main().catch((error) => {
        process.stderr.write(`Live GitHub inbox request failed: ${error.message}\n`);
        process.exitCode = 1;
    });
}
