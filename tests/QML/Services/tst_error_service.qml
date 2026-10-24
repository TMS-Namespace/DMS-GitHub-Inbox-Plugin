// tst_error_service.qml - verifies per-widget error reporting state.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    function test_reportAndClearError() {
        compare(service.userMessage, "");
        compare(service.report("test", "Friendly message", "diagnostic", true), "Friendly message");
        compare(service.userMessage, "Friendly message");
        compare(service.currentError.name, "PluginError");
        compare(service.currentError.details, "diagnostic");
        compare(service.currentError.retryable, true);
        service.clear();
        compare(service.userMessage, "");
        compare(service.currentError, null);
    }

    name: "ErrorService"

    ErrorService {
        id: service

        logger: QtObject {
            function error(scope, text) {
            }
        }
    }
}
