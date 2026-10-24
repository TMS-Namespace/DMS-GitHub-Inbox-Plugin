// InboxBarPill.qml - unread-count pill for horizontal or vertical bars.

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common
import qs.DCommon.Widgets

Item {
    id: pill

    property string countText: ""
    property url githubIconFallback
    property url githubIconPrimary
    property int iconSize: 24
    property int textSize: Theme.fontSizeSmall
    property bool tokenConfigured: false
    property int unreadCount: 0
    property bool vertical: false

    implicitHeight: !tokenConfigured ? 0 : (vertical ? pillColumn.implicitHeight : pillRow.implicitHeight)
    implicitWidth: !tokenConfigured ? 0 : (vertical ? pillColumn.implicitWidth : pillRow.implicitWidth)
    visible: tokenConfigured

    Row {
        id: pillRow

        spacing: Theme.spacingXS
        visible: !pill.vertical

        GitHubIcon {
            followThemeColor: true
            iconColor: Theme.surfaceText
            iconOpacity: GitHubConstants.githubIconBarOpacity
            size: pill.iconSize
            sourceFallback: pill.githubIconFallback
            sourcePrimary: pill.githubIconPrimary
        }
        StyledText {
            color: Theme.surfaceText
            font.pixelSize: pill.textSize
            font.weight: Font.Medium
            objectName: "barCountLabel"
            text: pill.countText
            visible: pill.unreadCount > 0
        }
    }
    Column {
        id: pillColumn

        spacing: Theme.spacingXS
        visible: pill.vertical

        GitHubIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            followThemeColor: true
            iconColor: Theme.surfaceText
            iconOpacity: GitHubConstants.githubIconBarOpacity
            size: pill.iconSize
            sourceFallback: pill.githubIconFallback
            sourcePrimary: pill.githubIconPrimary
        }
        StyledText {
            anchors.horizontalCenter: pillColumn.horizontalCenter
            color: Theme.surfaceText
            font.pixelSize: pill.textSize
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            objectName: "barCountLabel"
            text: pill.countText
            visible: pill.unreadCount > 0
        }
    }
}
