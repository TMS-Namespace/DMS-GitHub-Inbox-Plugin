// InboxMessageDetails.qml - pure message subject URL/reference transformations.

pragma Singleton

import QtQml

QtObject {
    // Replace only the matching notification and preserve the original array on a no-op.
    function withResolvedSubjectDetails(messages, threadId, webUrl, subjectReference) {
        if (!threadId)
            return messages;

        let normalizedReference = String(subjectReference || "").trim().replace(/^#/, "");
        let changed = false;
        let nextMessages = [];
        for (let index = 0; index < messages.length; index++) {
            let item = messages[index];
            let matchesThread = item && item.threadId === threadId;
            let shouldUpdateWebUrl = matchesThread && webUrl && (item.webUrl !== webUrl || !item.webUrlResolved);
            let shouldUpdateReference = matchesThread && normalizedReference && item.subjectReference !== normalizedReference;
            if (!shouldUpdateWebUrl && !shouldUpdateReference) {
                nextMessages.push(item);
                continue;
            }

            let copy = Object.assign({}, item);
            if (shouldUpdateWebUrl) {
                copy.webUrl = webUrl;
                copy.webUrlResolved = true;
            }
            if (shouldUpdateReference)
                copy.subjectReference = normalizedReference;
            nextMessages.push(copy);
            changed = true;
        }
        return changed ? nextMessages : messages;
    }
}
