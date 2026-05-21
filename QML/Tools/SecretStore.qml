// SecretStore.qml - GitHub token storage via Freedesktop Secret Service.

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: store
    visible: false

    property var pluginService: null
    property string pluginId: GitHubConstants.pluginNamespaceId
    property bool fatalOnUnavailable: false

    property string token: ""
    property bool isLoading: false
    property bool isStoring: false
    property bool secretToolAvailable: false
    property bool secretToolChecked: false
    property bool secretStorageUnavailable: secretToolChecked && !secretToolAvailable
    property string statusMessage: ""

    readonly property string storageModeKey: "githubTokenStorage"
    readonly property string secretStorageMode: "secret-service"

    property string _pendingStoreToken: ""

    signal tokenLoaded(string token)
    signal tokenStored(bool success, string message)
    signal tokenCleared(bool success, string message)
    signal activationRefused(string message)

    Component.onCompleted: loadToken()

    Connections {
        target: store.pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === store.pluginId && !store.isStoring)
                store.loadToken()
        }
    }

    function loadToken() {
        if (isLoading)
            return

        isLoading = true
        statusMessage = ""
        var proc = lookupComponent.createObject(store)
        proc.command = [
            "secret-tool", "lookup",
            "app", "dms-github-inbox-plugin",
            "key", "github-token"
        ]
        proc.running = true
    }

    function storeToken(value) {
        var trimmed = String(value || "").trim()
        if (!trimmed) {
            clearToken()
            return
        }

        if (secretToolChecked && !secretToolAvailable) {
            token = ""
            statusMessage = "Secret Service is unavailable. Install libsecret's secret-tool and unlock a keyring before saving a token."
            tokenStored(false, statusMessage)
            return
        }

        _pendingStoreToken = trimmed
        _startStore()
    }

    function clearToken() {
        token = ""
        _pendingStoreToken = ""
        if (pluginService) {
            _markSecretStorage()
        }

        var proc = clearComponent.createObject(store)
        proc.command = [
            "secret-tool", "clear",
            "app", "dms-github-inbox-plugin",
            "key", "github-token"
        ]
        proc.running = true
    }

    function _startStore() {
        if (isStoring || !_pendingStoreToken)
            return

        if (secretToolChecked && !secretToolAvailable) {
            _onStoreFinished(false, _pendingStoreToken,
                             "Secret Service is unavailable. Install libsecret's secret-tool and unlock a keyring before saving a token.")
            return
        }

        isStoring = true
        var proc = storeComponent.createObject(store, {
            storedToken: _pendingStoreToken
        })
        proc.command = [
            "secret-tool", "store",
            "--label=DMS GitHub Inbox Token",
            "app", "dms-github-inbox-plugin",
            "key", "github-token"
        ]
        proc.running = true
    }

    function _onStoreFinished(success, storedToken, details) {
        var queuedToken = _pendingStoreToken
        isStoring = false

        if (success) {
            secretToolChecked = true
            secretToolAvailable = true
            token = storedToken
            statusMessage = "Token saved to Secret Service."
            _markSecretStorage()
            tokenStored(true, statusMessage)
        } else {
            statusMessage = details || "Failed to save token to Secret Service."
            tokenStored(false, statusMessage)
        }

        if (queuedToken && queuedToken !== storedToken) {
            _pendingStoreToken = queuedToken
            Qt.callLater(_startStore)
        } else {
            _pendingStoreToken = ""
        }
    }

    function _isSecretToolMissing(exitCode, stderrText) {
        var text = String(stderrText || "").toLowerCase()
        return exitCode === 127
               || text.indexOf("not found") >= 0
               || text.indexOf("no such file") >= 0
               || text.indexOf("executable file not found") >= 0
               || text.indexOf("org.freedesktop.secrets") >= 0
               || text.indexOf("cannot autolaunch") >= 0
               || text.indexOf("could not connect") >= 0
    }

    function _secretUnavailableMessage(details) {
        var suffix = details ? (" " + details) : ""
        return "Secret Service is unavailable. Install libsecret's secret-tool and unlock a keyring before using this plugin." + suffix
    }

    function _refuseActivationIfFatal() {
        if (fatalOnUnavailable)
            activationRefused(statusMessage || "Secret Service is unavailable.")
    }

    function _markSecretStorage() {
        if (!pluginService)
            return
        pluginService.savePluginData(pluginId, "githubToken", "")
        pluginService.savePluginData(pluginId, storageModeKey, secretStorageMode)
    }

    Component {
        id: lookupComponent

        Process {
            id: proc
            property string output: ""
            property string errorOutput: ""

            stdout: StdioCollector {
                onStreamFinished: proc.output = text
            }

            stderr: StdioCollector {
                onStreamFinished: proc.errorOutput = text
            }

            onExited: function(exitCode) {
                store.isLoading = false
                store.secretToolChecked = true
                store.secretToolAvailable = !store._isSecretToolMissing(exitCode, proc.errorOutput)

                if (!store.secretToolAvailable) {
                    store.token = ""
                    store.statusMessage = store._secretUnavailableMessage(proc.errorOutput.trim())
                    store.tokenLoaded("")
                    store._refuseActivationIfFatal()
                    destroy()
                    return
                }

                if (exitCode === 0) {
                    store.token = (proc.output || "").trim()
                    store.statusMessage = store.token ? "" : "No GitHub token stored."
                } else {
                    store.token = ""
                    store.statusMessage = proc.errorOutput.trim() || "No GitHub token stored."
                }
                store.tokenLoaded(store.token)
                destroy()
            }
        }
    }

    Component {
        id: storeComponent

        Process {
            id: proc
            property string storedToken: ""
            property string errorOutput: ""
            stdinEnabled: true

            stderr: StdioCollector {
                onStreamFinished: proc.errorOutput = text
            }

            onStarted: {
                proc.write(proc.storedToken + "\n")
                proc.stdinEnabled = false
            }

            onExited: function(exitCode) {
                var details = proc.errorOutput.trim()
                if (store._isSecretToolMissing(exitCode, details)) {
                    store.secretToolChecked = true
                    store.secretToolAvailable = false
                    details = store._secretUnavailableMessage(details)
                }
                store._onStoreFinished(exitCode === 0, proc.storedToken, details)
                destroy()
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

            onExited: function(exitCode) {
                var success = true
                var message = "Token removed from Secret Service."
                store.statusMessage = message
                store.tokenCleared(success, message)
                destroy()
            }
        }
    }
}
