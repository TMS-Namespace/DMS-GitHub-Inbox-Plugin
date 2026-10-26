// PluginSettings.qml - stand-in for the host's settings page contract.

import QtQuick

Item {
    required property string pluginId
    property var pluginService: null

    function loadValue(key, fallbackValue) {
        return pluginService ? pluginService.loadPluginData(pluginId, key, fallbackValue) : fallbackValue;
    }
    function saveValue(key, value) {
        if (pluginService)
            pluginService.savePluginData(pluginId, key, value);
    }
}
