// DSpinner.qml - deterministic geometry for the host's animated busy indicator.
import QtQuick

Item {
    property color color: "white"
    property bool running: visible
    property real size: 48

    implicitHeight: size
    implicitWidth: size
}
