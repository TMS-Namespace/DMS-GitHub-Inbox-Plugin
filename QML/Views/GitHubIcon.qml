// GitHubIcon.qml - GitHub icon with remote favicon + local fallback

import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: root

    property url sourcePrimary: "https://github.com/favicon.ico"
    property url sourceFallback: Qt.resolvedUrl("../../Images/github-mark.svg")
    property int size: 14
    property real iconOpacity: 0.60
    property bool followThemeColor: true
    property color iconColor: Theme.surfaceText

    width: size
    height: size

    property bool useFallback: false

    onSourcePrimaryChanged: useFallback = false

    Image {
        id: iconImage
        anchors.fill: parent
        source: root.followThemeColor || root.useFallback ? root.sourceFallback : root.sourcePrimary
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        cache: true
        opacity: root.iconOpacity
        layer.enabled: root.followThemeColor
        layer.smooth: true
        layer.effect: MultiEffect {
            saturation: 0
            colorization: 1
            colorizationColor: root.iconColor
        }

        onStatusChanged: {
            if (!root.followThemeColor && status === Image.Error && !root.useFallback)
                root.useFallback = true
        }
    }
}
