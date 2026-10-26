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

    name: "DesktopNotificationService"

    DesktopNotificationService {
        id: notifications
    }
}
