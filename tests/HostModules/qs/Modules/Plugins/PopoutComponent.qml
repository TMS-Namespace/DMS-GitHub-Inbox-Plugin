// PopoutComponent.qml - stand-in for the host's popup content contract.

import QtQuick

Item {
    property string detailsText: ""
    property int headerHeight: 0
    property string headerText: ""
    property var parentPopout: null
    property bool showCloseButton: true
}
