// tst_avatar_state.qml - tests avatar state transforms and propagation batching.

import QtQuick
import QtTest
import "../../../src/QML/Services"
import "../../../src/QML/Tools"

TestCase {
    id: testCase

    property var emittedBatches: []

    function init() {
        emittedBatches = [];
        propagation.reset();
    }
    function test_avatarBatchQueueDeduplicatesLoginsAndRespectsBatchSize() {
        propagation.queue("one", "file:///one-old.png");
        propagation.queue("one", "file:///one.png");
        propagation.queue("two", "file:///two.png");
        propagation.queue("three", "file:///three.png");

        let batch = propagation.processBatch();

        compare(Object.keys(batch).length, 2);
        compare(batch.one, "file:///one.png");
        compare(propagation.pendingCount, 1);
        compare(propagation.pendingUpdates.three, "file:///three.png");
        compare(emittedBatches.length, 1);
    }
    function test_avatarUpdatesAreAppliedToMessagesViewsAndAuthors() {
        let message = {
            threadId: "thread-1",
            repositoryOwnerLogin: "owner",
            repositoryOwnerAvatarUrl: "https://avatars.example/owner"
        };
        let author = {
            login: "owner",
            avatarUrl: "https://avatars.example/owner"
        };
        let messages = [message];
        let viewMessages = [message];
        let authors = ({
                "thread-1": [author]
            });
        let result = avatarState.applyLocalAvatarUpdates(messages, viewMessages, authors, ({
                owner: "file:///cache/owner.png"
            }));

        verify(result.messagesChanged);
        verify(result.authorsChanged);
        compare(result.messages[0].repositoryOwnerAvatarUrl, "file:///cache/owner.png");
        compare(result.viewMessages[0].repositoryOwnerAvatarUrl, "file:///cache/owner.png");
        compare(result.authorsByThread["thread-1"][0].avatarUrl, "file:///cache/owner.png");
        compare(message.repositoryOwnerAvatarUrl, "https://avatars.example/owner");
        compare(author.avatarUrl, "https://avatars.example/owner");
    }

    name: "AvatarState"

    AvatarState {
        id: avatarState
    }
    AvatarPropagationService {
        id: propagation

        automaticProcessing: false
        batchSize: 2

        onBatchReady: function (updates) {
            let copy = {};
            for (let login in updates)
                copy[login] = updates[login];
            let next = testCase.emittedBatches.slice(0);
            next.push(copy);
            testCase.emittedBatches = next;
        }
    }
}
