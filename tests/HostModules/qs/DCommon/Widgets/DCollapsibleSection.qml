// DCollapsibleSection.qml - retains the native section's expansion and disabled-content contract.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: section

    default property alias content: contentColumn.data
    property string description: ""
    property bool expanded: false
    required property string title

    signal toggleRequested

    function toggle() {
        if (!enabled)
            return;
        toggleRequested();
        expanded = !expanded;
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 40
    }
    ColumnLayout {
        id: contentColumn

        Layout.fillWidth: true
        enabled: section.expanded
        visible: section.expanded
    }
}
