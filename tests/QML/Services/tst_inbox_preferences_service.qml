// tst_inbox_preferences_service.qml - tests preference normalization and persistence.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    function init() {
        fakePluginService.writes = [];
    }
    function test_invalidPluginDataUsesSafeDefaultsAndClampsNumbers() {
        preferences.pluginData = ({
                groupItemLimit: "999",
                groupingMode: "unknown",
                participationFilter: "maybe",
                popupHeight: "bad",
                readFilter: "YES",
                titleLines: "0"
            });

        compare(preferences.groupItemLimit, 25);
        compare(preferences.groupingMode, "repo");
        compare(preferences.participationFilter, "both");
        compare(preferences.popupHeightUnits, 15);
        compare(preferences.readFilter, "yes");
        compare(preferences.titleLines, 1);
    }
    function test_userPreferenceChangesAreNormalizedAndPersisted() {
        preferences.setGroupingMode("date");
        preferences.setParticipationFilter("YES");
        preferences.setReadFilter("invalid");

        compare(preferences.groupingMode, "date");
        compare(preferences.participationFilter, "yes");
        compare(preferences.readFilter, "both");
        compare(fakePluginService.writes.length, 3);
        compare(fakePluginService.writes[0].key, "groupingMode");
        compare(fakePluginService.writes[0].value, "date");
        compare(fakePluginService.writes[1].value, "yes");
        compare(fakePluginService.writes[2].value, "both");
    }

    name: "InboxPreferencesService"

    QtObject {
        id: fakePluginService

        property var writes: []

        function savePluginData(pluginId, key, value) {
            writes = writes.concat([
                {
                    pluginId: pluginId,
                    key: key,
                    value: value
                }
            ]);
        }
    }
    InboxPreferencesService {
        id: preferences

        pluginData: ({})
        pluginService: fakePluginService

        providerApi: QtObject {
            function pluginDataBool(value, fallbackValue) {
                return value === undefined ? fallbackValue : !!value;
            }
            function pollIntervalMs(value, fallbackValue) {
                return Number(value || fallbackValue) * 1000;
            }
        }
    }
}
