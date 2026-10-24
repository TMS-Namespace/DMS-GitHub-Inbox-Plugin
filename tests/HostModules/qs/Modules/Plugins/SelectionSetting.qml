// SelectionSetting.qml - stand-in for a persisted host selection setting.

import QtQuick

Item {
    property string defaultValue: ""
    property string description: ""
    required property string label
    required property var options
    required property string settingKey
    property string value: defaultValue

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
