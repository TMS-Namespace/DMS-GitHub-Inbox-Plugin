// RoundedAvatar.qml - Reusable circular avatar with fallback icon

import QtQuick
import Quickshell.Widgets as QSW
import qs.Common
import qs.Widgets

Item {
    id: root

    property string source: ""
    property string fallbackIcon: "person"
    property int fallbackIconSize: 12
    property color fallbackIconColor: Theme.surfaceVariantText
    property color backgroundColor: Theme.surfaceContainerHighest

    QSW.ClippingRectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        color: root.backgroundColor

        Image {
            id: avatarImage
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            sourceSize.width: root.width * 2
            sourceSize.height: root.height * 2
        }
    }

    DankIcon {
        anchors.centerIn: parent
        name: root.fallbackIcon
        size: root.fallbackIconSize
        color: root.fallbackIconColor
        visible: !root.source || avatarImage.status !== Image.Ready
    }
}
