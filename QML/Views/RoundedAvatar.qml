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

    // -- Retry state for transient load failures (e.g. network after wakeup) --
    property int _retryCount: 0

    onSourceChanged: _retryCount = 0

    Timer {
        id: retryTimer
        interval: GitHubConstants.avatarImageRetryBaseDelayMs * Math.pow(2, Math.max(0, root._retryCount - 1))
        onTriggered: {
            // Flip source to "" then back to force QML to re-load
            var url = root.source
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
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            sourceSize.width: root.width * 2
            sourceSize.height: root.height * 2

            onStatusChanged: {
                if (status === Image.Error
                        && root.source
                        && String(root.source).indexOf("file://") !== 0
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
        visible: !root.source || avatarImage.status !== Image.Ready
    }
}
