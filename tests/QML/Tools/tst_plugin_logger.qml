// tst_plugin_logger.qml - verifies logging follows configured development flags.

import QtQuick
import QtTest
import "../../../src/QML/Tools"

TestCase {
    id: testCase

    property var capturedLogs: []

    function cleanup() {
        PluginLogger.output = console;
    }
    function init() {
        capturedLogs = [];
        PluginLogger.output = ({
                warn: function (message) {
                    testCase.capturedLogs.push(message);
                },
                error: function (message) {
                    testCase.capturedLogs.push(message);
                }
            });
    }
    function test_logLevelsFollowConfiguredFlags() {
        PluginLogger.debug("test", "debug");
        PluginLogger.profile("test", "operation", 100, "details");
        PluginLogger.error("test", "failure");

        let expected = 0;
        if (Constants.loggingEnabled) {
            expected++;
            if (Constants.debugPerformanceLogging || Constants.profileLoggingEnabled)
                expected++;
            if (Constants.profileLoggingEnabled && (Constants.profileLogAllOperations || 100 >= Constants.profileSlowOperationThresholdMs))
                expected++;
        }
        compare(capturedLogs.length, expected);
    }

    name: "PluginLogger"
}
