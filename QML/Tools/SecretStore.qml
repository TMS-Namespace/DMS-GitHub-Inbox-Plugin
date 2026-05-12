// SecretStore.qml - GitHub token storage via Freedesktop Secret Service.

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: store
    visible: false

    property var pluginService: null
    property string pluginId: GitHubConstants.pluginNamespaceId
    property string legacyPlainTextToken: ""

    property string token: ""
    property bool isLoading: false
    property bool isStoring: false
    property bool secretToolAvailable: false
    property string statusMessage: ""

    readonly property string storageModeKey: "githubTokenStorage"
    readonly property string secretStorageMode: "secret-service"

    property string _pendingStoreToken: ""
    property bool _pendingStoreIsMigration: false

    signal tokenLoaded(string token)
    signal tokenStored(bool success, string message)
    signal tokenCleared(bool success, string message)

    Component.onCompleted: loadToken()

    Connections {
        target: store.pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === store.pluginId && !store.isStoring)
                store.loadToken()
        }
    }

    onPluginServiceChanged: {
        if (pluginService && token && legacyPlainTextToken)
            _markSecretStorage()
    }

    onLegacyPlainTextTokenChanged: {
        if (legacyPlainTextToken && !token)
            loadToken()
    }

    function loadToken() {
        if (isLoading)
            return

        var legacy = String(legacyPlainTextToken || "").trim()
        if (legacy) {
            token = legacy
            statusMessage = "Migrating token to Secret Service."
            tokenLoaded(token)
            storeToken(legacy, true)
            return
        }

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

    function storeToken(value, isMigration) {
        var trimmed = String(value || "").trim()
        if (!trimmed) {
            clearToken()
            return
        }

        _pendingStoreToken = trimmed
        _pendingStoreIsMigration = !!isMigration
        _startStore()
    }

    function clearToken() {
        token = ""
        _pendingStoreToken = ""
        _pendingStoreIsMigration = false
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

        isStoring = true
        var proc = storeComponent.createObject(store, {
            storedToken: _pendingStoreToken,
            isMigration: _pendingStoreIsMigration
        })
        proc.command = [
            "secret-tool", "store",
            "--label=DMS GitHub Inbox Token",
            "app", "dms-github-inbox-plugin",
            "key", "github-token"
        ]
        proc.running = true
    }

    function _onStoreFinished(success, storedToken, isMigration, details) {
        var queuedToken = _pendingStoreToken
        var queuedIsMigration = _pendingStoreIsMigration
        isStoring = false

        if (success) {
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
            _pendingStoreIsMigration = queuedIsMigration
            Qt.callLater(_startStore)
        } else {
            _pendingStoreToken = ""
            _pendingStoreIsMigration = false
        }
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
                store.secretToolAvailable = exitCode === 0 || proc.errorOutput.indexOf("not found") < 0
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
            property bool isMigration: false
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
                store._onStoreFinished(exitCode === 0, proc.storedToken, proc.isMigration, details)
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
