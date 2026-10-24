// GitHubIcon.qml - GitHub icon with remote favicon + local fallback

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: root

    property bool followThemeColor: true
    property color iconColor: Theme.surfaceText
    property real iconOpacity: 0.60
    property int size: 14
    property url sourceFallback: Qt.resolvedUrl("../../../images/github-mark.svg")
    property url sourcePrimary: "https://github.com/favicon.ico"
    property bool useFallback: false

    height: size
    width: size

    onSourcePrimaryChanged: useFallback = false

    Image {
        id: iconImage

        anchors.fill: parent
        antialiasing: true
        cache: true
        fillMode: Image.PreserveAspectFit
        layer.enabled: root.followThemeColor
        layer.smooth: true
        opacity: root.iconOpacity
        smooth: true
        source: root.followThemeColor || root.useFallback ? root.sourceFallback : root.sourcePrimary

        layer.effect: MultiEffect {
            colorization: 1
            colorizationColor: root.iconColor
            saturation: 0
        }

        onStatusChanged: {
            if (!root.followThemeColor && status === Image.Error && !root.useFallback)
                root.useFallback = true;
        }
    }
}
