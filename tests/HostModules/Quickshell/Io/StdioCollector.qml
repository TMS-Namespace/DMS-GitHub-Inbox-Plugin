// StdioCollector.qml - headless stream collector contract for Process tests.

import QtQuick

QtObject {
    property string text: ""

    signal streamFinished
}
