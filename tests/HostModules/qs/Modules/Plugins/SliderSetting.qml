// SliderSetting.qml - stand-in for a persisted host numeric setting.

import QtQuick

Item {
    property int defaultValue: 0
    required property string label
    property int maximum: 0
    property int minimum: 0
    required property string settingKey
    property int value: defaultValue

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
