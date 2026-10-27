// tst_author_merge_service.qml - exercises author batching, deduplication and reset.

import QtQuick
import QtTest
import "../../../src/QML/Services"
import "../../../src/QML" as Plugin

TestCase {
    function init() {
        service.reset();
        service.authorsByThread = ({});
        merged.clear();
    }
    function test_largeBatchRetainsRemainingThreads() {
        let total = Plugin.GitHubConstants.authorMergeFlushBatchSize + 1;
        for (let index = 0; index < total; index++)
            service.stage("thread-" + index, [
                {
                    login: "user-" + index,
                    type: "User"
                }
            ], false);
        service.schedule();
        service.flush();
        compare(merged.count, 1);
        compare(merged.signalArguments[0][2].length, total - 1);
        verify(service.isBusy);
        service.flush();
        compare(merged.count, 2);
        compare(merged.signalArguments[1][2].length, 1);
        compare(Object.keys(service.authorsByThread).length, total);
    }
    function test_manualFetchMergesAndAutomaticFetchReplaces() {
        service.authorsByThread = ({
                "42": [
                    {
                        login: "Alice",
                        type: "User"
                    }
                ]
            });
        service.stage("42", [
            {
                login: "Bob",
                type: "User"
            }
        ], false);
        service.stage("42", [
            {
                login: "alice",
                type: "User"
            }
        ], false);
        let snapshot = service.cloneAuthorsByThread(service.authorsByThread);
        compare(snapshot["42"].length, 2);
        compare(snapshot["42"][0].login, "Alice");
        compare(snapshot["42"][1].login, "Bob");
        service.stage("42", [
            {
                login: "Carol",
                type: "User"
            }
        ], true);
        service.schedule();
        verify(service.isBusy);
        service.flush();
        compare(merged.count, 1);
        compare(service.authorsByThread["42"].length, 1);
        compare(service.authorsByThread["42"][0].login, "Carol");
    }
    function test_resetDropsPendingMerges() {
        service.stage("42", [
            {
                login: "Alice",
                type: "User"
            }
        ], false);
        service.schedule();
        service.reset();
        verify(!service.isBusy);
        compare(Object.keys(service.cloneAuthorsByThread({})).length, 0);
        service.flush();
        compare(merged.count, 0);
    }

    name: "AuthorMergeService"

    AuthorMergeService {
        id: service

        onMerged: (authors, avatars, changedIds) => service.authorsByThread = authors
    }
    SignalSpy {
        id: merged

        signalName: "merged"
        target: service
    }
}
