// tst_author_prefetch_service.qml - verifies bounded author-prefetch scheduling and batching.

import QtQuick
import QtTest
import "../../../src/QML/Services"
import "../../../src/QML" as Plugin

TestCase {
    function cleanup() {
        prefetch.reset();
    }
    function init() {
        prefetch.reset();
        prefetch.token = "test-token";
        prefetch.loadAuthorInfo = true;
        worker.requests = [];
        worker.authorsByThreadRef = ({});
        worker.fetchedAtUpdatedAt = ({});
        worker.fetchedUrlsByThread = ({});
        completed.clear();
    }
    function message(threadId, needsUrl) {
        return {
            threadId: threadId,
            subjectApiUrl: "https://api.github.com/repos/owner/repo/pulls/42",
            subjectType: "PullRequest",
            updatedAt: "current",
            needsUrl: !!needsUrl
        };
    }
    function test_cachedAndActiveThreadsAreSkippedWhileForcedDetailsRefresh() {
        worker.authorsByThreadRef = ({
                "cached": [
                    {}
                ],
                "forced": [
                    {}
                ]
            });
        worker.fetchedAtUpdatedAt = ({
                "cached": "current",
                "forced": "current"
            });
        worker.fetchedUrlsByThread = ({
                "forced": {
                    old: true
                }
            });
        prefetch.prefetchForMessages([message("cached"), message("busy"), message("forced", true), message("missing"), message("missing")]);
        compare(prefetch._prefetchQueue.length, 2);
        prefetch._processPrefetchBatch();
        compare(worker.requests.length, 1);
        compare(worker.requests[0].threadId, "forced");
        compare(worker.fetchedUrlsByThread.forced, undefined);
        prefetch._processPrefetchBatch();
        compare(worker.requests.length, 2);
        compare(worker.requests[1].threadId, "missing");
        compare(completed.count, 1);
        verify(!prefetch.isBusy);
    }
    function test_missingTokenStopsPendingWork() {
        prefetch.prefetchForMessages([message("one")]);
        prefetch.token = "";
        prefetch._processPrefetchBatch();
        verify(!prefetch.isBusy);
        compare(worker.requests.length, 0);
        compare(completed.count, 1);
    }
    function test_refreshBudgetAndReset() {
        let messages = [];
        let limit = Plugin.GitHubConstants.maxAuthorPrefetchMessagesPerRefresh;
        for (let index = 0; index < limit + 2; index++)
            messages.push(message("thread-" + index));
        prefetch.prefetchForMessages(messages);
        compare(prefetch._prefetchQueue.length, limit);
        prefetch.prefetchForMessages(messages);
        compare(prefetch._prefetchQueue.length, limit);
        prefetch.reset();
        verify(!prefetch.isBusy);
        prefetch.prefetchForMessages([message("new")]);
        compare(prefetch._prefetchQueue.length, 1);
    }
    function test_restoredAuthorsSkipFreshThreadsAndFetchMissingOnes() {
        worker.fetchedAtUpdatedAt = ({
                "cached": "current"
            });
        prefetch.prefetchMissingForMessages([message("cached"), message("missing")], {
            "cached": [
                {}
            ]
        });
        compare(prefetch._prefetchQueue.length, 1);
        prefetch._processPrefetchBatch();
        compare(worker.requests.length, 1);
        compare(worker.requests[0].threadId, "missing");
    }

    name: "AuthorPrefetchService"

    AuthorPrefetchService {
        id: prefetch

        authorWorker: worker
    }
    QtObject {
        id: worker

        property var authorsByThreadRef: ({})
        property var fetchedAtUpdatedAt: ({})
        property var fetchedUrlsByThread: ({})
        property var requests: []

        function enqueueAuthorUrls(threadId, urls) {
            requests.push({
                threadId: threadId,
                urls: urls
            });
        }
        function fallbackAuthorForMessage(item) {
            return null;
        }
        function fetchedAtMatches(cached, updatedAt) {
            return String(cached || "") === String(updatedAt || "");
        }
        function hasFetchedAuthorDetailsForMessage(item) {
            return true;
        }
        function hasQueuedOrActiveThreadRequest(threadId) {
            return threadId === "busy";
        }
        function requiresSubjectReferenceResolution(item) {
            return false;
        }
        function requiresSubjectWebUrlResolution(item) {
            return item.needsUrl;
        }
        function shouldFetchAuthorDetailsForMessage(item) {
            return false;
        }
    }
    SignalSpy {
        id: completed

        signalName: "prefetchMaybeComplete"
        target: prefetch
    }
}
