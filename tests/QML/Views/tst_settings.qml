// tst_settings.qml - exercises the real settings page with a late host service.

import QtQuick
import QtTest
import "../../../src/QML"

TestCase {
    id: testCase

    function createSettings() {
        let component = Qt.createComponent("../../../src/QML/Settings.qml");
        compare(component.status, Component.Ready, component.errorString());
        return component.createObject(testCase, {
            width: 520,
            height: 1000
        });
    }
    function test_lateServiceAttachmentLoadsAndPersistsRealSettingControls() {
        fakePluginService.values = {
            pollInterval: "300",
            loadAuthorInfo: false,
            enableNotifications: true,
            groupItemLimit: 7,
            popupHeight: 12,
            titleLines: "3"
        };
        fakePluginService.writes = [];
        let page = createSettings();

        // DMS creates the settings page before attaching its persistence service.
        compare(fakePluginService.writes.length, 0);
        page.pluginService = fakePluginService;
        page.dependenciesChecked = true;
        page.missingDependencies = [];
        verify(page.dependenciesReady);

        let groupLimit = findChild(page, "groupItemLimitSetting");
        let popupHeight = findChild(page, "popupHeightSetting");
        let pollInterval = findChild(page, "pollIntervalSetting");
        let titleLines = findChild(page, "titleLinesSetting");
        let authorInfo = findChild(page, "loadAuthorInfoSetting");
        let notifications = findChild(page, "enableNotificationsSetting");
        let tokenInput = findChild(page, "githubTokenInput");
        let apiCallStats = findChild(page, "apiCallStatsView");
        verify(groupLimit);
        verify(popupHeight);
        verify(pollInterval);
        verify(titleLines);
        verify(authorInfo);
        verify(notifications);
        verify(tokenInput);
        verify(apiCallStats);
        compare(groupLimit.value, 7);
        compare(popupHeight.value, 12);
        compare(pollInterval.value, "300");
        compare(titleLines.value, "3");
        compare(authorInfo.value, false);
        compare(notifications.value, true);
        page.tokenValue = "ghp_test_token";
        compare(tokenInput.text, "ghp_test_token");

        fakePluginService.writes = [];
        groupLimit.value = 8;
        compare(fakePluginService.writes.length, 1);
        compare(fakePluginService.writes[0].pluginId, page.pluginId);
        compare(fakePluginService.writes[0].key, "groupItemLimit");
        compare(fakePluginService.writes[0].value, 8);
        page.destroy();
    }
    function test_pageWaitsForDependenciesAndExplainsMissingCommands() {
        let page = createSettings();
        verify(!page.dependenciesReady);

        page.dependenciesChecked = true;
        page.missingDependencies = ["curl", "jq"];

        verify(!page.dependenciesReady);
        let dependencyStatus = findChild(page, "dependencyStatus");
        verify(dependencyStatus);
        verify(dependencyStatus.text.indexOf("curl, jq") >= 0);
        page.destroy();
    }

    name: "Settings"

    QtObject {
        id: fakePluginService

        property var values: ({})
        property var writes: []

        signal pluginDataChanged(string pluginId)

        function loadPluginData(pluginId, key, fallbackValue) {
            return values[key] === undefined ? fallbackValue : values[key];
        }
        function savePluginData(pluginId, key, value) {
            let nextValues = Object.assign({}, values);
            nextValues[key] = value;
            values = nextValues;
            writes = writes.concat([
                {
                    pluginId: pluginId,
                    key: key,
                    value: value
                }
            ]);
        }
    }
}
