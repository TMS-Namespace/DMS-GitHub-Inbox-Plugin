// DIcon.qml - headless stand-in for the host's icon item.

import QtQuick

Text {
    property string name: ""
    property int size: 16

    color: "white"
    font.pixelSize: size
    text: name
}
