// PluginLogger.qml - centralizes plugin diagnostics and development logging.

pragma Singleton

import QtQuick
import ".."

QtObject {
    property var output: console

    // Emit diagnostic decisions only through the central development-mode gate.
    function debug(scope, text) {
        if (!GitHubConstants.loggingEnabled || (!GitHubConstants.debugPerformanceLogging && !GitHubConstants.profileLoggingEnabled))
            return;
        output.warn("[GitHubInbox] " + scope + ": " + text);
    }
    // Route failures through the single logging gate without exposing credentials.
    function error(scope, text) {
        if (!GitHubConstants.loggingEnabled)
            return;
        output.error("[GitHubInbox] " + scope + ": " + text);
    }
    // Record elapsed work only when profiling is enabled and the threshold is met.
    function profile(scope, operation, durationMs, details) {
        if (!GitHubConstants.loggingEnabled || !GitHubConstants.profileLoggingEnabled || (!GitHubConstants.profileLogAllOperations && durationMs < GitHubConstants.profileSlowOperationThresholdMs))
            return;
        let suffix = details ? (" - " + details) : "";
        output.warn("[GitHubInbox] " + scope + "." + operation + " took " + durationMs + "ms" + suffix);
    }
}
