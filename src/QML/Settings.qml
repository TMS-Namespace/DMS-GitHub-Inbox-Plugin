// Settings.qml - Settings page for GitHub Inbox plugin

pragma ComponentBehavior: Bound

import QtQuick
import "."
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    property alias dependenciesChecked: settingsService.dependenciesChecked
    property alias dependenciesReady: settingsService.dependenciesReady
    property alias missingDependencies: settingsService.missingDependencies
    property alias tokenSaveFailed: settingsService.tokenSaveFailed
    property alias tokenStatusMessage: settingsService.tokenStatusMessage
    property alias tokenValue: settingsService.tokenValue

    pluginId: GitHubConstants.pluginNamespaceId

    Component.onCompleted: {
        settingsService.loadToken();
        if (pluginService)
            settingsContent.loadSettings();
        settingsService.checkDependencies();
    }
    onPluginServiceChanged: {
        if (pluginService) {
            settingsService.loadToken();
            settingsContent.loadSettings();
        }
    }

    SettingsService {
        id: settingsService

        pluginService: root.pluginService
    }
    StyledText {
        color: Theme.error
        font.pixelSize: Theme.fontSizeMedium
        objectName: "dependencyStatus"
        text: root.dependenciesChecked ? "Missing required commands: " + root.missingDependencies.join(", ") + ". GitHub Inbox cannot work until they are installed." : "Checking required commands..."
        visible: !root.dependenciesReady
        width: parent.width
        wrapMode: Text.WordWrap
    }
    SettingsContentView {
        id: settingsContent

        height: visible ? implicitHeight : 0
        saveFailed: root.tokenSaveFailed
        tokenEditedCallback: function (value) {
            settingsService.scheduleTokenSave(value);
        }
        tokenStatusMessage: root.tokenStatusMessage
        tokenValue: root.tokenValue
        visible: root.dependenciesReady
        width: parent.width

        onClearCacheRequested: root.saveValue("clearCacheRequested", "true")
    }
}
