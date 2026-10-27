// InboxMessageState.qml - pure message normalization and reconciliation rules.

pragma ComponentBehavior: Bound

import QtQuick
import "."

Item {
    id: messageState

    property var constants: null

    // Hydrate a repository avatar without changing unrelated message fields.
    function applyKnownLocalRepositoryAvatar(item, localAvatarsByLogin, cacheCoordinator, cacheInitialized) {
        if (!item)
            return item;

        let login = String(item.repositoryOwnerLogin || "").trim();
        let localAvatarUrl = login ? (localAvatarsByLogin[login] || "") : "";
        if (!localAvatarUrl && login && cacheInitialized) {
            localAvatarUrl = cacheCoordinator.cachedLocalAvatarUrl(login);
            if (localAvatarUrl)
                localAvatarsByLogin[login] = localAvatarUrl;
        }
        if (!localAvatarUrl || localAvatarUrl === item.repositoryOwnerAvatarUrl)
            return item;

        let copy = cloneObject(item);
        copy.repositoryOwnerAvatarUrl = localAvatarUrl;
        return copy;
    }
    // Preserve the default expansion key when copying persisted group state.
    function cloneExpandedState(state) {
        let copy = cloneObject(state || {});
        if (copy[constants.expandedStateDefaultKey] === undefined)
            copy[constants.expandedStateDefaultKey] = true;
        return copy;
    }
    // Copy caller-owned data before publishing a reactive replacement.
    function cloneObject(source) {
        let copy = {};
        for (let key in source)
            copy[key] = source[key];
        return copy;
    }
    // Reuse known local resources rather than replacing them with remote URLs.
    function collectKnownLocalAvatars(authorsByThread) {
        let localAvatarsByLogin = {};
        for (let threadId in authorsByThread) {
            let authors = authorsByThread[threadId] || [];
            for (let index = 0; index < authors.length; index++)
                rememberKnownLocalAvatar(localAvatarsByLogin, authors[index].login, authors[index].avatarUrl);
        }
        return localAvatarsByLogin;
    }
    // Hide confirmed or pending Done records without altering the source list.
    function filterDoneMessages(items, doneThreadState) {
        let filtered = [];
        let source = items || [];
        let doneState = doneThreadState || ({});
        for (let index = 0; index < source.length; index++) {
            let item = source[index];
            if (item && item.threadId && doneState[item.threadId])
                continue;
            filtered.push(item);
        }
        return filtered;
    }
    // Infer absence only for cached timestamps covered by the successful response.
    function inferDoneMessagesFromRefresh(previousItems, incomingItems, doneThreadState) {
        let previous = previousItems || [];
        let incoming = incomingItems || [];
        let doneState = doneThreadState || ({});
        if (previous.length === 0)
            return [];

        let incomingByThread = {};
        let oldestIncomingMs = 0;
        for (let index = 0; index < incoming.length; index++) {
            let item = incoming[index];
            if (!item || !item.threadId)
                continue;
            incomingByThread[item.threadId] = true;
            let updatedAtMs = messageUpdatedAtMs(item);
            if (updatedAtMs && (oldestIncomingMs === 0 || updatedAtMs < oldestIncomingMs))
                oldestIncomingMs = updatedAtMs;
        }

        let inferred = [];
        let seenThreads = {};
        for (let index = 0; index < previous.length; index++) {
            let item = previous[index];
            if (!item || !item.threadId || incomingByThread[item.threadId] || doneState[item.threadId] || seenThreads[item.threadId])
                continue;
            if (incoming.length > 0) {
                let updatedAtMs = messageUpdatedAtMs(item);
                if (!oldestIncomingMs || !updatedAtMs || updatedAtMs < oldestIncomingMs)
                    continue;
            }
            seenThreads[item.threadId] = true;
            inferred.push(item);
        }
        return inferred;
    }
    // Recognize check-suite, check-run and workflow-run subjects case-insensitively.
    function isCiSubjectType(subjectType) {
        let normalizedType = String(subjectType || "").toLowerCase();
        return normalizedType === "checksuite" || normalizedType === "checkrun" || normalizedType === "workflowrun";
    }
    // Identify workflow automation separately from human PR participation.
    function isGitHubActionsAuthor(author) {
        let login = String((author && author.login) || "").trim().toLowerCase();
        let htmlUrl = String((author && (author.htmlUrl || author.html_url)) || "").trim().toLowerCase();
        return login === "github-actions" || login === "github-actions[bot]" || htmlUrl === constants.githubWebBaseUrl + "/apps/github-actions";
    }
    // Find the newest valid activity timestamp for notification baselines.
    function latestMessageUpdatedAtMs(items) {
        let latest = 0;
        let source = items || [];
        for (let index = 0; index < source.length; index++) {
            let updatedAtMs = messageUpdatedAtMs(source[index]);
            if (updatedAtMs > latest)
                latest = updatedAtMs;
        }
        return latest;
    }
    // Retain resolved references and local resources when activity timestamps still match.
    function mergeCachedMessageFields(items, existingMessages, authorsByThread, cacheCoordinator, cacheInitialized) {
        let existingByThread = {};
        let localAvatarsByLogin = collectKnownLocalAvatars(authorsByThread || ({}));
        let existing = existingMessages || [];
        let incoming = items || [];
        for (let index = 0; index < existing.length; index++) {
            let item = existing[index];
            if (item && item.threadId) {
                existingByThread[item.threadId] = item;
                rememberKnownLocalAvatar(localAvatarsByLogin, item.repositoryOwnerLogin, item.repositoryOwnerAvatarUrl);
            }
        }

        let merged = [];
        for (let index = 0; index < incoming.length; index++) {
            let item = incoming[index];
            if (!item || !item.threadId) {
                merged.push(item);
                continue;
            }

            let cached = existingByThread[item.threadId];
            if (!cached || (cached.updatedAt || "") !== (item.updatedAt || "")) {
                merged.push(applyKnownLocalRepositoryAvatar(item, localAvatarsByLogin, cacheCoordinator, cacheInitialized));
                continue;
            }

            let copy = item;
            if (cached.webUrlResolved && cached.webUrl && cached.webUrl !== item.webUrl) {
                copy = cloneObject(copy);
                copy.webUrl = cached.webUrl;
                copy.webUrlResolved = true;
            } else if (cached.webUrlResolved && !item.webUrlResolved) {
                copy = cloneObject(copy);
                copy.webUrlResolved = true;
            }

            let cachedSubjectReference = String(cached.subjectReference || "");
            if (cachedSubjectReference && cachedSubjectReference !== (item.subjectReference || "")) {
                copy = cloneObject(copy);
                copy.subjectReference = cachedSubjectReference;
            }

            let cachedAvatarUrl = String(cached.repositoryOwnerAvatarUrl || "");
            if (cachedAvatarUrl.indexOf("file://") === 0 && cachedAvatarUrl !== item.repositoryOwnerAvatarUrl) {
                copy = cloneObject(copy);
                copy.repositoryOwnerAvatarUrl = cachedAvatarUrl;
            }

            merged.push(applyKnownLocalRepositoryAvatar(copy, localAvatarsByLogin, cacheCoordinator, cacheInitialized));
        }
        return merged;
    }
    // Compare user-visible fields before deciding that a refresh can skip rebuilding delegates.
    function messageEquivalent(left, right) {
        if (!left || !right)
            return left === right;
        return (left.threadId || "") === (right.threadId || "") && (!!left.unread === !!right.unread) && (left.reason || "") === (right.reason || "") && (!!left.participated === !!right.participated) && (left.updatedAt || "") === (right.updatedAt || "") && (left.updatedAtMs || 0) === (right.updatedAtMs || 0) && (left.repository || "") === (right.repository || "") && (left.repositoryUrl || "") === (right.repositoryUrl || "") && (left.repositoryOwnerLogin || "") === (right.repositoryOwnerLogin || "") && (left.repositoryOwnerAvatarUrl || "") === (right.repositoryOwnerAvatarUrl || "") && (left.subjectType || "") === (right.subjectType || "") && (left.title || "") === (right.title || "") && (left.subjectApiUrl || "") === (right.subjectApiUrl || "") && (left.subjectReference || "") === (right.subjectReference || "") && (left.webUrl || "") === (right.webUrl || "") && (!!left.webUrlResolved === !!right.webUrlResolved);
    }
    // Use parsed UTC activity time and keep invalid timestamps outside authoritative comparisons.
    function messageUpdatedAtMs(item) {
        if (!item)
            return 0;
        return item.updatedAtMs || Date.parse(item.updatedAt || "") || 0;
    }
    // Require both ordering and field equality before treating message arrays as unchanged.
    function messagesEquivalent(left, right) {
        if (!left || !right || left.length !== right.length)
            return false;
        for (let index = 0; index < left.length; index++) {
            if (!messageEquivalent(left[index], right[index]))
                return false;
        }
        return true;
    }
    // Remove stale actor candidates while retaining usable cached participants.
    function normalizeCachedAuthorsForMessage(message, authors) {
        let repositoryOwner = String(message.repositoryOwnerLogin || "").trim().toLowerCase();
        let normalizedType = String(message.subjectType || "").toLowerCase();
        let normalizedReason = String(message.reason || "").toLowerCase();
        let filtered = [];
        let source = authors || [];
        for (let index = 0; index < source.length; index++) {
            let author = source[index];
            let authorLogin = String((author && author.login) || "").trim().toLowerCase();
            if (authorLogin && authorLogin === repositoryOwner)
                continue;
            if ((normalizedType === "pullrequest" || normalizedType === "issue") && isGitHubActionsAuthor(author))
                continue;
            filtered.push(author);
        }
        if (isCiSubjectType(message.subjectType) && filtered.length > 1)
            return filtered.slice(0, 1);
        if ((normalizedType === "pullrequest" || normalizedType === "issue") && normalizedReason === "comment" && filtered.length > constants.maxAuthorsDisplayedPerMessage)
            return filtered.slice(0, constants.maxAuthorsDisplayedPerMessage);
        if (normalizedType === "pullrequest" && normalizedReason === "author" && filtered.length > constants.maxAuthorsDisplayedPerMessage)
            return filtered.slice(0, constants.maxAuthorsDisplayedPerMessage);
        return filtered;
    }
    // Find the oldest valid retained timestamp that dynamic pagination must cover.
    function oldestMessageUpdatedAtMs(items) {
        let oldest = 0;
        let source = items || [];
        for (let index = 0; index < source.length; index++) {
            let updatedAtMs = messageUpdatedAtMs(source[index]);
            if (updatedAtMs && (oldest === 0 || updatedAtMs < oldest))
                oldest = updatedAtMs;
        }
        return oldest;
    }
    // Compute the unread count from retained messages after reconciliation.
    function recalculateUnread(items) {
        let count = 0;
        let source = items || [];
        for (let index = 0; index < source.length; index++) {
            if (source[index] && source[index].unread)
                count++;
        }
        return count;
    }
    // Keep only local resources that can be reused by login.
    function rememberKnownLocalAvatar(localAvatarsByLogin, login, avatarUrl) {
        let normalizedLogin = String(login || "").trim();
        let normalizedUrl = String(avatarUrl || "");
        if (normalizedLogin && normalizedUrl.indexOf("file://") === 0)
            localAvatarsByLogin[normalizedLogin] = normalizedUrl;
    }
    // Preserve cached threads outside the fetched window; only covered absences can mean Done.
    function retainUncoveredMessages(previousItems, incomingItems, complete) {
        let incoming = incomingItems || [];
        let result = incoming.slice(0);
        let seen = {};
        for (let item of incoming)
            if (item && item.threadId)
                seen[item.threadId] = true;
        let oldestIncoming = oldestMessageUpdatedAtMs(incoming);
        for (let item of previousItems || []) {
            if (!item || !item.threadId || seen[item.threadId])
                continue;
            let timestamp = messageUpdatedAtMs(item);
            if (!complete || (incoming.length > 0 && (!timestamp || !oldestIncoming || timestamp < oldestIncoming))) {
                result.push(item);
                seen[item.threadId] = true;
            }
        }
        result.sort((left, right) => messageUpdatedAtMs(right) - messageUpdatedAtMs(left));
        return result;
    }
}
