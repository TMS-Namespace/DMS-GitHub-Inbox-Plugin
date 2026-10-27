// TestEnvironment.js - isolates headless runtime state and external commands from the user's session.

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// Keep the real Qt runtime while replacing commands that would reach credentials, the network or the desktop.
function createTestEnvironment() {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), "github-inbox-tests-"));
    for (const name of ["bin", "cache", "config", "data", "tmp", "modules"]) fs.mkdirSync(path.join(directory, name));
    // Stub DMS UI only; process and WorkerScript behavior must use installed runtime types.
    fs.symlinkSync(path.resolve(__dirname, "HostModules/qs"), path.join(directory, "modules/qs"), "dir");
    // Quickshell resolves qs.* from its configuration root rather than from a standard module directory.
    const nativeRoot = path.join(directory, "native");
    fs.mkdirSync(nativeRoot);
    for (const name of ["Common", "DCommon", "Modules", "Services"])
        fs.symlinkSync(path.resolve(__dirname, "HostModules/qs", name), path.join(nativeRoot, name), "dir");
    fs.symlinkSync(path.resolve(__dirname, "../src"), path.join(nativeRoot, "source"), "dir");
    fs.writeFileSync(
        path.join(nativeRoot, "RuntimeChecks.qml"),
        fs.readFileSync(path.join(__dirname, "Runtime/RuntimeChecks.qml"), "utf8").replaceAll("../../src/", "source/")
    );
    for (const name of ["WorkerControl.qml", "Echo.js"])
        fs.copyFileSync(path.join(__dirname, "Runtime", name), path.join(nativeRoot, name));
    // Exercise real shared widgets separately; keep deterministic host-service doubles around them.
    const duxRoot = path.join(directory, "dux");
    fs.mkdirSync(duxRoot);
    const hostRoot = process.env.DMS_SOURCE_ROOT || "/usr/share/quickshell/dms";
    fs.symlinkSync(path.join(hostRoot, "DCommon"), path.join(duxRoot, "DCommon"), "dir");
    for (const name of ["Common", "Modules", "Services"])
        fs.symlinkSync(path.resolve(__dirname, "HostModules/qs", name), path.join(duxRoot, name), "dir");
    fs.symlinkSync(path.resolve(__dirname, "../src"), path.join(duxRoot, "source"), "dir");
    fs.writeFileSync(
        path.join(duxRoot, "DuxControls.qml"),
        fs.readFileSync(path.join(__dirname, "Runtime/DuxControls.qml"), "utf8").replaceAll("../../src/", "source/")
    );
    const commands = {
        "secret-tool":
            '#!/bin/sh\nif [ "$GITHUB_INBOX_TEST_SECRET_FAIL" = "$1" ]; then printf "%s\\n" "Test Secret Service failure" >&2; exit 7; fi\ncase "$1" in\nlookup) test -f "$XDG_CACHE_HOME/test-secret" || exit 1; cat "$XDG_CACHE_HOME/test-secret";;\nstore) cat > "$XDG_CACHE_HOME/test-secret";;\nclear) rm -f "$XDG_CACHE_HOME/test-secret";;\n*) exit 2;;\nesac\n',
        curl: '#!/bin/sh\nprintf "%s\\n" curl >> "$GITHUB_INBOX_BLOCKED_REQUESTS"\nexit 99\n',
        dms: '#!/bin/sh\ncase "$1" in\nnotify) exit 0;;\ndl) if [ "$GITHUB_INBOX_TEST_DMS_DOWNLOAD" = retry ]; then if [ ! -f "$XDG_CACHE_HOME/test-download-attempt" ]; then printf first > "$XDG_CACHE_HOME/test-download-attempt"; exit 1; fi; exit 0; fi;;\nesac\nprintf "%s\\n" "dms $1" >> "$GITHUB_INBOX_BLOCKED_REQUESTS"\nexit 99\n'
    };
    for (const [name, script] of Object.entries(commands))
        fs.writeFileSync(path.join(directory, "bin", name), script, { mode: 0o700 });
    const blockedRequestsPath = path.join(directory, "blocked-requests");
    return {
        directory,
        nativeConfigPath: path.join(nativeRoot, "RuntimeChecks.qml"),
        nativeControlPath: path.join(nativeRoot, "WorkerControl.qml"),
        nativeDuxPath: path.join(duxRoot, "DuxControls.qml"),
        environment: {
            ...process.env,
            PATH: path.join(directory, "bin") + path.delimiter + (process.env.PATH || ""),
            XDG_CACHE_HOME: path.join(directory, "cache"),
            XDG_CONFIG_HOME: path.join(directory, "config"),
            XDG_DATA_HOME: path.join(directory, "data"),
            TMPDIR: path.join(directory, "tmp"),
            GITHUB_INBOX_BLOCKED_REQUESTS: blockedRequestsPath,
            QT_QPA_PLATFORM: "offscreen",
            QT_QPA_PLATFORMTHEME: "generic",
            QT_FATAL_WARNINGS: "0"
        },
        // Unexpected process-level network requests are reported as test failures after Qt exits.
        blockedRequests() {
            return fs.existsSync(blockedRequestsPath) ? fs.readFileSync(blockedRequestsPath, "utf8").trim() : "";
        },
        // Always remove generated data, including after a failed Qt launch.
        dispose() {
            fs.rmSync(directory, { recursive: true, force: true });
        }
    };
}

module.exports = { createTestEnvironment };
