// SecretStore.qml - GitHub token storage via Freedesktop Secret Service.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: store

    property string _pendingStoreToken: ""
    property bool autoLoad: true
    property bool fatalOnUnavailable: false
    property bool isLoading: false
    property bool isStoring: false
    property string pluginId: GitHubConstants.pluginNamespaceId
    property var pluginService: null
    readonly property string secretStorageMode: "secret-service"
    property bool secretStorageUnavailable: secretToolChecked && !secretToolAvailable
    property bool secretToolAvailable: false
    property bool secretToolChecked: false
    property var secretToolCommand: ["secret-tool"]
    property string statusMessage: ""
    readonly property string storageModeKey: "githubTokenStorage"
    property string token: ""

    signal activationRefused(string message)
    signal tokenCleared(bool success, string message)
    signal tokenLoaded(string token)
    signal tokenStored(bool success, string message)

    // Distinguish unavailable keyring infrastructure from an ordinary missing item.
    function _isSecretToolMissing(exitCode, stderrText) {
        let text = String(stderrText || "").toLowerCase();
        return exitCode === 127 || text.indexOf("not found") >= 0 || text.indexOf("no such file") >= 0 || text.indexOf("executable file not found") >= 0 || text.indexOf("org.freedesktop.secrets") >= 0 || text.indexOf("cannot autolaunch") >= 0 || text.indexOf("could not connect") >= 0;
    }
    // Remove legacy plaintext metadata after Secret Service confirms persistence.
    function _markSecretStorage() {
        if (!pluginService)
            return;
        pluginService.savePluginData(pluginId, "githubToken", "");
        pluginService.savePluginData(pluginId, storageModeKey, secretStorageMode);
    }
    // Confirm completed storage before publishing the token or starting a queued replacement.
    function _onStoreFinished(success, storedToken, details) {
        let queuedToken = _pendingStoreToken;
        isStoring = false;

        if (success) {
            secretToolChecked = true;
            secretToolAvailable = true;
            token = storedToken;
            statusMessage = "Token saved to Secret Service.";
            _markSecretStorage();
            tokenStored(true, statusMessage);
        } else {
            statusMessage = "Failed to save token to Secret Service.";
            PluginLogger.error("SecretStore.store", details || statusMessage);
            tokenStored(false, statusMessage);
        }

        if (queuedToken && queuedToken !== storedToken) {
            _pendingStoreToken = queuedToken;
            Qt.callLater(_startStore);
        } else {
            _pendingStoreToken = "";
        }
    }
    // Report unavailable secure storage to owners that require it for activation.
    function _refuseActivationIfFatal() {
        if (fatalOnUnavailable)
            activationRefused(statusMessage || "Secret Service is unavailable.");
    }
    // Explain keyring setup without presenting a failed request as success.
    function _secretUnavailableMessage(details) {
        if (details)
            PluginLogger.error("SecretStore.availability", details);
        return "Secret Service is unavailable. Install libsecret's secret-tool and unlock a keyring before using this plugin.";
    }
    // Write the latest queued token through stdin only when no store operation is active.
    function _startStore() {
        if (isStoring || !_pendingStoreToken)
            return;
        if (secretToolChecked && !secretToolAvailable) {
            _onStoreFinished(false, _pendingStoreToken, "Secret Service is unavailable. Install libsecret's secret-tool and unlock a keyring before saving a token.");
            return;
        }

        isStoring = true;
        storeComponent.createObject(store, {
            storedToken: _pendingStoreToken,
            command: secretToolCommand.concat(["store", "--label=DMS GitHub Inbox Token", "app", "dms-github-inbox-plugin", "key", "github-token"]),
            running: true
        });
    }
    // Request keyring removal and wait for confirmation before clearing confirmed token state.
    function clearToken() {
        _pendingStoreToken = "";

        clearComponent.createObject(store, {
            command: secretToolCommand.concat(["clear", "app", "dms-github-inbox-plugin", "key", "github-token"]),
            running: true
        });
    }
    // Confirm removal only after Secret Service has returned its result.
    function finishClear(exitCode, details) {
        let success = exitCode === 0;
        if (success) {
            token = "";
            _markSecretStorage();
        }
        statusMessage = success ? "Token removed from Secret Service." : "Failed to remove token from Secret Service.";
        if (!success)
            PluginLogger.error("SecretStore.clear", details || statusMessage);
        tokenCleared(success, statusMessage);
    }
    // Start at most one keyring lookup and deliver its result through the service signals.
    function loadToken() {
        if (isLoading)
            return;
        isLoading = true;
        statusMessage = "";
        lookupComponent.createObject(store, {
            command: secretToolCommand.concat(["lookup", "app", "dms-github-inbox-plugin", "key", "github-token"]),
            running: true
        });
    }
    // Coalesce edits while a keyring write is active; never place the token in command arguments.
    function storeToken(value) {
        let trimmed = String(value || "").trim();
        if (!trimmed) {
            clearToken();
            return;
        }

        if (secretToolChecked && !secretToolAvailable) {
            token = "";
            statusMessage = "Secret Service is unavailable. Install libsecret's secret-tool and unlock a keyring before saving a token.";
            tokenStored(false, statusMessage);
            return;
        }

        _pendingStoreToken = trimmed;
        _startStore();
    }

    visible: false

    Component.onCompleted: {
        if (autoLoad)
            loadToken();
    }

    Connections {
        // Reload the keyring token after this plugin's settings change, unless a store is active.
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === store.pluginId && !store.isStoring)
                store.loadToken();
        }

        target: store.pluginService
    }
    Component {
        id: lookupComponent

        Process {
            id: proc

            property string errorOutput: ""
            property string output: ""

            stderr: StdioCollector {
                onStreamFinished: proc.errorOutput = text
            }
            stdout: StdioCollector {
                onStreamFinished: proc.output = text
            }

            onExited: function (exitCode) {
                store.isLoading = false;
                store.secretToolChecked = true;
                store.secretToolAvailable = !store._isSecretToolMissing(exitCode, proc.errorOutput);

                if (!store.secretToolAvailable) {
                    store.token = "";
                    store.statusMessage = store._secretUnavailableMessage(proc.errorOutput.trim());
                    store.tokenLoaded("");
                    store._refuseActivationIfFatal();
                    destroy();
                    return;
                }

                if (exitCode === 0) {
                    store.token = (proc.output || "").trim();
                    store.statusMessage = store.token ? "" : "No GitHub token stored.";
                } else {
                    store.token = "";
                    store.statusMessage = proc.errorOutput.trim() ? "Failed to read token from Secret Service." : "No GitHub token stored.";
                    if (proc.errorOutput.trim())
                        PluginLogger.error("SecretStore.lookup", proc.errorOutput.trim());
                }
                store.tokenLoaded(store.token);
                destroy();
            }
        }
    }
    Component {
        id: storeComponent

        Process {
            id: proc

            property string errorOutput: ""
            property string storedToken: ""

            stdinEnabled: true

            stderr: StdioCollector {
                onStreamFinished: proc.errorOutput = text
            }

            onExited: function (exitCode) {
                let details = proc.errorOutput.trim();
                if (store._isSecretToolMissing(exitCode, details)) {
                    store.secretToolChecked = true;
                    store.secretToolAvailable = false;
                    details = store._secretUnavailableMessage(details);
                }
                store._onStoreFinished(exitCode === 0, proc.storedToken, details);
                destroy();
            }
            onStarted: {
                proc.write(proc.storedToken + "\n");
                proc.stdinEnabled = false;
            }
        }
    }
    Component {
        id: clearComponent

        Process {
            id: proc

            property string errorOutput: ""

            stderr: StdioCollector {
                onStreamFinished: proc.errorOutput = text
            }

            onExited: function (exitCode) {
                store.finishClear(exitCode, proc.errorOutput.trim());
                destroy();
            }
        }
    }
}
