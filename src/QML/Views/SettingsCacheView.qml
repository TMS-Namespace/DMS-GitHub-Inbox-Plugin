// SettingsCacheView.qml - local cache description and clear-cache command.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: cacheView

    signal clearCacheRequested

    spacing: Theme.spacingS
    width: parent.width

    Rectangle {
        color: Theme.outlineVariant
        height: 1
        width: parent.width
    }
    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        text: "Cache"
    }
    StyledText {
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        text: "Inbox messages, author details, and avatars are cached locally for faster loading."
        width: parent.width
        wrapMode: Text.WordWrap
    }
    Rectangle {
        border.color: clearCacheArea.containsMouse ? Theme.error : Theme.outlineVariant
        border.width: 1
        color: clearCacheArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12) : Theme.surfaceContainerHigh
        height: clearCacheLabel.height + Theme.spacingS
        radius: Theme.cornerRadius
        width: clearCacheLabel.width + Theme.spacingM * 2

        StyledText {
            id: clearCacheLabel

            anchors.centerIn: parent
            color: clearCacheArea.containsMouse ? Theme.error : Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            text: "Clear Cache"
        }
        MouseArea {
            id: clearCacheArea

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            onClicked: cacheView.clearCacheRequested()
        }
    }
}
