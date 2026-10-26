// DActionButton.qml - native button interaction with the Dux action-button contract.
import QtQuick
import QtQuick.Templates as Templates

Templates.Button {
    property color backgroundColor: "transparent"
    property int buttonSize: 32
    property color color: backgroundColor
    property color iconColor: "white"
    property string iconName: ""
    property int iconSize: 24
    property real radius: buttonSize / 2
    property var tooltipText: null

    hoverEnabled: true
    implicitHeight: buttonSize
    implicitWidth: buttonSize
}
