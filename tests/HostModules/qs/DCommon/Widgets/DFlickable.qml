// DFlickable.qml - keeps Qt's attached scrollbar behavior in isolated view tests.
import QtQuick
import QtQuick.Controls as Controls

Flickable {
    id: view

    property bool fadeEdges: true
    property bool showScrollBar: true
    property alias verticalScrollBar: scrollBar

    Controls.ScrollBar.vertical: DScrollbar {
        id: scrollBar

        allowed: view.showScrollBar
        targetFlickable: view
    }
}
