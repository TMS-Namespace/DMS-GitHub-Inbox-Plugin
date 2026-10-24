// GitHubTokenSetting.qml - token entry and external token settings link.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: tokenSetting

    property bool saveFailed: false
    property string statusMessage: ""
    property string tokenValue: ""

    signal tokenEdited(string value)
    signal tokenHelpRequested

    spacing: Theme.spacingM
    width: parent.width

    Item {
        height: githubRow.height
        width: githubRow.width

        Row {
            id: githubRow

            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.primary
                name: "link"
                opacity: tokenLinkArea.containsMouse ? 1.0 : 0.7
                size: Theme.fontSizeSmall
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                opacity: tokenLinkArea.containsMouse ? 1.0 : 0.7
                text: "Create classic token on GitHub"
            }
        }
        MouseArea {
            id: tokenLinkArea

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            onClicked: tokenSetting.tokenHelpRequested()
        }
    }
    Column {
        spacing: Theme.spacingXS
        width: parent.width

        StyledText {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            text: "GitHub Classic Token"
        }
        DTextField {
            echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
            height: Math.round(Theme.fontSizeMedium * 3)
            objectName: "githubTokenInput"
            placeholderText: "ghp_..."
            showPasswordToggle: true
            text: tokenSetting.tokenValue
            width: parent.width

            onTextEdited: tokenSetting.tokenEdited(text)
        }
        StyledText {
            color: tokenSetting.saveFailed ? Theme.error : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: tokenSetting.statusMessage
            visible: tokenSetting.statusMessage.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
}
