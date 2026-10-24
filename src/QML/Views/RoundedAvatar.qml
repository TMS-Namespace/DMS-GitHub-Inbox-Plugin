// RoundedAvatar.qml - Reusable circular avatar with fallback icon

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets as QSW
import ".."
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    // -- Retry state for transient load failures (e.g. network after wakeup) --
    property int _retryCount: 0
    property bool allowRemote: false
    property color backgroundColor: Theme.surfaceContainerHighest
    property string fallbackIcon: "person"
    property color fallbackIconColor: Theme.surfaceVariantText
    property int fallbackIconSize: 12
    readonly property bool imageReady: avatarImage.status === Image.Ready
    property string loadableSource: {
        let value = String(root.source || "");
        if (!value)
            return "";
        if (value.indexOf("file://") === 0 || value.indexOf("qrc:") === 0)
            return value;
        return root.allowRemote ? value : "";
    }
    property string source: ""

    onSourceChanged: _retryCount = 0

    Timer {
        id: retryTimer

        interval: GitHubConstants.avatarImageRetryBaseDelayMs * Math.pow(2, Math.max(0, root._retryCount - 1))

        onTriggered: {
            // Flip source to "" then back to force QML to re-load
            let url = root.loadableSource;
            avatarImage.source = "";
            avatarImage.source = url;
        }
    }
    QSW.ClippingRectangle {
        id: mask

        anchors.fill: parent
        color: root.backgroundColor
        radius: width / 2

        Image {
            id: avatarImage

            anchors.fill: parent
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            source: root.loadableSource
            sourceSize.height: root.height * 2
            sourceSize.width: root.width * 2
            visible: status === Image.Ready

            onStatusChanged: {
                if (status === Image.Error && root.loadableSource && String(root.loadableSource).indexOf("file://") !== 0 && root._retryCount < GitHubConstants.avatarImageMaxRetries) {
                    root._retryCount++;
                    retryTimer.restart();
                }
            }
        }
    }
    DIcon {
        anchors.centerIn: parent
        color: root.fallbackIconColor
        name: root.fallbackIcon
        size: root.fallbackIconSize
        visible: !root.loadableSource || avatarImage.status !== Image.Ready
    }
}
