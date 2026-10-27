// AuthorMergeService.qml - batches author-list updates and avatar preload candidates.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: service

    property var authorsByThread: ({})
    property bool flushQueued: false
    readonly property bool isBusy: flushQueued || flushTimer.running
    property var pendingAuthors: ({})
    property var pendingAvatars: []

    signal merged(var authorsByThread, var preloadAuthors, var changedThreadIds)

    // Include unpublished updates when callers need a current author snapshot.
    function cloneAuthorsByThread(authors) {
        let copy = {};
        for (let threadId in authors)
            copy[threadId] = authors[threadId];
        for (let pendingId in pendingAuthors)
            copy[pendingId] = pendingAuthors[pendingId];
        return copy;
    }
    // Publish one bounded batch and retain remaining threads for the next timer tick.
    function flush() {
        let start = Date.now();
        flushQueued = false;
        let pending = pendingAuthors;
        let remaining = {};
        let avatars = pendingAvatars;
        let changedIds = [];
        let remainingCount = 0;
        for (let threadId in pending) {
            if (changedIds.length >= GitHubConstants.authorMergeFlushBatchSize) {
                remaining[threadId] = pending[threadId];
                remainingCount++;
            } else {
                changedIds.push(threadId);
            }
        }
        if (changedIds.length === 0) {
            pendingAuthors = remaining;
            pendingAvatars = avatars;
            if (remainingCount > 0)
                schedule();
            PluginLogger.profile("AuthorBackgroundWorker", "_flushMerges", Date.now() - start, "changed=0");
            return;
        }
        let next = {};
        for (let existingId in authorsByThread || ({}))
            next[existingId] = authorsByThread[existingId];
        for (let index = 0; index < changedIds.length; index++)
            next[changedIds[index]] = pending[changedIds[index]];
        pendingAuthors = remaining;
        pendingAvatars = [];
        merged(next, avatars, changedIds);
        if (remainingCount > 0)
            schedule();
        PluginLogger.profile("AuthorBackgroundWorker", "_flushMerges", Date.now() - start, "changed=" + changedIds.length + " remaining=" + remainingCount);
    }
    // Discard unpublished authors and stop the pending flush.
    function reset() {
        flushTimer.stop();
        pendingAuthors = ({});
        pendingAvatars = [];
        flushQueued = false;
    }
    // Schedule one flush for all updates staged during the current interval.
    function schedule() {
        if (flushQueued)
            return;
        flushQueued = true;
        flushTimer.restart();
    }
    // Merge participants for one thread, replacing existing authors on automatic prefetch.
    function stage(threadId, fetchedAuthors, automaticPrefetch) {
        let current = authorsByThread || ({});
        let existing = automaticPrefetch ? [] : (pendingAuthors[threadId] || current[threadId] || []);
        let authors = AuthorUtils.mergeAuthorLists(existing, fetchedAuthors);
        let next = pendingAuthors;
        next[threadId] = authors;
        pendingAuthors = next;
        let avatars = pendingAvatars;
        for (let index = 0; index < authors.length; index++)
            avatars.push(authors[index]);
        pendingAvatars = avatars;
    }

    visible: false

    Timer {
        id: flushTimer

        interval: GitHubConstants.authorMergeFlushIntervalMs
        repeat: false

        onTriggered: service.flush()
    }
}
