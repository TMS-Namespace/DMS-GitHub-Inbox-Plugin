// SetupSymlink.test.js - verifies installation paths without touching the user's plugin directory.
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "github-inbox-install-"));
try {
    for (const customConfig of [false, true]) {
        const home = path.join(temporaryDirectory, customConfig ? "custom-home" : "default-home");
        const config = customConfig ? path.join(temporaryDirectory, "custom-config") : path.join(home, ".config");
        const environment = { ...process.env, HOME: home };
        if (customConfig) environment.XDG_CONFIG_HOME = config;
        else delete environment.XDG_CONFIG_HOME;
        for (let attempt = 0; attempt < 2; attempt++) {
            const result = spawnSync("bash", [path.join(root, "support/setup-symlink.sh")], {
                env: environment,
                encoding: "utf8"
            });
            assert.equal(result.status, 0, result.stderr);
            assert.equal(fs.readlinkSync(path.join(config, "dms/plugins/GitHubInboxPlugin")), root);
        }
        assert.equal(fs.existsSync(path.join(home, ".config/DankMaterialShell")), false);
    }
    const manifest = JSON.parse(fs.readFileSync(path.join(root, "plugin.json"), "utf8"));
    assert.equal(manifest.requires_dms, ">=2.0.0");
} finally {
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
}
console.log("Dux installation and minimum-version checks passed");
