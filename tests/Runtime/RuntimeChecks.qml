// RuntimeChecks.qml - verifies native Quickshell processes and parser workers with isolated external commands.

import QtQuick
import Quickshell
import "../../src/JS/Integrations/GitHub/GitHubHelpers.js" as Helpers
import "../../src/QML/Services"

ShellRoot {
    id: testRoot

    property string payload: JSON.stringify([
        {
            id: "42",
            unread: true,
            updated_at: "2026-10-24T10:00:00Z",
            subject: {
                type: "PullRequest",
                title: "Example",
                url: "https://api.github.com/repos/owner/repo/pulls/42"
            },
            repository: {
                full_name: "owner/repo"
            }
        }
    ])
    property string phase: "store"

    function checkCache(message) {
        if (phase === "cache") {
            if (!require(message.action === "cacheParsed" && message.data.doneThreadState["42"].source === "local", "Legacy Done state was not migrated"))
                return;
            phase = "cacheFailure";
            cacheWorker.sendMessage({
                action: "parseCache",
                seq: 2,
                expectedVersion: 1,
                text: "{"
            });
        } else if (phase === "cacheFailure") {
            if (!require(message.failure && message.failure.name === "PluginError" && message.failure.userMessage !== message.failure.details, "Missing typed cache error"))
                return;
            console.info("RUNTIME_CHECKS_PASSED");
            successExit.start();
        }
    }
    function checkInbox(message) {
        if (phase === "inbox" && message.phase === "chunk") {
            if (!require(JSON.stringify(message.items) === JSON.stringify(Helpers.parseMessagesPayload(payload).items), "Worker and main parser differ"))
                return;
            phase = "inboxFailure";
            inboxWorker.sendMessage({
                seq: 2,
                payloadText: "[]",
                allSegmentCount: 1
            });
        } else if (phase === "inboxFailure") {
            if (!require(message.failure && message.failure.name === "PluginError" && message.failure.retryable, "Missing typed inbox error"))
                return;
            phase = "cache";
            cacheWorker.source = Qt.resolvedUrl("../../src/JS/BackgroundWorkers/CacheBackgroundWorker.js");
            cacheWorker.sendMessage({
                action: "parseCache",
                seq: 1,
                expectedVersion: 1,
                text: JSON.stringify({
                    version: 1,
                    lastFetched: 10,
                    notifications: [],
                    authorsByThread: {},
                    authorFetchedAt: {},
                    avatarMap: {},
                    doneThreadState: ["42"]
                })
            });
        }
    }

    // Exit normally on assertion failures, so a test failure never becomes a desktop crash report.
    function require(condition, message) {
        if (condition)
            return true;
        console.error("RUNTIME_CHECK_FAILED: " + message);
        Qt.exit(1);
        return false;
    }

    Component.onCompleted: secret.storeToken("ghp_test_only")

    SecretStore {
        id: secret

        autoLoad: false

        onTokenCleared: function (success, message) {
            if (testRoot.phase === "clearFailure") {
                if (!testRoot.require(!success && secret.token === "ghp_test_only", "Failed removal changed confirmed token state"))
                    return;
                testRoot.phase = "clear";
                secret.secretToolCommand = ["secret-tool"];
                secret.clearToken();
            } else if (testRoot.phase === "clear") {
                if (!testRoot.require(success && secret.token === "", message))
                    return;
                testRoot.phase = "inbox";
                inboxWorker.source = Qt.resolvedUrl("../../src/JS/Integrations/GitHub/InboxParserBackgroundWorker.js");
                inboxWorker.sendMessage({
                    seq: 1,
                    payloadText: testRoot.payload + "\nSPLIT\n[]\nSPLIT\n",
                    separator: "SPLIT",
                    allSegmentCount: 1
                });
            }
        }
        onTokenLoaded: function (token) {
            if (!testRoot.require(token === "ghp_test_only", "Secret Service round trip lost stdin data"))
                return;
            testRoot.phase = "clearFailure";
            secret.secretToolCommand = ["env", "GITHUB_INBOX_TEST_SECRET_FAIL=clear", "secret-tool"];
            secret.clearToken();
        }
        onTokenStored: function (success, message) {
            if (!testRoot.require(success, message))
                return;
            testRoot.phase = "lookup";
            secret.loadToken();
        }
    }
    WorkerScript {
        id: inboxWorker

        onMessage: function (message) {
            testRoot.checkInbox(message);
        }
    }
    WorkerScript {
        id: cacheWorker

        onMessage: function (message) {
            testRoot.checkCache(message);
        }
    }
    Timer {
        id: successExit

        interval: 50

        onTriggered: Qt.exit(0)
    }
    Timer {
        interval: 10000
        running: true

        onTriggered: testRoot.require(false, "Native integration test timed out during " + testRoot.phase)
    }
}
