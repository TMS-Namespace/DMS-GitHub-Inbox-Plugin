// tst_inbox_operations.qml - covers optimistic inbox operations and state reconciliation.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    function init() {
        operations.resetState(true);
        operations.doneThreadState = ({});
        operations.pendingDoneThreadState = ({});
        operations.pendingReadMessagesByThread = ({});
        operations.pendingDoneMessagesByThread = ({});
    }
    function test_bulkReadAndRepositoryDoneOnlyTouchSelectedThreads() {
        let messages = [
            {
                threadId: "a",
                repository: "owner/one",
                unread: true
            },
            {
                threadId: "b",
                repository: "owner/one",
                unread: true
            },
            {
                threadId: "c",
                repository: "owner/two",
                unread: true
            }
        ];
        let readResult = operations.applyResult("threads_read", "", "", messages, ["b"]);
        compare(readResult.items[0].unread, true);
        compare(readResult.items[1].unread, false);
        compare(readResult.items[2].unread, true);

        let doneResult = operations.applyResult("repo_done", "", "owner/one", messages, ["a"]);
        compare(doneResult.items.length, 2);
        compare(doneResult.items[0].threadId, "b");
        compare(doneResult.items[1].threadId, "c");
    }
    function test_doneMutationCanRollbackOrCommit() {
        let messages = [
            {
                threadId: "thread-a",
                unread: true,
                updatedAtMs: 20
            },
            {
                threadId: "thread-b",
                unread: true,
                updatedAtMs: 10
            }
        ];
        let hidden = operations.applyResult("thread_done", "thread-a", "", messages, []);
        compare(hidden.items.length, 1);
        compare(hidden.items[0].threadId, "thread-b");
        compare(operations.pendingDoneMessagesByThread["thread-a"].unread, true);

        let rolledBack = operations.applyResult("thread_done_revert", "thread-a", "", hidden.items, []);
        compare(rolledBack.items.length, 2);
        compare(rolledBack.items[0].threadId, "thread-a");
        verify(rolledBack.unreadChanged);

        hidden = operations.applyResult("thread_done", "thread-a", "", messages, []);
        operations.applyResult("thread_done_sync", "thread-a", "", hidden.items, []);
        compare(operations.doneThreadState["thread-a"].source, "local");
        compare(operations.pendingDoneMessagesByThread["thread-a"], undefined);
    }
    function test_inferredDoneAndOldEntriesAreReconciled() {
        operations.setDoneThreadState({
            inferred: {
                source: "github_missing_from_complete_refresh",
                updatedAt: "",
                savedAt: Date.now()
            },
            old: {
                source: "local",
                updatedAt: "",
                savedAt: Date.now() - 10000
            },
            recent: {
                source: "local",
                updatedAt: "",
                savedAt: Date.now()
            }
        });
        operations.clearReturnedDoneThreadState([
            {
                threadId: "inferred",
                updatedAtMs: Date.now()
            }
        ]);
        compare(operations.doneThreadState.inferred, undefined);

        operations.pruneDoneThreadState(5000);
        compare(operations.doneThreadState.old, undefined);
        verify(operations.doneThreadState.recent);
    }
    function test_localDoneClearsOnlyAfterNewerActivity() {
        operations.markMessagesLocallyDone([
            {
                threadId: "thread-a",
                updatedAt: "2026-06-01T12:00:00Z"
            }
        ], "local");
        let sameActivity = Date.parse("2026-06-01T12:00:00Z");
        operations.clearReturnedDoneThreadState([
            {
                threadId: "thread-a",
                updatedAtMs: sameActivity
            }
        ]);
        verify(operations.doneThreadState["thread-a"]);

        operations.clearReturnedDoneThreadState([
            {
                threadId: "thread-a",
                updatedAtMs: sameActivity + 1
            }
        ]);
        compare(operations.doneThreadState["thread-a"], undefined);
    }
    function test_mutationCommandReadsAuthorizationHeaderFromStdin() {
        operations.providerApi = {
            buildCurlRetryArguments: function () {
                return ["--retry", "2", "--retry-connrefused", "--retry-max-time", "45"];
            }
        };
        let command = operations.buildMutationCommand("PATCH", "https://api.github.com/notifications/threads/42", "{\"read\":false}");

        verify(command[2].indexOf("-H @-") >= 0);
        verify(command.indexOf("Authorization: token") < 0);
        verify(command.indexOf("--retry") >= 0);
        verify(command.indexOf("--retry-max-time") >= 0);
        compare(command[command.length - 1], "https://api.github.com/notifications/threads/42");
        verify(command.indexOf("{\"read\":false}") >= 0);
    }
    function test_pendingReadStateIsAppliedToARefreshedMessage() {
        operations.pendingReadMessagesByThread = ({
                "thread-a": true
            });
        let source = [
            {
                threadId: "thread-a",
                unread: true
            },
            {
                threadId: "thread-b",
                unread: true
            }
        ];
        let result = operations.applyPendingReadState(source);
        compare(result[0].unread, false);
        compare(result[1].unread, true);
        compare(source[0].unread, true);
    }
    function test_readMutationRollsBackAndKeepsOtherMessages() {
        let messages = [
            {
                threadId: "thread-a",
                unread: true
            },
            {
                threadId: "thread-b",
                unread: true
            }
        ];
        let optimistic = operations.applyResult("thread_read_pending", "thread-a", "", messages, []);
        compare(optimistic.items[0].unread, false);
        compare(optimistic.items[1].unread, true);
        compare(operations.pendingReadMessagesByThread["thread-a"].unread, true);

        let rolledBack = operations.applyResult("thread_read_revert", "thread-a", "", optimistic.items, []);
        compare(rolledBack.items[0].unread, true);
        compare(rolledBack.items[1].unread, true);
        compare(operations.pendingReadMessagesByThread["thread-a"], undefined);
    }
    function test_unchangedDoneReconciliationDoesNotPublishUpdates() {
        operations.setDoneThreadState({
            "thread-a": {
                source: "local",
                updatedAt: "2026-06-01T12:00:00Z",
                savedAt: 1
            }
        });
        doneStateChanges.clear();
        operations.clearReturnedDoneThreadState([
            {
                threadId: "thread-a",
                updatedAt: "2026-06-01T12:00:00Z"
            }
        ]);
        operations.pruneDoneThreadState(100000000000);
        compare(doneStateChanges.count, 0);
        verify(operations.doneThreadState["thread-a"]);
    }

    name: "InboxOperations"

    InboxOperations {
        id: operations
    }
    SignalSpy {
        id: doneStateChanges

        signalName: "doneThreadStateChanged"
        target: operations
    }
}
