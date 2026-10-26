// PopoutComponent.qml - current popup contract, excluding compatibility-only properties.

import QtQuick

Column {
    property var closePopout: null
    property string detailsText: ""
    property int headerHeight: 0
    property string headerText: ""
    property var parentPopout: null
}
