// SettingsService.qml - dependency validation and GitHub token persistence.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: service

    property bool _tokenEdited: false
    property bool _tokenEditing: false
    property bool dependenciesChecked: false
    readonly property bool dependenciesReady: dependenciesChecked && missingDependencies.length === 0
    property string displayedTokenValidationError: ""
    property var missingDependencies: []
    property var pluginService: null
    readonly property var providerApi: GitHubManager.getProviderApi("github")
    property bool tokenSaveFailed: false
    property string tokenStatusMessage: ""
    readonly property string tokenValidationError: providerApi ? providerApi.validateTokenFormat(tokenValue) : "Token validation is unavailable. Reload the plugin."
    property string tokenValue: ""

    // Probe required commands before the settings controls are enabled.
    function checkDependencies() {
        if (dependencyCheck.running)
            return;
        dependencyCheck.output = "";
        dependencyCheck.command = ["bash", "-c", "for dependency in \"$@\"; do command -v \"$dependency\" >/dev/null 2>&1 || printf '%s\\n' \"$dependency\"; done", "github-inbox-dependencies"].concat(GitHubConstants.requiredCommands);
        dependencyCheck.running = true;
    }
    // Ignore focus changes without edits and duplicate completion signals from the native field.
    function finishTokenEdit(value) {
        if (_tokenEditing)
            persistToken(value);
    }
    // Start at most one keyring lookup and deliver its result through the service signals.
    function loadToken() {
        secretStore.loadToken();
    }
    // Commit the draft only after editing finishes; empty input requests keyring removal.
    function persistToken(value) {
        _tokenEdited = true;
        _tokenEditing = false;
        let trimmed = String(value || "").trim();
        tokenValue = trimmed;
        displayedTokenValidationError = tokenValidationError;
        tokenSaveFailed = false;
        tokenStatusMessage = "";
        if (tokenValidationError)
            return;
        if (trimmed)
            secretStore.storeToken(trimmed);
        else
            secretStore.clearToken();
    }
    // Validate every edit without normalizing the draft or writing it to the keyring.
    function updateTokenDraft(value) {
        _tokenEdited = true;
        _tokenEditing = true;
        tokenValue = value;
        displayedTokenValidationError = tokenValidationError;
        tokenSaveFailed = false;
        tokenStatusMessage = "";
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

        objectName: "settingsSecretStore"
        pluginService: service.pluginService

        onTokenCleared: function (success, message) {
            if (service._tokenEditing)
                return;
            service.tokenSaveFailed = !success;
            service.tokenStatusMessage = message;
        }
        onTokenLoaded: function (token) {
            if (service._tokenEdited)
                return;
            service.tokenValue = token || "";
            service.tokenSaveFailed = false;
            if (!token && statusMessage)
                service.tokenStatusMessage = statusMessage;
        }
        onTokenStored: function (success, message) {
            if (service._tokenEditing || (success && token !== service.tokenValue))
                return;
            service.tokenSaveFailed = !success;
            service.tokenStatusMessage = message;
        }
    }
}
