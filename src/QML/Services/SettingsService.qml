// SettingsService.qml - dependency validation and GitHub token persistence.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: service

    property bool dependenciesChecked: false
    readonly property bool dependenciesReady: dependenciesChecked && missingDependencies.length === 0
    property var missingDependencies: []
    property var pluginService: null
    property bool tokenSaveFailed: false
    property string tokenStatusMessage: ""
    property string tokenValue: ""

    // Probe required commands before the settings controls are enabled.
    function checkDependencies() {
        if (dependencyCheck.running)
            return;
        dependencyCheck.output = "";
        dependencyCheck.command = ["bash", "-c", "for dependency in \"$@\"; do command -v \"$dependency\" >/dev/null 2>&1 || printf '%s\\n' \"$dependency\"; done", "github-inbox-dependencies"].concat(GitHubConstants.requiredCommands);
        dependencyCheck.running = true;
    }
    // Start at most one keyring lookup and deliver its result through the service signals.
    function loadToken() {
        secretStore.loadToken();
    }
    // Translate an empty settings value into removal and retain a visible save status.
    function persistToken(value) {
        let trimmed = String(value || "").trim();
        tokenValue = trimmed;
        tokenSaveFailed = false;
        tokenStatusMessage = trimmed ? "Saving token to Secret Service..." : "Removing token from Secret Service...";
        if (trimmed)
            secretStore.storeToken(trimmed);
        else
            secretStore.clearToken();
    }
    // Debounce text edits so intermediate keystrokes do not each write to the keyring.
    function scheduleTokenSave(value) {
        tokenValue = value;
        tokenSaveTimer.restart();
    }

    Process {
        id: dependencyCheck

        property string output: ""

        stdout: SplitParser {
            onRead: line => dependencyCheck.output += line + "\n"
        }

        onExited: exitCode => {
            service.missingDependencies = exitCode === 0 ? dependencyCheck.output.split("\n").filter(name => name.length > 0) : GitHubConstants.requiredCommands;
            service.dependenciesChecked = true;
            dependencyCheck.output = "";
        }
    }
    SecretStore {
        id: secretStore

        pluginService: service.pluginService

        onTokenCleared: function (success, message) {
            service.tokenSaveFailed = !success;
            service.tokenStatusMessage = message;
        }
        onTokenLoaded: function (token) {
            service.tokenValue = token || "";
            service.tokenSaveFailed = false;
            if (!token && statusMessage)
                service.tokenStatusMessage = statusMessage;
        }
        onTokenStored: function (success, message) {
            service.tokenSaveFailed = !success;
            service.tokenStatusMessage = message;
        }
    }
    Timer {
        id: tokenSaveTimer

        interval: GitHubConstants.tokenSaveDelayMs
        repeat: false

        onTriggered: service.persistToken(service.tokenValue)
    }
}
