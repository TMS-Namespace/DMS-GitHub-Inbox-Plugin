// SettingsContentView.qml - composes the settings sections and persistence controls.

pragma ComponentBehavior: Bound

import QtQuick
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
    GitHubTokenSetting {
        saveFailed: content.saveFailed
        statusMessage: content.tokenStatusMessage
        tokenValue: content.tokenValue

        onTokenEdited: function (value) {
            if (content.tokenEditedCallback)
                content.tokenEditedCallback(value);
        }
        onTokenHelpRequested: Qt.openUrlExternally(GitHubConstants.githubTokenSettingsUrl)
    }
    SettingsPreferencesView {
    }
    SettingsCacheView {
        onClearCacheRequested: content.clearCacheRequested()
    }
    SettingsApiStatsView {
    }
}
