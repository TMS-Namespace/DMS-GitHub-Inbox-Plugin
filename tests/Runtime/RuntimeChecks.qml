// RuntimeChecks.qml - verifies native Quickshell processes and parser workers with isolated external commands.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../src/JS/Integrations/GitHub/GitHubHelpers.js" as Helpers
import "../../src/QML/BackgroundWorkers"
import "../../src/QML/Services"

ShellRoot {
    id: testRoot

    property var authorSnapshot: ({})
    property bool avatarRedownloadRequested: false
    property int cacheSaveChecks: 0
    property bool damagedCacheReported: false
    property int mutationErrors: 0
    property var mutationEvents: []
    property var mutationMessages: []
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
    property string workflowReference: ""
    property string workflowUrl: ""

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
            phase = "cacheRestore";
            restoredCache.initialize();
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
    // Run automatic and explicit author fetches through curl, WorkerScript and the merge service.
    function startAuthorChecks() {
        phase = "authorAutomatic";
        authorParser.source = Qt.resolvedUrl("../../src/JS/Integrations/GitHub/InboxParserBackgroundWorker.js");
        authors.prefetchForMessages([
            {
                threadId: "42",
                subjectApiUrl: "https://api.github.com/repos/owner/repo/pulls/42",
                updatedAt: "2026-10-24T10:00:00Z",
                title: "PR",
                subjectType: "PullRequest",
                reason: "comment"
            }
        ]);
    }

    // Verify serialized Done and read requests against the isolated curl process.
    function startMutationChecks() {
        phase = "mutations";
        mutationMessages = [
            {
                threadId: "101",
                unread: true,
                updatedAtMs: 30
            },
            {
                threadId: "102",
                unread: true,
                updatedAtMs: 20
            },
            {
                threadId: "103",
                unread: true,
                updatedAtMs: 10
            }
        ];
        mutations.markThreadsDone(mutationMessages.slice(0, 2));
        mutations.markThreadReadAfterOpen("103");
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
    PluginCache {
        id: restoredCache

        cacheDir: Quickshell.env("XDG_CACHE_HOME") + "/integration-restore"
        pollIntervalMs: 120000
        providerApi: ({
                buildAvatarUrl: function (login) {
                    return "https://avatars.githubusercontent.com/" + login;
                }
            })

        onAvatarDownloadsRequested: items => {
            if (testRoot.phase === "cacheRestore")
                testRoot.avatarRedownloadRequested = items.length === 1 && items[0].login === "bad";
        }
        onCacheFailure: message => testRoot.require(false, "Restored cache failed: " + message)
        onCacheReady: {
            if (!testRoot.require(testRoot.phase === "cacheRestore" && testRoot.avatarRedownloadRequested, "Invalid avatar did not request a replacement"))
                return;
            if (!testRoot.require(restoredCache.cachedMessages.length === 1 && restoredCache.cachedTimestamp === 1700000 && restoredCache.cachedPollIntervalMs === 120000, "Cached messages or refresh settings were not restored"))
                return;
            let localUrl = "file://" + restoredCache.cacheDir + "/avatars/good.png";
            if (!testRoot.require(restoredCache.avatarLocalPaths.good === localUrl && !restoredCache.avatarLocalPaths.bad && restoredCache.cachedMessages[0].repositoryOwnerAvatarUrl === localUrl && restoredCache.cachedAuthorsByThread["42"][0].avatarUrl === localUrl, "Validated avatar paths were not restored"))
                return;
            testRoot.phase = "cacheSave";
            restoredCache.updateMessages([
                {
                    threadId: "42",
                    unread: false
                }
            ], 1700001);
            restoredCache.updateAuthorFetchedAt("42", "author-marker");
            restoredCache._writeToDisk();
            cacheSaveCheckTimer.start();
        }
    }
    PluginCache {
        id: damagedCache

        cacheDir: Quickshell.env("XDG_CACHE_HOME") + "/integration-damaged"

        onCacheFailure: message => testRoot.damagedCacheReported = message.indexOf("preserved") >= 0
        onCacheReady: {
            if (!testRoot.require(testRoot.phase === "cacheDamaged" && testRoot.damagedCacheReported && !damagedCache._preserveDamagedCache, "Damaged cache recovery was not reported after a successful backup"))
                return;
            damagedCacheCheck.running = true;
        }
    }
    Process {
        id: cacheSaveCheck

        command: ["sh", "-c", "jq -e '.lastFetched == 1700001 and .notifications[0].unread == false and .authorFetchedAt[\"42\"] == \"author-marker\" and .avatarMap.good.localFile == \"good.png\" and (.avatarMap.bad == null)' \"$XDG_CACHE_HOME/integration-restore/objects/cache.json\" >/dev/null && test -f \"$XDG_CACHE_HOME/integration-restore/avatars/good.png\" && test ! -e \"$XDG_CACHE_HOME/integration-restore/avatars/bad.png\""]

        onExited: exitCode => {
            if (exitCode === 0) {
                testRoot.phase = "cacheDamaged";
                damagedCache.initialize();
            } else if (++testRoot.cacheSaveChecks < 30)
                cacheSaveCheckTimer.restart();
            else
                testRoot.require(false, "Cache snapshot or avatar validation was not persisted");
        }
    }
    Timer {
        id: cacheSaveCheckTimer

        interval: 100

        onTriggered: cacheSaveCheck.running = true
    }
    Process {
        id: damagedCacheCheck

        command: ["sh", "-c", "backup=$(find \"$XDG_CACHE_HOME/integration-damaged/objects\" -name 'cache.json.damaged-*' -type f -print -quit); test -n \"$backup\" && cmp -s \"$backup\" \"$XDG_CACHE_HOME/integration-damaged/objects/cache.json\""]

        onExited: exitCode => {
            if (!testRoot.require(exitCode === 0, "Damaged cache backup was missing or changed"))
                return;
            testRoot.phase = "cacheFirstRun";
            freshCache.initialize();
        }
    }
    PluginCache {
        id: freshCache

        cacheDir: Quickshell.env("XDG_CACHE_HOME") + "/integration-first-run"

        onCacheFailure: message => testRoot.require(false, "Fresh cache failed: " + message)
        onCacheReady: {
            if (!testRoot.require(testRoot.phase === "cacheFirstRun" && freshCache.initialized && freshCache.cachedMessages.length === 0 && freshCache.cachedTimestamp === 0, "First-run cache initialization failed"))
                return;
            testRoot.phase = "download";
            avatarDownload.startAttempt();
        }
    }
    AvatarDownloadWorker {
        id: avatarDownload

        autoStart: false
        downloadCommand: ["env", "GITHUB_INBOX_TEST_DMS_DOWNLOAD=retry", "dms", "dl", "https://example.invalid/avatar.png"]
        maximumRetries: 2
        retryDelayMs: 10
        retryWindowMs: 1000

        onFinished: success => {
            if (!testRoot.require(success && attempts === 2, "Native Dux download did not retry then complete"))
                return;
            testRoot.startMutationChecks();
        }
    }
    InboxOperations {
        id: mutations

        providerApi: ({
                buildCurlRetryArguments: function () {
                    return [];
                },
                buildThreadActionRequest: function (action, threadId) {
                    return {
                        method: action === "done" ? "DELETE" : "PATCH",
                        url: "https://api.github.com/notifications/threads/" + threadId,
                        payloadJson: ""
                    };
                }
            })
        token: "ghp_test_only"

        onOperationApplied: (actionType, threadId, repositoryFullName, threadIds) => {
            if (testRoot.phase === "cancelMutation") {
                testRoot.require(false, "A cancelled mutation published a stale result");
                return;
            }
            if (testRoot.phase !== "mutations")
                return;
            testRoot.mutationEvents.push(actionType + ":" + threadId);
            let result = mutations.applyResult(actionType, threadId, repositoryFullName, testRoot.mutationMessages, threadIds);
            testRoot.mutationMessages = result.items;
            if (actionType === "thread_done_sync" && threadId === "102") {
                if (!testRoot.require(testRoot.mutationEvents.join(",") === "threads_done:,thread_read_pending:103,thread_done_sync:101,thread_read_revert:103,thread_done_sync:102", "Mutation queue order or rollback changed"))
                    return;
                if (!testRoot.require(testRoot.mutationErrors === 1 && testRoot.mutationMessages.length === 1 && testRoot.mutationMessages[0].threadId === "103" && testRoot.mutationMessages[0].unread, "Failed read did not restore the unread message"))
                    return;
                if (!testRoot.require(mutations.doneThreadState["101"] && mutations.doneThreadState["102"], "Successful Done requests were not committed"))
                    return;
                testRoot.phase = "cancelMutation";
                mutations.markThreadAsRead("101");
                mutations.resetState(false);
                cancelledMutationWait.start();
            }
        }
        onOperationError: message => {
            if (testRoot.phase === "mutations" && message.indexOf("403") >= 0)
                testRoot.mutationErrors++;
            else
                testRoot.require(false, "Unexpected mutation error: " + message);
        }
    }
    AuthorBackgroundWorker {
        id: authors

        authorsByThreadRef: testRoot.authorSnapshot
        token: "ghp_test_only"
        workerSendMessage: function (message) {
            authorParser.sendMessage(message);
        }

        onAuthorFetchedAtChanged: (threadId, updatedAt) => {
            if (testRoot.phase === "authorAutomatic" && threadId === "42") {
                testRoot.phase = "authorExplicit";
                authors.enqueueAuthorUrls("42", ["https://api.github.com/repos/owner/repo/issues/42/comments"], "2026-10-24T10:00:00Z", false, null, "PR", "PullRequest", "comment");
            } else if (testRoot.phase === "authorExplicit" && threadId === "42") {
                testRoot.phase = "authorAwaitMerge";
            } else if (testRoot.phase === "authorCi" && threadId === "ci") {
                testRoot.phase = "authorCiAwaitMerge";
            } else if (testRoot.phase === "cancelAuthor") {
                testRoot.require(false, "A cancelled author request published a stale result");
            }
        }
        onAuthorsMerged: (authorsByThread, preloadAuthors, changedThreadIds) => {
            testRoot.authorSnapshot = authorsByThread;
            if (testRoot.phase === "authorAwaitMerge") {
                let participants = authorsByThread["42"] || [];
                if (!testRoot.require(participants.length === 2 && participants[0].login === "author" && participants[1].login === "commenter", "PR author and commenter were not merged"))
                    return;
                testRoot.phase = "authorCi";
                authors.enqueueAuthorUrls("ci", ["https://api.github.com/repos/owner/repo/actions/runs"], "2026-10-24T10:00:00Z", true, null, "Build workflow run succeeded for main branch", "CheckSuite", "ci_activity");
            } else if (testRoot.phase === "authorCiAwaitMerge") {
                let participants = authorsByThread.ci || [];
                if (!testRoot.require(participants.length === 1 && participants[0].login === "trigger" && testRoot.workflowReference === "3116" && testRoot.workflowUrl === "https://github.com/owner/repo/actions/runs/123", "CI triggering actor or workflow reference was incorrect"))
                    return;
                testRoot.phase = "cancelAuthor";
                authors.enqueueAuthorUrls("stale", ["https://api.github.com/repos/owner/repo/pulls/99"], "2026-10-24T10:00:00Z", false, null, "PR", "PullRequest", "comment");
                authors.resetState();
                cancelledAuthorWait.start();
            } else if (testRoot.phase === "cancelAuthor") {
                testRoot.require(false, "A cancelled author merge was published");
            }
        }
        onSubjectWebUrlResolved: (threadId, webUrl, subjectReference) => {
            if (threadId === "ci") {
                testRoot.workflowUrl = webUrl;
                testRoot.workflowReference = subjectReference;
            }
        }
    }
    WorkerScript {
        id: authorParser

        onMessage: message => authors.handleAuthorResult(message)
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
        id: cancelledMutationWait

        interval: 150

        onTriggered: {
            if (!testRoot.require(!mutations.isBusy && mutations.doneThreadState["101"], "Reset lost confirmed state or retained pending work"))
                return;
            testRoot.startAuthorChecks();
        }
    }
    Timer {
        id: cancelledAuthorWait

        interval: 400

        onTriggered: {
            if (!testRoot.require(!authors.isBusy && !testRoot.authorSnapshot.stale, "Cancelled author request remained active"))
                return;
            console.info("RUNTIME_CHECKS_PASSED");
            successExit.start();
        }
    }
    Timer {
        id: successExit

        interval: 50

        onTriggered: Qt.exit(0)
    }
    Timer {
        interval: 15000
        running: true

        onTriggered: testRoot.require(false, "Native integration test timed out during " + testRoot.phase)
    }
}
