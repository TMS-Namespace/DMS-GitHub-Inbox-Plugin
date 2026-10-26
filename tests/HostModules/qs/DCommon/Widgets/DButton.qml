// DButton.qml - native button interaction with the Dux text-button contract.
import QtQuick
import QtQuick.Templates as Templates

Templates.Button {
    property color backgroundColor: "transparent"
    property string iconName: ""
    property real maximumWidth: Infinity
    property color textColor: "white"

    implicitHeight: 36
    implicitWidth: Math.min(maximumWidth, 140)
}
