// Theme.qml - minimal DMS theme interface for headless plugin component tests.

pragma Singleton

import QtQuick

QtObject {
    readonly property int cornerRadius: 8
    readonly property color error: "#cf6679"
    readonly property int fontSizeLarge: 18
    readonly property int fontSizeMedium: 14
    readonly property int fontSizeSmall: 12
    readonly property color nestedSurface: "#22252b"
    readonly property color outlineMedium: "#666a73"
    readonly property color outlineVariant: "#555963"
    readonly property color primary: "#5267d9"
    readonly property int spacingM: 12
    readonly property int spacingS: 8
    readonly property int spacingXL: 24
    readonly property int spacingXS: 4
    readonly property int spacingXXS: 2
    readonly property color surfaceContainer: "#282b32"
    readonly property color surfaceContainerHigh: "#30343c"
    readonly property color surfaceContainerHighest: "#353943"
    readonly property color surfaceText: "#f3f3f3"
    readonly property color surfaceVariant: "#454955"
    readonly property color surfaceVariantText: "#c4c8d2"

    function withAlpha(colorValue, alpha) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, alpha);
    }
}
