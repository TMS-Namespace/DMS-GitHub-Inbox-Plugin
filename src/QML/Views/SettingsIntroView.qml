// SettingsIntroView.qml - settings page title and token-scope guidance.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    spacing: Theme.spacingS
    width: parent.width

    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        text: "GitHub Inbox"
    }
    StyledText {
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        text: "Use a GitHub classic personal access token with at least the 'notifications' scope."
        width: parent.width
        wrapMode: Text.WordWrap
    }
}
