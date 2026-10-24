// tst_inbox_message_state.qml - tests inbox reconciliation and notification rules.

import QtQuick
import QtTest
import "../../../src/QML/Services"
import "../../../src/QML/Tools"

TestCase {
    function test_doneInferenceOnlyUsesCoveredTimeWindow() {
        let previous = [
            {
                threadId: "newer",
                updatedAtMs: 300
            },
            {
                threadId: "older",
                updatedAtMs: 100
            }
        ];
        let incoming = [
            {
                threadId: "boundary",
                updatedAtMs: 200
            }
        ];
        let inferred = messageState.inferDoneMessagesFromRefresh(previous, incoming, ({}));

        compare(inferred.length, 1);
        compare(inferred[0].threadId, "newer");
    }
    function test_messageEquivalenceIncludesVisibleFields() {
        let original = {
            threadId: "one",
            title: "Title",
            updatedAtMs: 100,
            unread: true
        };
        let same = {
            threadId: "one",
            title: "Title",
            updatedAtMs: 100,
            unread: true
        };
        let changed = {
            threadId: "one",
            title: "Changed",
            updatedAtMs: 100,
            unread: true
        };

        verify(messageState.messageEquivalent(original, same));
        verify(!messageState.messageEquivalent(original, changed));
        compare(messageState.recalculateUnread([original, changed]), 2);
    }
    function test_messageStateFiltersDoneAndTracksTimeBounds() {
        let messages = [
            {
                threadId: "one",
                updatedAtMs: 400,
                unread: true
            },
            {
                threadId: "two",
                updatedAtMs: 100,
                unread: false
            }
        ];
        let visible = messageState.filterDoneMessages(messages, ({
                "one": true
            }));

        compare(visible.length, 1);
        compare(messageState.oldestMessageUpdatedAtMs(messages), 100);
        compare(messageState.latestMessageUpdatedAtMs(messages), 400);
    }
    function test_newMessageDetectionUsesUpdatedAtAndSkipsDone() {
        let baseline = Date.parse("2026-10-22T10:00:00Z");
        let messages = [
            {
                threadId: "new",
                unread: true,
                updatedAt: "2026-10-23T10:00:00Z"
            },
            {
                threadId: "old",
                unread: true,
                updatedAt: "2026-10-22T09:00:00Z"
            },
            {
                threadId: "done",
                unread: true,
                updatedAt: "2026-10-23T11:00:00Z"
            },
            {
                threadId: "read",
                unread: false,
                updatedAt: "2026-10-23T12:00:00Z"
            }
        ];

        notifications.setBaseline([
            {
                threadId: "baseline",
                updatedAtMs: baseline
            }
        ]);
        let result = notifications.detectNewMessages(messages, ({
                done: true
            }));

        compare(result.length, 1);
        compare(result[0].threadId, "new");
    }
    function test_notificationCommandUsesTitlesForTwoAndGenericForMore() {
        let two = notifications.messageNotificationCommand([
            {
                title: "First title\nsecond line",
                repository: "owner/one"
            },
            {
                title: "Second title",
                repository: "owner/two"
            }
        ]);
        let twoBody = two[two.length - 1];
        verify(twoBody.indexOf("First title\nowner/one") >= 0);
        verify(twoBody.indexOf("second line") < 0);
        verify(twoBody.indexOf("Second title\nowner/two") >= 0);

        let many = notifications.messageNotificationCommand([
            {
                title: "One",
                repository: "owner/one"
            },
            {
                title: "Two",
                repository: "owner/one"
            },
            {
                title: "Three",
                repository: "owner/two"
            }
        ]);
        let manyBody = many[many.length - 1];
        compare(many[many.length - 2], "3 New GitHub Messages");
        verify(manyBody.indexOf("New GitHub messages") === 0);
        verify(manyBody.indexOf("owner/one, owner/two") >= 0);
        verify(manyBody.indexOf("One") < 0);
    }
    // A capped refresh must neither erase older cache entries nor duplicate returned threads.
    function test_refreshRetainsUncoveredCache() {
        let previous = [
            {
                threadId: "recentMissing",
                updatedAtMs: 300
            },
            {
                threadId: "boundary",
                updatedAtMs: 200
            },
            {
                threadId: "old",
                updatedAtMs: 100
            }
        ];
        let incoming = [
            {
                threadId: "boundary",
                updatedAtMs: 200
            }
        ];
        let covered = messageState.retainUncoveredMessages(previous, incoming, true);
        compare(covered.map(item => item.threadId), ["boundary", "old"]);
        let partial = messageState.retainUncoveredMessages(previous, incoming, false);
        compare(partial.map(item => item.threadId), ["recentMissing", "boundary", "old"]);
        compare(messageState.retainUncoveredMessages(previous, [], false).length, 3);
        compare(messageState.retainUncoveredMessages(previous, [], true).length, 0);
    }

    name: "InboxMessageState"

    InboxMessageState {
        id: messageState

        constants: ({
                expandedStateDefaultKey: "__default__",
                githubWebBaseUrl: "https://github.com",
                maxAuthorsDisplayedPerMessage: 3
            })
    }
    DesktopNotificationService {
        id: notifications

        cacheCoordinator: ({
                cachedLocalAvatarUrl: function () {
                    return "";
                }
            })
        fallbackIcon: ""
        messageState: messageState
    }
}
