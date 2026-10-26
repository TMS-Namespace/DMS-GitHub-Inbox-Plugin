// ErrorService.qml - stores one widget's current user-facing error.

import QtQuick
import "../../JS/Contracts/PluginError.js" as PluginError
import ".."

QtObject {
    id: service

    property var currentError: null
    property var logger: PluginLogger
    property string userMessage: ""

    // Remove the current error after the owning workflow succeeds.
    function clear() {
        currentError = null;
        userMessage = "";
    }
    // Keep the safe message in observable state and send diagnostics only to the logger.
    function report(scope, userMessage, details, retryable) {
        currentError = PluginError.create(userMessage, details, retryable);
        service.userMessage = currentError.userMessage;
        logger.error(scope, details || currentError.userMessage);
        return service.userMessage;
    }
}
