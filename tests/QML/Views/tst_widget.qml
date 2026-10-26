// tst_widget.qml - tests the real widget entry point with late host services.

import QtQuick
import QtTest
import qs.Common
import qs.Services

TestCase {
    id: testCase

    property int closeRequests: 0
    property var delegatedAuthorRequests: []
    property var delegatedPreferences: []
    property int refreshRequests: 0
    property var settingsEvents: []

    function createWidget() {
        let component = Qt.createComponent("../../../src/QML/Widget.qml");
        compare(component.status, Component.Ready, component.errorString());
        return component.createObject(testCase, {
            width: 480,
            height: 800,
            pluginData: ({}),
            workerScriptsEnabled: false
        });
    }
    // Opening the host popup must immediately expose messages loaded while it was closed.
    function test_openPopupDisplaysCachedMessages() {
        let widget = createWidget();
        let popout = widget.popoutContent.createObject(testCase);
        widget.inboxMessages = [
            {
                threadId: "cached-one",
                unread: true
            },
            {
                threadId: "cached-two",
                unread: false
            }
        ];
        compare(widget.messagesForView.length, 0);
        popupHost.shouldBeVisible = false;
        popout.parentPopout = popupHost;
        popupHost.shouldBeVisible = true;
        compare(widget.popoutVisible, true);
        compare(widget.messagesForView.length, 2);
        compare(popout.messages.length, 2);
        popupHost.shouldBeVisible = false;
        popupHost.shouldBeVisible = true;
        compare(popout.messages.length, 2);
        popout.destroy();
        widget.destroy();
    }
    function test_popoutRoutesCommandsToServicesAndHostCallbacks() {
        delegatedAuthorRequests = [];
        delegatedPreferences = [];
        closeRequests = 0;
        refreshRequests = 0;
        let widget = createWidget();
        let popout = widget.popoutContent.createObject(testCase);
        popout.preferencesService = fakePreferences;
        popout.authorRequestCallback = function (threadId, url, subjectType) {
            testCase.delegatedAuthorRequests.push([threadId, url, subjectType]);
        };
        popout.closePopoutCallback = function () {
            testCase.closeRequests++;
        };
        popout.refreshCallback = function () {
            testCase.refreshRequests++;
        };

        popout.groupingModeChangedByUser("date");
        popout.participationFilterChangedByUser("yes");
        popout.closeRequested();
        popout.refreshNow();
        popout.requestThreadAuthors("42", "https://api.github.com/repos/owner/repo/pulls/42", "PullRequest");

        compare(delegatedPreferences, ["groupingMode:date", "participationFilter:yes"]);
        compare(closeRequests, 1);
        compare(refreshRequests, 1);
        compare(delegatedAuthorRequests, [["42", "https://api.github.com/repos/owner/repo/pulls/42", "PullRequest"]]);
        popout.destroy();
        widget.destroy();
    }
    // Check the expanded column against the host's padding, not against a screenshot.
    function test_popoutUsesCompactHostInsets() {
        let widget = createWidget();
        let popout = widget.popoutContent.createObject(testCase, {
            width: 480
        });
        let column = findChild(popout, "compactInboxPopout");
        verify(column);
        compare(PopoutMetrics.contentPadding + column.x, Theme.spacingS);
        compare(PopoutMetrics.contentPadding + popout.width - column.x - column.width, Theme.spacingS);
        compare(PopoutMetrics.contentPadding + column.y, Theme.spacingS);
        compare(PopoutMetrics.contentPadding + popout.implicitHeight - column.y - column.implicitHeight, Theme.spacingS);
        popout.width = 360;
        compare(PopoutMetrics.contentPadding + popout.width - column.x - column.width, Theme.spacingS);
        popout.destroy();
        widget.destroy();
    }
    // The actual button must close the inbox before opening this plugin's settings tab.
    function test_settingsButtonClosesPopupBeforeOpeningPluginSettings() {
        settingsEvents = [];
        PopoutService.settingsModal = settingsModal;
        let widget = createWidget();
        let popout = widget.popoutContent.createObject(testCase, {
            width: 480
        });
        widget._popoutClosed.connect(function () {
            testCase.settingsEvents.push("closed");
        });
        let button = findChild(popout, "openInboxSettingsButton");
        verify(button);
        button.click();
        compare(settingsEvents, ["closed", "plugin:githubInbox"]);
        PopoutService.settingsModal = null;
        popout.destroy();
        widget.destroy();
    }
    function test_widgetPresentationComponentsInstantiate() {
        let widget = createWidget();
        let popout = widget.popoutContent.createObject(testCase);
        let horizontalPill = widget.horizontalBarPill.createObject(testCase);
        let verticalPill = widget.verticalBarPill.createObject(testCase);

        verify(popout);
        verify(horizontalPill);
        verify(verticalPill);
        widget.textSize = 22;
        widget.iconSize = 32;
        compare(horizontalPill.textSize, 22);
        compare(verticalPill.textSize, 22);
        compare(horizontalPill.iconSize, 32);
        compare(verticalPill.iconSize, 32);
        compare(findChild(horizontalPill, "barCountLabel").font.pixelSize, 22);
        compare(findChild(verticalPill, "barCountLabel").font.pixelSize, 22);
        compare(popout.headerText, "GitHub Inbox");
        compare(horizontalPill.vertical, false);
        compare(verticalPill.vertical, true);

        horizontalPill.destroy();
        verticalPill.destroy();
        popout.destroy();
        widget.destroy();
    }
    function test_widgetWaitsForLateHostServiceWithoutReportingAnError() {
        fakePluginService.values = ({});
        fakePluginService.writes = [];
        let widget = createWidget();

        compare(widget.errorMessage, "");
        compare(fakePluginService.writes.length, 0);
        widget.pluginService = fakePluginService;
        compare(widget.errorMessage, "");
        compare(widget.providerApi.providerId, "github");
        widget.destroy();
    }

    name: "Widget"

    QtObject {
        id: settingsModal

        function showWithTabName(tabName) {
            testCase.settingsEvents.push(tabName);
        }
    }
    QtObject {
        id: popupHost

        property bool shouldBeVisible: false
    }
    QtObject {
        id: fakePreferences

        function setGroupingMode(value) {
            testCase.delegatedPreferences = testCase.delegatedPreferences.concat(["groupingMode:" + value]);
        }
        function setParticipationFilter(value) {
            testCase.delegatedPreferences = testCase.delegatedPreferences.concat(["participationFilter:" + value]);
        }
        function setReadFilter(value) {
            testCase.delegatedPreferences = testCase.delegatedPreferences.concat(["readFilter:" + value]);
        }
    }
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
