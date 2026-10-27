// DTooltipHost.qml - host tooltip inputs without creating desktop popup windows in unit tests.
import QtQuick

Item {
    property MouseArea hoverArea: null
    property bool multiline: false
    property bool shown: false
    property Item target: null
    property var text: null
}
