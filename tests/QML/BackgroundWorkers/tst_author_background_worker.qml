// tst_author_background_worker.qml - verifies author request completion and stale-result handling.

import QtQuick
import QtTest
import "../../../src/QML/BackgroundWorkers"

TestCase {
    id: testCase

    property var parserMessage: null
    readonly property string subjectUrl: "https://api.github.com/repos/owner/repo/pulls/42"

    function cleanup() {
        worker.clearAllState();
    }
    function init() {
        worker.clearAllState();
        worker.loadAuthorInfo = true;
        worker.token = "test-only";
        parserMessage = null;
        completed.clear();
    }
    function request() {
        return {
            threadId: "42",
            urls: [subjectUrl],
            updatedAt: "2026-10-24T10:00:00Z",
            subjectType: "PullRequest",
            reason: "comment",
            automaticPrefetch: false
        };
    }
    function test_failedRequestReleasesSlotWithoutMarkingUrlsFetched() {
        worker.requestsInFlight = 1;
        worker.markThreadUrlsActive("42", [subjectUrl]);
        worker.handleRequestFinished(request(), worker.requestGeneration, 1, "", 0, Date.now());
        compare(worker.requestsInFlight, 0);
        compare(worker.activeUrlsByThread["42"], undefined);
        compare(worker.fetchedUrlsByThread["42"], undefined);
        compare(parserMessage, null);
        compare(completed.count, 1);
    }
    function test_obsoleteRequestAndParserResultsAreIgnored() {
        let generation = worker.requestGeneration;
        worker.requestsInFlight = 1;
        worker.resetState();
        worker.handleRequestFinished(request(), generation, 0, "stale", 5, Date.now());
        worker.handleAuthorResult({
            generation: generation,
            threadId: "42",
            authors: [
                {
                    login: "stale",
                    type: "User"
                }
            ]
        });
        compare(worker.requestsInFlight, 0);
        compare(parserMessage, null);
        compare(Object.keys(worker.cloneAuthorsByThread({})).length, 0);
        verify(!worker.isBusy);
    }
    function test_subjectPolicyFiltersAutomationAndLimitsVisibleParticipants() {
        let participants = [
            {
                login: "author"
            },
            {
                login: "github-actions[bot]"
            },
            {
                login: "commenter"
            },
            {
                login: "reviewer"
            },
            {
                login: "another"
            }
        ];
        let pullRequest = worker.normalizeAuthorsForSubject("PullRequest", "comment", participants);
        compare(pullRequest.length, 3);
        compare(pullRequest[0].login, "author");
        compare(pullRequest[1].login, "commenter");
        compare(pullRequest[2].login, "reviewer");
        let workflow = worker.normalizeAuthorsForSubject("CheckSuite", "ci_activity", participants);
        compare(workflow.length, 1);
        compare(workflow[0].login, "author");
    }
    function test_successWaitsForParserAndMergesParticipants() {
        worker.requestsInFlight = 1;
        worker.markThreadUrlsActive("42", [subjectUrl]);
        let generation = worker.requestGeneration;
        worker.handleRequestFinished(request(), generation, 0, "test-response", 13, Date.now());
        compare(worker.requestsInFlight, 1);
        verify(worker.fetchedUrlsByThread["42"][subjectUrl]);
        compare(parserMessage.buffer, "test-response");
        compare(parserMessage.generation, generation);
        worker.handleAuthorResult({
            generation: generation,
            threadId: "42",
            updatedAt: "2026-10-24T10:00:00Z",
            subjectType: "PullRequest",
            reason: "comment",
            authors: [
                {
                    login: "author",
                    type: "User"
                },
                {
                    login: "commenter",
                    type: "User"
                }
            ]
        });
        compare(worker.requestsInFlight, 0);
        let snapshot = worker.cloneAuthorsByThread({});
        compare(snapshot["42"].length, 2);
        compare(snapshot["42"][0].login, "author");
        compare(snapshot["42"][1].login, "commenter");
        verify(worker.hasPendingPrefetchWork());
    }

    name: "AuthorBackgroundWorker"

    AuthorBackgroundWorker {
        id: worker

        workerSendMessage: function (message) {
            testCase.parserMessage = message;
        }
    }
    SignalSpy {
        id: completed

        signalName: "prefetchMaybeComplete"
        target: worker
    }
}
