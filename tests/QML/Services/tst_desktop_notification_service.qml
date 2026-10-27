// tst_desktop_notification_service.qml - verifies source-wide error notification throttling.

import QtQuick
import QtTest
import "../../../src/QML/Services"
import "../../../src/QML/Tools"

TestCase {
    function init() {
        notifications.reset();
    }
    function test_alternatingErrorsShareTheCooldown() {
        verify(notifications.notifyFetchError("First error", false));
        verify(!notifications.notifyFetchError("Different error", false));
        compare(notifications.errorNotificationText, "First error");
        notifications.errorNotificationAt = Date.now() - Constants.errorNotificationRepeatMs - 1;
        verify(notifications.notifyFetchError("Different error", false));
    }
    function test_manualErrorsDoNotConsumeCooldown() {
        verify(!notifications.notifyFetchError("Manual error", true));
        compare(notifications.errorNotificationAt, 0);
    }
    // Use the built-in CLI with argument separation, preserving icons, expiry and literal titles.
    function test_notificationCommandUsesDux() {
        notifications.fallbackIcon = "file:///tmp/plugin icon.png";
        let command = notifications.messageNotificationCommand([
            {
                title: "--help\nignored",
                repository: "owner/repo"
            }
        ]);
        compare(command.slice(0, 2), ["dms", "notify"]);
        verify(command.indexOf("notify-send") < 0);
        compare(command[command.indexOf("-a") + 1], Constants.notificationAppName);
        compare(command[command.indexOf("-t") + 1], String(Constants.notificationExpireMs));
        compare(command[command.indexOf("-i") + 1], "/tmp/plugin icon.png");
        compare(command.slice(-3), ["--", "New GitHub Message", "--help\nowner/repo"]);
        compare(notifications.messageNotificationCommand([]), []);
    }

    name: "DesktopNotificationService"

    DesktopNotificationService {
        id: notifications
    }
}
