// RunAll.js - runs dependency-free JavaScript and headless QML tests.

"use strict";

const childProcess = require("node:child_process");
const path = require("node:path");
const { unexpectedWarnings, nativeWarnings } = require("../audit/QmlWarnings");
const { createTestEnvironment } = require("./TestEnvironment");

const repositoryRoot = path.resolve(__dirname, "..");
const javascriptTests = [
    "tests/CommentAudit.test.js",
    "tests/HostContracts.test.js",
    "tests/SetupSymlink.test.js",
    "tests/TestEnvironment.test.js",
    "tests/RunnerWarnings.test.js",
    "tests/JS/Contracts/ProviderContracts.test.js",
    "tests/JS/Contracts/PluginError.test.js",
    "tests/JS/Integrations/GitHub/GitHubHelpers.test.js",
    "tests/JS/Integrations/GitHub/AuthorTools.test.js",
    "tests/JS/Helpers/CacheCommands.test.js",
    "tests/JS/Helpers/InboxOperationRules.test.js",
    "tests/JS/Helpers/CalendarTime.test.js",
    "tests/JS/Storage/CacheSerialization.test.js",
    "tests/JS/Integrations/GitHub/InboxParserBackgroundWorker.test.js",
    "tests/JS/BackgroundWorkers/CacheBackgroundWorker.test.js"
];

for (const testPath of javascriptTests) {
    const result = childProcess.spawnSync(process.execPath, [testPath], {
        cwd: repositoryRoot,
        stdio: "inherit"
    });
    if (result.status !== 0) process.exit(result.status || 1);
}

if (process.argv.includes("--live")) {
    const liveTest = childProcess.spawnSync(
        process.execPath,
        ["tests/JS/Integrations/GitHub/Notifications.live.test.js"],
        {
            cwd: repositoryRoot,
            stdio: "inherit"
        }
    );
    if (liveTest.status !== 0) process.exit(liveTest.status || 1);
}

function findQt6QmlTestRunner() {
    const candidates = [
        process.env.QML_TEST_RUNNER,
        "qmltestrunner6",
        "/usr/lib/qt6/bin/qmltestrunner",
        "/usr/lib64/qt6/bin/qmltestrunner",
        "qmltestrunner"
    ].filter(Boolean);

    for (const candidate of candidates) {
        const result = childProcess.spawnSync("sh", [
            "-c",
            'command -v -- "$1" || test -x "$1"',
            "runner-check",
            candidate
        ]);
        if (result.status !== 0) continue;

        const runnerPath = candidate.includes("/")
            ? candidate
            : childProcess
                  .spawnSync("sh", ["-c", 'command -v -- "$1"', "runner-path", candidate], { encoding: "utf8" })
                  .stdout.trim();
        const dependencies = childProcess.spawnSync("ldd", [runnerPath], { encoding: "utf8" });
        if (dependencies.status === 0 && /libQt6(?:Core|QuickTest)\.so/.test(dependencies.stdout)) return runnerPath;
    }
    return "";
}

const qmlTestRunner = findQt6QmlTestRunner();
if (!qmlTestRunner) {
    console.error(
        "Qt 6 qmltestrunner was not found. Install the Qt 6 QuickTest runner, or set QML_TEST_RUNNER to its executable path."
    );
    process.exit(1);
}

const testEnvironment = createTestEnvironment();
let qmlTest;
let blockedRequests;
let runtimeTest;
let runtimeControl;
let duxControls;
try {
    qmlTest = childProcess.spawnSync(
        qmlTestRunner,
        ["-input", "tests/QML", "-import", "src/QML", "-import", "tests/HostModules"],
        {
            cwd: repositoryRoot,
            env: testEnvironment.environment,
            encoding: "utf8",
            maxBuffer: 16 * 1024 * 1024
        }
    );
    blockedRequests = testEnvironment.blockedRequests();
    if (qmlTest.status === 0) {
        runtimeControl = childProcess.spawnSync("qs", ["-p", testEnvironment.nativeControlPath], {
            cwd: repositoryRoot,
            env: { ...testEnvironment.environment, WAYLAND_DISPLAY: undefined, DISPLAY: undefined },
            encoding: "utf8",
            timeout: 10000,
            maxBuffer: 16 * 1024 * 1024
        });
        runtimeTest = childProcess.spawnSync("qs", ["-p", testEnvironment.nativeConfigPath], {
            cwd: repositoryRoot,
            env: {
                ...testEnvironment.environment,
                GITHUB_INBOX_TEST_MUTATIONS: "1",
                WAYLAND_DISPLAY: undefined,
                DISPLAY: undefined,
                QML_IMPORT_PATH: path.join(testEnvironment.directory, "modules")
            },
            encoding: "utf8",
            timeout: 20000,
            maxBuffer: 16 * 1024 * 1024
        });
        duxControls = childProcess.spawnSync("qs", ["-p", testEnvironment.nativeDuxPath], {
            cwd: repositoryRoot,
            env: { ...testEnvironment.environment, WAYLAND_DISPLAY: undefined, DISPLAY: undefined },
            encoding: "utf8",
            timeout: 15000,
            maxBuffer: 16 * 1024 * 1024
        });
        blockedRequests = testEnvironment.blockedRequests();
    }
} finally {
    testEnvironment.dispose();
}

if (blockedRequests) {
    console.error("QML tests attempted an external network command; the request was blocked.");
    process.exit(1);
}

if (qmlTest.error) throw qmlTest.error;
if (duxControls) {
    const output = (duxControls.stdout || "") + (duxControls.stderr || "");
    process.stdout.write(output);
    if (duxControls.status !== 0 || !output.includes("DUX_CONTROLS_PASSED") || nativeWarnings(output).length) {
        console.error("Installed Dux control checks failed.");
        process.exit(1);
    }
}
if (runtimeTest) {
    process.stdout.write(runtimeTest.stdout || "");
    process.stderr.write(runtimeTest.stderr || "");
    if (
        runtimeTest.status !== 0 ||
        !((runtimeTest.stdout || "") + (runtimeTest.stderr || "")).includes("RUNTIME_CHECKS_PASSED")
    ) {
        console.error("Native Quickshell integration checks failed.");
        console.error(
            JSON.stringify({
                status: runtimeTest.status,
                signal: runtimeTest.signal,
                error: runtimeTest.error && runtimeTest.error.message
            })
        );
        process.exit(1);
    }
    const controlOutput = (runtimeControl.stdout || "") + (runtimeControl.stderr || "");
    if (runtimeControl.status !== 0 || !controlOutput.includes("WORKER_CONTROL_PASSED")) {
        console.error("Native worker control fixture did not complete.");
        process.exit(1);
    }
    const knownQtWarning = "qt.core.qobject.connect: QObject::connect(QJSEngine, QtObject): invalid nullptr parameter";
    const reproduced = nativeWarnings(controlOutput).includes(knownQtWarning);
    const runtimeWarnings = nativeWarnings((runtimeTest.stdout || "") + (runtimeTest.stderr || ""));
    if (runtimeWarnings.some((warning) => warning !== knownQtWarning || !reproduced)) {
        console.error("Native integration tests produced unexpected runtime warnings.");
        process.exit(1);
    }
}
process.stdout.write(qmlTest.stdout || "");
process.stderr.write(qmlTest.stderr || "");
const warnings = unexpectedWarnings((qmlTest.stdout || "") + "\n" + (qmlTest.stderr || ""));
if (warnings.length) {
    console.error(`QML tests produced ${warnings.length} unexpected runtime warnings.`);
    process.exit(1);
}
if (qmlTest.status === null) {
    console.error(
        "QML test runner did not start or exited without a status code." +
            (qmlTest.signal ? " Signal: " + qmlTest.signal + "." : "")
    );
    process.exit(1);
}
process.exit(qmlTest.status);
