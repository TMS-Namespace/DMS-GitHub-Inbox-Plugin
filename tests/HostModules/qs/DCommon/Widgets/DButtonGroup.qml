// DButtonGroup.qml - controlled selection emits user intent without mutating bound selection.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as Templates

Row {
    id: group

    property int buttonHeight: 32
    property int buttonPadding: 8
    property bool checkEnabled: true
    property int currentIndex: -1
    property int minButtonWidth: 40
    property var model: []
    property color selectedColor: "white"
    property color selectedContentColor: "black"
    property string size: "medium"
    property color unselectedColor: "transparent"
    property color unselectedContentColor: "white"

    signal selectionChanged(int index, bool selected)

    function selectItem(index) {
        selectionChanged(index, true);
        if (currentIndex >= 0 && currentIndex !== index)
            selectionChanged(currentIndex, false);
    }

    Repeater {
        model: group.model

        delegate: Templates.Button {
            required property int index
            required property string modelData

            height: group.buttonHeight
            text: modelData
            width: group.minButtonWidth

            onClicked: group.selectItem(index)
        }
    }
}
