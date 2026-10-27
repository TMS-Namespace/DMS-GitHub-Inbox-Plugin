// DuxControls.qml - exercises installed Dux controls in an offscreen window, without screenshots.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import "../../src/QML/Services" as Services
import "../../src/QML/Views" as Views
import qs.Common
import qs.DCommon.Widgets

ShellRoot {
    id: checks

    property int cacheActions: 0
    property int groupActions: 0
    property int groupingSelections: 0
    property int phase: 0
    property real previousThumbSize: 0
    property int readActions: 0
    property int readSelections: 0
    property int refreshActions: 0
    property int settingsActions: 0
    property int tokenEdits: 0

    // Search real component instances rather than asserting source-text assumptions.
    function find(item, name) {
        if (item.objectName === name)
            return item;
        for (let child of item.children || []) {
            let result = find(child, name);
            if (result)
                return result;
        }
        return null;
    }
    // Exit normally on failures so test diagnostics never trigger desktop crash reporting.
    function require(condition, message) {
        if (condition)
            return true;
        console.error("DUX_CONTROLS_FAILED: " + message);
        Qt.exit(1);
        return false;
    }

    Component.onCompleted: {
        panel._headerHovered = true;
        let items = [];
        for (let index = 0; index < 15; index++)
            items.push({
                threadId: String(index),
                title: "A notification",
                repository: "owner/repo",
                updatedAtMs: Date.now(),
                unread: true
            });
        panel.messages = items;
    }

    Services.SettingsService {
        id: tokenSettingsService
    }
    Window {
        id: window

        height: 650
        visible: true
        width: 640

        DButton {
            id: defaultCacheButton

            visible: false
        }
        Views.GitHubTokenSetting {
            id: tokenEditor

            saveFailed: tokenSettingsService.tokenSaveFailed || tokenSettingsService.displayedTokenValidationError !== ""
            statusMessage: tokenSettingsService.displayedTokenValidationError || tokenSettingsService.tokenStatusMessage
            tokenValue: tokenSettingsService.tokenValue
            width: 400

            onTokenEdited: function (value) {
                checks.tokenEdits++;
                tokenSettingsService.updateTokenDraft(value);
            }
            onTokenEditingFinished: value => tokenSettingsService.finishTokenEdit(value)
        }
        Views.PopoutPanel {
            id: panel

            anchors.fill: parent
            groupItemLimit: 20
            groupingMode: "date"
            popupOpen: true
            showAuthorInfo: false
            tokenConfigured: true

            onOpenSettings: checks.settingsActions++
            onReadFilterChangedByUser: function (value) {
                checks.readSelections++;
                panel.readFilter = value;
            }
            onRefreshNow: checks.refreshActions++
        }
        Views.InboxMessageRow {
            id: message

            messageData: ({
                    threadId: "42",
                    unread: true,
                    title: "Example",
                    subjectType: "PullRequest"
                })
            visible: false
            width: 500

            onMarkRead: checks.readActions++
        }
        Views.DateGroupingGroupView {
            id: dateGroup

            expanded: true
            groupData: ({
                    label: "Today",
                    items: [
                        {
                            threadId: "42",
                            unread: true
                        }
                    ]
                })
            visible: false
            width: 500

            onMarkGroupRead: function (items) {
                if (items.length === 1 && items[0].threadId === "42")
                    checks.groupActions++;
            }
        }
        Views.SettingsCacheView {
            id: cacheSettings

            visible: false

            onClearCacheRequested: checks.cacheActions++
        }
        Views.SettingsContentView {
            id: settingsGroups

            visible: false
            width: 520
        }
        Views.InboxPopoutView {
            id: popout

            tokenConfigured: true
            visible: false
            width: 500

            onGroupingModeChangedByUser: function (value) {
                checks.groupingSelections++;
                popout.groupingMode = value;
            }
        }
    }
    Timer {
        interval: checks.phase === 1 ? 700 : 150
        repeat: true
        running: true

        onTriggered: {
            let scroller = checks.find(panel, "inboxMessageScroller");
            if (!checks.require(scroller && scroller.verticalScrollBar, "Missing native attached scrollbar"))
                return;
            if (checks.phase === 0) {
                for (let name of ["authenticationSettingsSection", "behaviourSettingsSection", "viewSettingsSection", "cacheSettingsSection", "apiCallStatsView"]) {
                    let section = checks.find(settingsGroups, name);
                    if (!checks.require(section && !section.expanded && section.implicitHeight > 0, "Settings group did not load collapsed: " + name))
                        return;
                    section.toggle();
                    if (!checks.require(section.expanded, "Native settings group did not expand: " + name))
                        return;
                    section.toggle();
                }
                let viewControls = checks.find(settingsGroups, "viewSettingsControls");
                if (!checks.require(viewControls.children[0].objectName === "titleLinesSetting", "Title rows must be first in View Settings"))
                    return;
                let selector = checks.find(panel, "readFilterControl");
                let participation = checks.find(panel, "participationFilterControl");
                if (!checks.require(selector.parent.x === 0 && Math.abs(participation.parent.x + participation.parent.width - panel.width) < 1, "Desktop filters lost their opposite-edge alignment"))
                    return;
                let headerAction = checks.find(panel, "expandAllButton");
                if (!checks.require(headerAction.backgroundColor.a > 0 && headerAction.radius === headerAction.width / 2, "Header action lost its circular background"))
                    return;
                let refreshAction = checks.find(panel, "refreshInboxButton");
                let settingsAction = checks.find(panel, "openInboxSettingsButton");
                let closeAction = checks.find(panel, "closeInboxButton");
                if (!checks.require(settingsAction.x < closeAction.x, "Settings must precede Close in the toolbar"))
                    return;
                panel.isLoading = true;
                refreshAction.click();
                settingsAction.click();
                if (!checks.require(!refreshAction.enabled && refreshAction.color === refreshAction.backgroundColor && refreshAction.radius === refreshAction.width / 2 && checks.refreshActions === 0, "Disabled refresh changed background or remained actionable"))
                    return;
                if (!checks.require(checks.settingsActions === 1, "Settings action was blocked during refresh"))
                    return;
                panel.isLoading = false;
                panel.tokenConfigured = false;
                let disabledIcon = checks.find(headerAction, "disabledToolbarIcon");
                if (!checks.require(!headerAction.enabled && disabledIcon.visible && disabledIcon.color === headerAction.iconColor && headerAction.color === headerAction.backgroundColor, "Disabled toolbar icon or background changed style"))
                    return;
                panel.tokenConfigured = true;
                selector.selectItem(0);
                if (!checks.require(panel.readFilter === "yes" && selector.currentIndex === 0 && checks.readSelections === 1, "Selector did not preserve controlled selection"))
                    return;
                panel.readFilter = "both";
                if (!checks.require(selector.currentIndex === 2 && checks.readSelections === 1, "Programmatic selection emitted a user change"))
                    return;
                let readButton = checks.find(message, "messageReadButton");
                if (!checks.require(readButton.backgroundColor.a > 0 && readButton.radius === readButton.width / 2, "Message action lost its circular background"))
                    return;
                message.isBusy = true;
                readButton.click();
                if (!checks.require(!readButton.enabled && checks.readActions === 0, "Busy action was not disabled"))
                    return;
                message.isBusy = false;
                readButton.click();
                if (!checks.require(checks.readActions === 1, "Native read button did not dispatch its action"))
                    return;
                let groupRead = checks.find(dateGroup, "groupReadButton");
                if (!checks.require(groupRead.backgroundColor.a > 0 && groupRead.radius === groupRead.width / 2, "Group action lost its circular background"))
                    return;
                dateGroup.isBusy = true;
                groupRead.click();
                dateGroup.isBusy = false;
                groupRead.click();
                if (!checks.require(checks.groupActions === 1, "Group action lost membership or ignored busy state"))
                    return;
                let cacheButton = checks.find(cacheSettings, "clearCacheButton");
                if (!checks.require(cacheButton.iconName === "" && cacheButton.backgroundColor === defaultCacheButton.backgroundColor && cacheButton.textColor === defaultCacheButton.textColor, "Cache action must use the same default Dux button style as Markets"))
                    return;
                if (!checks.require(!cacheSettings.expanded && !cacheButton.enabled, "Cache section must start collapsed with inactive contents"))
                    return;
                cacheSettings.toggle();
                cacheButton.click();
                if (!checks.require(checks.cacheActions === 1, "Cache button did not emit its command"))
                    return;
                cacheSettings.toggle();
                if (!checks.require(!cacheSettings.expanded && !cacheButton.enabled, "Collapsed cache section left its action active"))
                    return;
                let groupingControl = checks.find(popout, "groupingModeControl");
                groupingControl.selectItem(1);
                if (!checks.require(popout.groupingMode === "date" && groupingControl.currentIndex === 1 && checks.groupingSelections === 1, "Grouping selector lost its controlled value"))
                    return;
                panel.errorMessage = "First error line\nSecond error line";
                let tooltip = checks.find(panel, "refreshErrorTooltip");
                if (!checks.require(tooltip.multiline && tooltip.text === panel.errorMessage, "Error tooltip lost multiline text"))
                    return;
                if (!checks.require(scroller.contentHeight > scroller.height && scroller.verticalScrollBar.size > 0 && scroller.verticalScrollBar.size < 1, "Scrollbar extent was not attached"))
                    return;
                checks.previousThumbSize = scroller.verticalScrollBar.size;
                scroller.verticalScrollBar.position = 0.2;
                let titleTooltip = checks.find(message, "messageTitleTooltip");
                if (!checks.require(titleTooltip.multiline && titleTooltip.text === "Open web page", "Fitting titles must use the native multiline click tooltip"))
                    return;
                message.messageData = Object.assign({}, message.messageData, {
                    title: "A long title with enough text to be truncated ".repeat(20),
                    repository: "long-organization/" + "long-repository-name".repeat(10)
                });
                message.showRepositoryInfo = true;
                message.visible = true;
                message.authors = [
                    {
                        login: "a-very-long-author-name".repeat(5)
                    }
                ];
                tokenSettingsService.tokenValue = "ghp_" + "a".repeat(36);
                if (!checks.require(checks.tokenEdits === 0, "Loading a token was treated as a user edit"))
                    return;
                let tokenInput = checks.find(tokenEditor, "githubTokenInput");
                tokenInput.forceActiveFocus();
                tokenInput.text = "  ghp_short  ";
                if (!checks.require(tokenInput.getActiveFocus() && checks.tokenEdits === 1 && tokenEditor.tokenValue === "  ghp_short  ", "Native token edit was lost or repeated"))
                    return;
                checks.phase = 1;
            } else if (checks.phase === 1) {
                let metadata = checks.find(message, "messageMetadataRow");
                if (!checks.require(metadata.mapToItem(message, 0, 0).y + metadata.height <= message.height - Theme.spacingS, "Date card metadata exceeds bottom padding with native fonts"))
                    return;
                for (let pair of [["messageTitleTooltip", "Open web page"], ["repositoryTooltip", "Open repo web page"], ["authorTooltip", "Open author's web page"]]) {
                    let tooltip = checks.find(message, pair[0]);
                    if (!checks.require(tooltip && tooltip.multiline && tooltip.target.truncated && tooltip.hoverArea && tooltip.text === tooltip.target.text + "\n" + pair[1], "Truncated links lost their native full-text tooltip: " + pair[0]))
                        return;
                    let content = tooltip.findTextContent(tooltip);
                    if (!checks.require(content && content.horizontalAlignment === Text.AlignLeft, "Native tooltip content is not left-aligned: " + pair[0]))
                        return;
                }
                let errorTooltip = checks.find(panel, "refreshErrorTooltip");
                let errorContent = errorTooltip.findTextContent(errorTooltip);
                if (!checks.require(errorContent && errorContent.horizontalAlignment === Text.AlignLeft, "Refresh-error tooltip is not left-aligned"))
                    return;
                let tokenInput = checks.find(tokenEditor, "githubTokenInput");
                let tokenStatus = checks.find(tokenEditor, "githubTokenStatus");
                if (!checks.require(tokenInput.text === "  ghp_short  " && tokenStatus.text.length > 0 && tokenInput.isError, "Live validation was missing or changed the draft"))
                    return;
                tokenInput.setFocus(false);
                if (!checks.require(tokenInput.text === "ghp_short" && tokenInput.isError && tokenStatus.text.length > 0 && checks.tokenEdits === 1, "Native focus loss did not trim and validate exactly once"))
                    return;
                if (!checks.require(scroller.contentY > 0, "Moving the native thumb did not scroll content"))
                    return;
                scroller.contentY = 0;
                window.height = 450;
                window.width = 360;
                checks.phase = 2;
            } else {
                let tokenStatus = checks.find(tokenEditor, "githubTokenStatus");
                if (!checks.require(tokenStatus.text.length > 0 && tokenStatus.visible, "Committed validation feedback disappeared"))
                    return;
                if (!checks.require(scroller.verticalScrollBar.position === 0 && scroller.verticalScrollBar.size < checks.previousThumbSize, "Scrollbar did not follow content position and resize"))
                    return;
                let readControl = checks.find(panel, "readFilterControl");
                let participationControl = checks.find(panel, "participationFilterControl");
                let first = readControl.mapToItem(panel, 0, 0);
                let second = participationControl.mapToItem(panel, 0, 0);
                if (!checks.require(second.y >= first.y + readControl.height || second.x >= first.x + readControl.width, "Narrow filters overlap"))
                    return;
                if (!checks.require(Math.abs(participationControl.parent.x + participationControl.parent.width - panel.width) < 1, "Narrow participation filter lost right alignment"))
                    return;
                console.info("DUX_CONTROLS_PASSED");
                stop();
                Qt.exit(0);
            }
        }
    }
}
