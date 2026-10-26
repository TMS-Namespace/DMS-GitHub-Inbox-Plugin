// SettingsIntroView.qml - settings page title above the grouped controls.

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
}
