// RoundedAvatar.qml - Reusable circular avatar with fallback icon

import QtQuick
import Quickshell.Widgets as QSW
import qs.Common
import qs.Widgets
import ".."

Item {
    id: root

    property string source: ""
    property string fallbackIcon: "person"
    property int fallbackIconSize: 12
    property color fallbackIconColor: Theme.surfaceVariantText
    property color backgroundColor: Theme.surfaceContainerHighest
    property bool allowRemote: false

    // -- Retry state for transient load failures (e.g. network after wakeup) --
    property int _retryCount: 0
    property string loadableSource: {
        var value = String(root.source || "")
        if (!value)
            return ""
        if (value.indexOf("file://") === 0 || value.indexOf("qrc:") === 0)
            return value
        return root.allowRemote ? value : ""
    }

    onSourceChanged: _retryCount = 0

    Timer {
        id: retryTimer
        interval: GitHubConstants.avatarImageRetryBaseDelayMs * Math.pow(2, Math.max(0, root._retryCount - 1))
        onTriggered: {
            // Flip source to "" then back to force QML to re-load
            var url = root.loadableSource
            avatarImage.source = ""
            avatarImage.source = url
        }
    }

    QSW.ClippingRectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        color: root.backgroundColor

        Image {
            id: avatarImage
            anchors.fill: parent
            source: root.loadableSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            sourceSize.width: root.width * 2
            sourceSize.height: root.height * 2

            onStatusChanged: {
                if (status === Image.Error
                        && root.loadableSource
                        && String(root.loadableSource).indexOf("file://") !== 0
                        && root._retryCount < GitHubConstants.avatarImageMaxRetries) {
                    root._retryCount++
                    retryTimer.restart()
                }
            }
        }
    }

    DankIcon {
        anchors.centerIn: parent
        name: root.fallbackIcon
        size: root.fallbackIconSize
        color: root.fallbackIconColor
        visible: !root.loadableSource || avatarImage.status !== Image.Ready
    }
}
