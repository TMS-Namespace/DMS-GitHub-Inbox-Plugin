// DesktopNotificationService.qml - batches inbox notifications through the built-in Dux CLI.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: service

    property real baselineUpdatedAtMs: 0
    property var cacheCoordinator: null
    property real errorNotificationAt: 0
    property string errorNotificationText: ""
    property var fallbackIcon: ""
    property var messageState: null
    property bool notificationsEnabled: true
    property var pendingMessages: []

    // Discard deferred notifications before a failed or superseded refresh can deliver them.
    function clearPending() {
        pendingMessages = [];
    }
    // Compare message UTC activity timestamps with the prior successful baseline.
    function detectNewMessages(items, doneThreadState) {
        if (!notificationsEnabled || baselineUpdatedAtMs <= 0)
            return [];

        let candidates = messageState.filterDoneMessages(items || [], doneThreadState || ({}));
        let result = [];
        for (let index = 0; index < candidates.length; index++) {
            let message = candidates[index];
            if (message && message.threadId && message.unread && messageState.messageUpdatedAtMs(message) > baselineUpdatedAtMs)
                result.push(message);
        }
        return result;
    }
    // Wait until visible message updates settle before dispatching the pending notification batch.
    function flushIfReady(popoutVisible, viewApplyRunning, pendingViewCount) {
        if (pendingMessages.length === 0 || (popoutVisible && (viewApplyRunning || pendingViewCount > 0)))
            return false;
        let messages = pendingMessages;
        clearPending();
        sendMessageNotification(messages);
        return true;
    }
    // Use detailed titles for small batches and a generic summary for larger batches.
    function messageNotificationCommand(messages) {
        let items = messages || [];
        if (items.length === 0)
            return [];

        let body = "";
        if (items.length <= GitHubConstants.notificationDetailedMessageLimit) {
            let parts = [];
            for (let index = 0; index < items.length; index++) {
                let title = String(items[index].title || "").split("\n")[0].trim();
                let repository = String(items[index].repository || "").trim();
                let detail = title || "New message";
                if (repository)
                    detail += "\n" + repository;
                parts.push(detail);
            }
            body = parts.join("\n\n");
        } else {
            let repositories = [];
            let seenRepositories = {};
            for (let index = 0; index < items.length; index++) {
                let repository = String(items[index].repository || "").trim();
                if (!repository || seenRepositories[repository])
                    continue;
                seenRepositories[repository] = true;
                repositories.push(repository);
            }
            body = "New GitHub messages";
            if (repositories.length > 0)
                body += "\n" + repositories.join(", ");
        }

        let summary = items.length === 1 ? "New GitHub Message" : items.length + " New GitHub Messages";
        let command = ["dms", "notify", "-a", GitHubConstants.notificationAppName, "-t", String(GitHubConstants.notificationExpireMs)];
        let iconPath = resolveIcon(items);
        if (iconPath)
            command.push("-i", iconPath);
        command.push("--", summary, body);
        return command;
    }
    // Throttle all error texts from this source with one cooldown; manual failures stay inline.
    function notifyFetchError(message, wasManual) {
        if (wasManual)
            return false;
        let text = String(message || "GitHub refresh failed.").trim();
        if (!text)
            return false;
        let now = Date.now();
        if (errorNotificationAt > 0 && now - errorNotificationAt < GitHubConstants.errorNotificationRepeatMs)
            return false;
        errorNotificationText = text;
        errorNotificationAt = now;
        notifyProcessDef.createObject(service, {
            command: ["dms", "notify", "-a", GitHubConstants.notificationAppName, "-u", "normal", "-t", String(GitHubConstants.notificationExpireMs), "--", "GitHub Inbox refresh failed", text],
            running: true
        });
        return true;
    }
    // Keep the latest nonempty message batch pending until notification delivery.
    function queue(messages) {
        if (messages && messages.length > 0)
            pendingMessages = messages;
    }
    // Clear the activity baseline, error-notification cooldown and pending notification batch.
    function reset() {
        baselineUpdatedAtMs = 0;
        errorNotificationAt = 0;
        errorNotificationText = "";
        clearPending();
    }
    // Prefer a cached repository avatar and fall back to the local plugin icon.
    function resolveIcon(messages) {
        if (messages.length > 0) {
            let firstOwnerLogin = String(messages[0].repositoryOwnerLogin || "").trim();
            if (firstOwnerLogin) {
                let singleOwner = true;
                for (let index = 1; index < messages.length; index++) {
                    if (String(messages[index].repositoryOwnerLogin || "").trim() !== firstOwnerLogin) {
                        singleOwner = false;
                        break;
                    }
                }
                if (singleOwner) {
                    let avatarUrl = String(messages[0].repositoryOwnerAvatarUrl || "");
                    if (avatarUrl.indexOf("file://") !== 0)
                        avatarUrl = cacheCoordinator.cachedLocalAvatarUrl(firstOwnerLogin);
                    if (avatarUrl.indexOf("file://") === 0)
                        return avatarUrl.substring(7);
                }
            }
        }

        let fallback = String(fallbackIcon || "");
        return fallback.indexOf("file://") === 0 ? fallback.substring(7) : "";
    }
    // Dispatch a prepared notification with separate process arguments.
    function sendMessageNotification(messages) {
        let command = messageNotificationCommand(messages);
        if (command.length > 0)
            notifyProcessDef.createObject(service, {
                command: command,
                running: true
            });
    }
    // Track newest message activity rather than the time its response was received.
    function setBaseline(items) {
        baselineUpdatedAtMs = messageState.latestMessageUpdatedAtMs(items || []);
    }

    Component {
        id: notifyProcessDef

        Process {
            onExited: destroy()
        }
    }
}
