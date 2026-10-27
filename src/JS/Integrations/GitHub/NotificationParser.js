// NotificationParser.js - canonical inbox decoding, pagination and notification URLs.

// No QML singleton context is needed when these pure definitions are included in a worker.

// Bind one error contract without importing QML libraries into a worker context.
function createParser(errorContract) {
    const _GITHUB_INBOX_FALLBACK_URL = "https://github.com/notifications";

    // Join bounded inbox pages and authoritative participation pages without inferring actors.
    function parseMessagesWithParticipationSegments(
        payloadText,
        separator,
        allSegmentCount,
        pageSize,
        targetOldestVisibleUpdatedAtMs
    ) {
        var splitToken = separator || "__GH_PARTICIPATING_SPLIT__";
        var marker = "\n" + splitToken + "\n";
        var normalizedPayload = String(payloadText || "");
        if (normalizedPayload.length > 0 && normalizedPayload.charAt(normalizedPayload.length - 1) !== "\n")
            normalizedPayload += "\n";
        var chunks = normalizedPayload.split(marker);
        var segments = [];

        for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
            var chunk = String(chunks[chunkIndex] || "").trim();
            if (chunk.length > 0) segments.push(chunk);
        }

        if (segments.length === 0)
            throw errorContract.create(
                "GitHub returned an incomplete notification response.",
                "No response segments",
                true
            );

        var count = parseInt(allSegmentCount || 0);
        if (isNaN(count) || count < 1) {
            count = Math.floor(segments.length / 2);
            if (count < 1) count = 1;
        }

        var expectedSegmentCount = count * 2;
        if (segments.length < expectedSegmentCount) {
            throw errorContract.create(
                "GitHub returned an incomplete notification response.",
                "Missing notification pages",
                true
            );
        }

        var allSegments = segments.slice(0, Math.min(count, segments.length));
        var participatingSegments = segments.slice(Math.min(count, segments.length));
        var expectedPageSize = parseInt(pageSize || 50);
        if (isNaN(expectedPageSize) || expectedPageSize < 1) expectedPageSize = 50;

        var allItemsByThread = {};
        var participationMap = {};
        var isComplete = false;
        var targetOldestMs = parseInt(targetOldestVisibleUpdatedAtMs || 0);
        if (isNaN(targetOldestMs)) targetOldestMs = 0;
        var oldestFetchedMs = 0;

        for (var allIndex = 0; allIndex < allSegments.length; allIndex++) {
            var allParsed = parseMessagesPayload(allSegments[allIndex]);
            if (allParsed.error) return allParsed;
            if (allIndex === allSegments.length - 1) isComplete = allParsed.items.length < expectedPageSize;
            for (var allItemIndex = 0; allItemIndex < allParsed.items.length; allItemIndex++) {
                var allItem = allParsed.items[allItemIndex];
                if (!allItem.threadId) continue;
                var updatedAtMs = allItem.updatedAtMs || 0;
                if (updatedAtMs && (oldestFetchedMs === 0 || updatedAtMs < oldestFetchedMs))
                    oldestFetchedMs = updatedAtMs;
                if (!allItemsByThread[allItem.threadId]) allItemsByThread[allItem.threadId] = allItem;
            }
        }

        // A bounded fetch is authoritative for pseudo-Done reconciliation only once
        // its oldest returned `updated_at` reaches the oldest cached visible thread.
        // Widget._applyFetchedMessages reconciles that window through InboxMessageState.
        // GitHub pagination reference:
        // https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api
        if (!isComplete && targetOldestMs > 0 && oldestFetchedMs > 0) isComplete = oldestFetchedMs <= targetOldestMs;

        for (var partIndex = 0; partIndex < participatingSegments.length; partIndex++) {
            var partParsed = parseMessagesPayload(participatingSegments[partIndex]);
            if (partParsed.error) return partParsed;
            for (var partItemIndex = 0; partItemIndex < partParsed.items.length; partItemIndex++) {
                var partItem = partParsed.items[partItemIndex];
                if (partItem.threadId) participationMap[partItem.threadId] = true;
            }
        }

        var mergedItems = [];
        for (var threadId in allItemsByThread) {
            var mergedItem = allItemsByThread[threadId];
            mergedItem.participated = !!participationMap[threadId];
            mergedItems.push(mergedItem);
        }

        mergedItems.sort(function (left, right) {
            if (left.unread !== right.unread) return left.unread ? -1 : 1;
            var leftTimestamp = left.updatedAtMs || 0;
            var rightTimestamp = right.updatedAtMs || 0;
            return rightTimestamp - leftTimestamp;
        });

        return {
            items: mergedItems,
            unreadCount: mergedItems.filter((item) => item.unread).length,
            isComplete: isComplete
        };
    }

    // Decode a notification page into current message fields; malformed input raises PluginError.
    function parseMessagesPayload(payloadText) {
        var payload;
        try {
            payload = JSON.parse(payloadText || "[]");
        } catch (error) {
            throw errorContract.create("GitHub returned invalid JSON.", "Notification JSON decoding failed", false);
        }

        if (!Array.isArray(payload)) {
            throw errorContract.create("Unexpected GitHub response format.", "Expected a notification array", false);
        }

        var items = [];
        for (var index = 0; index < payload.length; index++) {
            var item = payload[index];
            if (!item || typeof item !== "object" || Array.isArray(item))
                throw errorContract.create("Unexpected GitHub response format.", "Invalid notification entry", false);
            var subject = item.subject || {};
            var repository = item.repository || {};

            var updatedAt = item.updated_at || "";

            items.push({
                threadId: item.id || "",
                unread: !!item.unread,
                reason: item.reason || "",
                participated: false,
                updatedAt: updatedAt,
                updatedAtMs: Date.parse(updatedAt) || 0,
                repository: repository.full_name || "",
                repositoryUrl: repository.html_url || "",
                repositoryOwnerLogin: (repository.owner && repository.owner.login) || "",
                repositoryOwnerAvatarUrl: (repository.owner && repository.owner.avatar_url) || "",
                subjectType: subject.type || "Message",
                title: subject.title || "(untitled)",
                subjectApiUrl: subject.url || "",
                subjectReference: "",
                webUrl: resolveWebUrl(item),
                webUrlResolved: false
            });
        }

        items.sort((left, right) =>
            left.unread !== right.unread ? (left.unread ? -1 : 1) : right.updatedAtMs - left.updatedAtMs
        );
        return { items: items, unreadCount: items.filter((item) => item.unread).length };
    }

    // Support the provider's single-list response and the paired list form through the same decoder.
    function parseMessagesWithParticipation(payloadText, separator) {
        let marker = "\n" + (separator || "__GH_PARTICIPATING_SPLIT__") + "\n";
        if (String(payloadText).indexOf(marker) < 0) return parseMessagesPayload(payloadText);
        return parseMessagesWithParticipationSegments(payloadText, separator, 1);
    }

    // Prefer the notification subject destination, then its repository, then the inbox.
    function resolveWebUrl(notification) {
        if (!notification) return _GITHUB_INBOX_FALLBACK_URL;

        var subject = notification.subject || {};
        var apiUrl = subject.url || "";
        var converted = apiToWebUrl(apiUrl, subject.type || "", subject.title || "");
        if (converted) return converted;

        var repository = notification.repository || {};
        if (repository.html_url) return repository.html_url;

        return _GITHUB_INBOX_FALLBACK_URL;
    }

    // Translate a known GitHub subject endpoint without treating workflow IDs as run numbers.
    function apiToWebUrl(apiUrl, subjectType, subjectTitle) {
        if (!apiUrl || apiUrl.indexOf("https://api.github.com/repos/") !== 0) return "";

        var path = apiUrl.substring("https://api.github.com/repos/".length);
        var parts = path.split("/");
        if (parts.length < 2) return "";

        var owner = parts[0];
        var repo = parts[1];
        var base = "https://github.com/" + owner + "/" + repo;
        var tail = parts.slice(2);

        if (tail.length >= 2 && tail[0] === "issues") return base + "/issues/" + tail[1];
        if (tail.length >= 2 && tail[0] === "pulls") return base + "/pull/" + tail[1];
        if (tail.length >= 2 && tail[0] === "commits") return base + "/commit/" + tail[1];
        if (tail.length >= 3 && tail[0] === "actions" && tail[1] === "runs") return base + "/actions/runs/" + tail[2];
        if (tail.length >= 2 && tail[0] === "check-runs") return base + "/runs/" + tail[1];
        if (tail.length >= 2 && tail[0] === "check-suites") return base + "/actions";
        if (tail.length >= 2 && tail[0] === "statuses") return base + "/commit/" + tail[1];
        if (tail.length >= 2 && tail[0] === "discussions") return base + "/discussions/" + tail[1];
        if (tail.length >= 3 && tail[0] === "releases" && tail[1] === "tags")
            return base + "/releases/tag/" + encodeURIComponent(tail.slice(2).join("/"));
        if (tail.length >= 2 && tail[0] === "releases") {
            return base + "/releases";
        }
        if (tail.length >= 3 && tail[0] === "dependabot" && tail[1] === "alerts")
            return base + "/security/dependabot/" + tail[2];
        if (tail.length >= 2 && tail[0] === "security-advisories") return base + "/security/advisories/" + tail[1];
        if (tail.length >= 3 && tail[0] === "code-scanning" && tail[1] === "alerts")
            return base + "/security/code-scanning/" + tail[2];

        return base;
    }

    return {
        parseMessagesWithParticipationSegments,
        parseMessagesPayload,
        parseMessagesWithParticipation,
        resolveWebUrl,
        apiToWebUrl
    };
}
