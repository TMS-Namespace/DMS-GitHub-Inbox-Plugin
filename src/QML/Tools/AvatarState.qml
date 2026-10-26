// AvatarState.qml - immutable local-avatar propagation over inbox state.

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: avatarState

    // Update all observable message and author copies from one local resource batch.
    function applyLocalAvatarUpdates(messages, viewMessages, authorsByThread, updates) {
        let resultMessages = updateMessages(messages || [], updates || {});
        let resultViewMessages = updateMessages(viewMessages || [], updates || {});
        let resultAuthors = updateAuthors(authorsByThread || ({}), updates || {});
        return {
            authorsByThread: resultAuthors.value,
            authorsChanged: resultAuthors.changed,
            messages: resultMessages.value,
            messagesChanged: resultMessages.changed,
            viewMessages: resultViewMessages.value,
            viewMessagesChanged: resultViewMessages.changed
        };
    }
    // Copy caller-owned data before publishing a reactive replacement.
    function cloneObject(source) {
        let copy = {};
        for (let key in source)
            copy[key] = source[key];
        return copy;
    }
    // Replace changed author arrays while preserving unrelated thread records.
    function updateAuthors(authorsByThread, updates) {
        let nextAuthors = {};
        let changed = false;
        for (let threadId in authorsByThread) {
            let authors = authorsByThread[threadId] || [];
            let nextAuthorsForThread = authors;
            for (let index = 0; index < authors.length; index++) {
                let author = authors[index];
                let localUrl = updates[String((author && author.login) || "")];
                if (!localUrl || author.avatarUrl === localUrl && !localUrl.startsWith("file://"))
                    continue;
                if (nextAuthorsForThread === authors)
                    nextAuthorsForThread = authors.slice(0);
                let copy = cloneObject(author);
                copy.avatarUrl = localUrl;
                nextAuthorsForThread[index] = copy;
                changed = true;
            }
            nextAuthors[threadId] = nextAuthorsForThread;
        }
        return {
            changed: changed,
            value: changed ? nextAuthors : authorsByThread
        };
    }
    // Publish a new message snapshot without treating local edits as successful remote refreshes.
    function updateMessages(messages, updates) {
        let nextMessages = messages.slice(0);
        let changed = false;
        for (let index = 0; index < messages.length; index++) {
            let message = messages[index];
            let localUrl = updates[String((message && message.repositoryOwnerLogin) || "")];
            if (!localUrl || message.repositoryOwnerAvatarUrl === localUrl && !localUrl.startsWith("file://"))
                continue;
            let copy = cloneObject(message);
            copy.repositoryOwnerAvatarUrl = localUrl;
            nextMessages[index] = copy;
            changed = true;
        }
        return {
            changed: changed,
            value: changed ? nextMessages : messages
        };
    }
}
