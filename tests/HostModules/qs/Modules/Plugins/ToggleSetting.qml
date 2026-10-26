// ToggleSetting.qml - stand-in for a persisted host boolean setting.

import QtQuick

Item {
    property bool defaultValue: false
    property string description: ""
    required property string label
    required property string settingKey
    property bool value: defaultValue

    function _findSettings() {
        let current = parent;
        while (current) {
            if (current["load" + "Value"] && current["save" + "Value"])
                return current;
            current = current.parent;
        }
        return null;
    }
    function loadValue() {
        let settings = _findSettings();
        if (settings)
            value = settings.loadValue(settingKey, defaultValue);
    }

    onValueChanged: {
        let settings = _findSettings();
        if (settings)
            settings.saveValue(settingKey, value);
    }
}
