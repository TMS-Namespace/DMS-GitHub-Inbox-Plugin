// GitHubIcon.qml - GitHub icon with remote favicon + local fallback

import QtQuick

Item {
    id: root

    property url sourcePrimary: "https://github.com/favicon.ico"
    property url sourceFallback: Qt.resolvedUrl("../Images/github-mark.svg")
    property int size: 14
    property real iconOpacity: 0.78

    width: size
    height: size

    property bool useFallback: false

    onSourcePrimaryChanged: useFallback = false

    Image {
        id: iconImage
        anchors.fill: parent
        source: root.useFallback ? root.sourceFallback : root.sourcePrimary
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        cache: true
        opacity: root.iconOpacity

        onStatusChanged: {
            if (status === Image.Error && !root.useFallback)
                root.useFallback = true
        }
    }
}
