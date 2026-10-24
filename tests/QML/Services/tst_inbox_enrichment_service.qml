// tst_inbox_enrichment_service.qml - tests cache author cleanup and enrichment selection.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    function init() {
        enrichment.loadAuthorInfo = true;
        enrichment.messages = [];
        authorWorker.requests = [];
        cacheCoordinator.authorUpdates = [];
        cacheCoordinator.fetchedAtUpdates = [];
        enrichment.authorsByThread = ({
                keep: [
                    {
                        login: "contributor",
                        avatarUrl: "avatar"
                    }
                ],
                old: [
                    {
                        login: "contributor",
                        avatarUrl: "avatar"
                    }
                ]
            });
        authorWorker.fetchedAtUpdatedAt = ({
                keep: "updated",
                old: "updated"
            });
        authorWorker.fetchedUrlsByThread = ({
                keep: {
                    url: true
                },
                old: {
                    url: true
                }
            });
    }
    function test_enrichmentSelectionIncludesMissingRemoteAvatarAndAuthorInfo() {
        enrichment.loadAuthorInfo = false;
        let messages = [
            {
                threadId: "remote-avatar",
                repositoryOwnerLogin: "owner",
                repositoryOwnerAvatarUrl: "https://avatar.example/owner"
            },
            {
                threadId: "local-avatar",
                repositoryOwnerLogin: "owner",
                repositoryOwnerAvatarUrl: "file:///cache/owner.png"
            }
        ];
        let result = enrichment.filterMessagesNeedingEnrichment(messages);

        compare(result.length, 1);
        compare(result[0].threadId, "remote-avatar");
    }
    // Explicit arguments still take precedence, and disabling author details stops dispatch.
    function test_explicitAuthorRequestRespectsOverridesAndDisabledSetting() {
        enrichment.messages = [
            {
                threadId: "42",
                subjectType: "PullRequest",
                subjectApiUrl: "https://api.github.com/repos/owner/repo/pulls/42"
            }
        ];
        enrichment.requestThreadAuthors("42", "https://api.github.com/repos/owner/repo/issues/42", "Issue");
        compare(authorWorker.requests[0].subjectType, "Issue");
        compare(authorWorker.requests[0].url, "https://api.github.com/repos/owner/repo/issues/42");
        enrichment.loadAuthorInfo = false;
        enrichment.requestThreadAuthors("42", "", "");
        compare(authorWorker.requests.length, 1);
    }
    // Selection context belongs to the service and must preserve the notification timestamp/title.
    function test_explicitAuthorRequestUsesMatchingNotification() {
        enrichment.messages = [
            {
                threadId: "other",
                title: "Other"
            },
            {
                threadId: "42",
                title: "Selected PR",
                subjectType: "PullRequest",
                updatedAt: "2026-10-24T10:00:00Z",
                webUrl: "https://github.com/owner/repo/pull/42"
            }
        ];
        enrichment.requestThreadAuthors("42", "", "");
        compare(authorWorker.requests.length, 1);
        let request = authorWorker.requests[0];
        compare(request.threadId, "42");
        compare(request.url, "https://api.github.com/repos/owner/repo/pulls/42");
        compare(request.subjectType, "PullRequest");
        compare(request.updatedAt, "2026-10-24T10:00:00Z");
        compare(request.title, "Selected PR");
        compare(request.automatic, false);
    }
    function test_pruningRetainsOnlyCurrentThreadState() {
        enrichment.pruneAuthorCaches([
            {
                threadId: "keep"
            }
        ]);

        verify(enrichment.authorsByThread.keep);
        compare(enrichment.authorsByThread.old, undefined);
        verify(authorWorker.fetchedUrlsByThread.keep);
        compare(authorWorker.fetchedUrlsByThread.old, undefined);
        compare(cacheCoordinator.prunedThreads, ["keep"]);
    }
    function test_repositoryOwnerAuthorIsRemovedAndMarkedForRefetch() {
        let cachedAuthors = ({
                thread: [
                    {
                        login: "repo-owner",
                        avatarUrl: "avatar"
                    },
                    {
                        login: "contributor",
                        avatarUrl: "avatar"
                    }
                ]
            });
        let fetchedAt = ({
                thread: "same-update"
            });

        enrichment.sanitizeCachedAuthors([
            {
                threadId: "thread",
                repositoryOwnerLogin: "repo-owner",
                updatedAt: "same-update"
            }
        ], cachedAuthors, fetchedAt);

        compare(cachedAuthors.thread.length, 1);
        compare(cachedAuthors.thread[0].login, "contributor");
        compare(fetchedAt.thread, "");
        compare(cacheCoordinator.authorUpdates.length, 1);
        compare(cacheCoordinator.authorUpdates[0].threadId, "thread");
    }

    name: "InboxEnrichmentService"

    InboxEnrichmentService {
        id: enrichment

        loadAuthorInfo: true

        authorWorker: QtObject {
            id: authorWorker

            property var fetchedAtUpdatedAt: ({})
            property var fetchedUrlsByThread: ({})
            property var requests: []

            // Record dispatches without starting network work.
            function enqueueAuthorFetch(threadId, url, subjectType, updatedAt, automatic, fallbackAuthor, title) {
                requests = requests.concat([
                    {
                        threadId: threadId,
                        url: url,
                        subjectType: subjectType,
                        updatedAt: updatedAt,
                        automatic: automatic,
                        title: title
                    }
                ]);
            }
            function fetchedAtMatches(value) {
                return !!value;
            }
            function hasFetchedAuthorDetailsForMessage() {
                return true;
            }
            function requiresSubjectReferenceResolution() {
                return false;
            }
            function requiresSubjectWebUrlResolution() {
                return false;
            }
        }
        cacheCoordinator: QtObject {
            id: cacheCoordinator

            property var authorUpdates: []
            property var fetchedAtUpdates: []
            property var prunedThreads: []

            function pruneToThreads(threadIds) {
                prunedThreads = threadIds;
            }
            function updateAuthorFetchedAt(threadId, updatedAt) {
                fetchedAtUpdates = fetchedAtUpdates.concat([
                    {
                        threadId: threadId,
                        updatedAt: updatedAt
                    }
                ]);
            }
            function updateChangedAuthors(authors) {
                for (let threadId in authors)
                    authorUpdates = authorUpdates.concat([
                        {
                            threadId: threadId,
                            authors: authors[threadId]
                        }
                    ]);
            }
        }
        messageState: QtObject {
            function normalizeCachedAuthorsForMessage(message, authors) {
                return authors.filter(author => author.login !== message.repositoryOwnerLogin);
            }
        }
    }
}
