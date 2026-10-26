// SettingsContentView.qml - composes the settings sections and persistence controls.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."
import qs.Common
import qs.DCommon.Widgets

Column {
    id: content

    property bool saveFailed: false
    property var tokenEditedCallback: null
    property string tokenStatusMessage: ""
    property string tokenValue: ""

    signal clearCacheRequested

    // Refresh displayed host controls after the settings service is attached.
    function loadSettings() {
        for (let child of children)
            if (child.loadValue)
                child.loadValue();
    }

    spacing: Theme.spacingM
    width: parent.width

    SettingsIntroView {
    }
    DCollapsibleSection {
        description: "Use a GitHub classic personal access token with at least the 'notifications' scope."
        objectName: "authenticationSettingsSection"
        title: "Authentication"
        width: parent.width

        GitHubTokenSetting {
            Layout.fillWidth: true
            saveFailed: content.saveFailed
            statusMessage: content.tokenStatusMessage
            tokenValue: content.tokenValue

            onTokenEdited: function (value) {
                if (content.tokenEditedCallback)
                    content.tokenEditedCallback(value);
            }
            onTokenHelpRequested: Qt.openUrlExternally(GitHubConstants.githubTokenSettingsUrl)
        }
    }
    SettingsPreferencesView {
    }
    SettingsCacheView {
        onClearCacheRequested: content.clearCacheRequested()
    }
    SettingsApiStatsView {
    }
}
