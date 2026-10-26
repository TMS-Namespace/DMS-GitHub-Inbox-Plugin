// DTextField.qml - stand-in for the host's password-capable text input.

import QtQuick

TextInput {
    property bool passwordVisible: false
    property string placeholderText: ""
    property bool showPasswordToggle: false
}
