// PopoutPanel.qml - Popup content for GitHub inbox messages list
//
// Pure visual component.  Filtering, grouping and expanded-state
// management lives in the grouping models.

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common
import qs.DCommon.Widgets

Item {
    id: panel

    property bool _headerHovered: headerHoverArea.containsMouse || expandAllArea.hovered || collapseAllArea.hovered || refreshAllArea.hovered || markAllArea.hovered || closeArea.hovered || settingsArea.hovered
    property real _relativeTimeReferenceMs: Date.now()
    property bool anyBusy: isRefreshBusy
    property var authorsByThread: ({})
    property string errorMessage: ""
    property var expandedDateGroupsState: ({
            [GitHubConstants.expandedStateDefaultKey]: true
        })
    property var expandedReposState: ({
            [GitHubConstants.expandedStateDefaultKey]: true
        })
    property int groupItemLimit: GitHubConstants.defaultGroupItemLimit
    property string groupingMode: "repo"              // repo | date
    property bool hasBlockingError: hasError && messages.length === 0 && !isLoading
    property bool hasDisplayedMessages: groupingMode === "date" ? dateGrouping.hasDisplayedMessages : repoGrouping.hasDisplayedMessages
    property bool hasError: errorMessage !== ""
    property real headerHoverBottomInset: 0
    property real headerHoverHeight: headerOffset
    property real headerOffset: 0
    property bool isAuthorFetching: false
    property bool isDownloadingAvatars: false
    property bool isLoading: false
    property bool isOperating: false
    property bool isRefreshBusy: isLoading || isAuthorFetching || isDownloadingAvatars || isOperating
    property real lastUpdated: 0

    // -- Inputs ---------------------------------------------------------------
    property var messages: []
    property string participationFilter: "both"       // yes | no | both
    property bool popupOpen: false
    property string readFilter: "both"                // yes | no | both
    property string refreshTooltipText: {
        if (panel.anyBusy)
            return "Refresh in progress";
        if (panel.hasError)
            return panel.errorMessage || "Last refresh failed";
        return "Refresh GitHub inbox";
    }
    property bool showAuthorInfo: true
    property int titleLines: GitHubConstants.defaultTitleLines
    property bool tokenConfigured: false
    property int unreadCount: 0

    signal closePopout
    signal markAllRead
    signal markDateGroupDone(var items)
    signal markDateGroupRead(var items)
    signal markRepoDone(var items)
    signal markRepoRead(var items)
    signal markThreadDone(string threadId)
    signal markThreadRead(string threadId)
    signal markThreadReadAfterOpen(string threadId)
    signal markThreadUnread(string threadId)
    signal openSettings
    signal participationFilterChangedByUser(string value)
    signal persistExpandedDateGroups(var state)
    signal persistExpandedRepos(var state)
    signal readFilterChangedByUser(string value)

    // -- Actions --------------------------------------------------------------
    signal refreshNow
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)

    // Format the user-facing update label without changing its stored UTC timestamp.
    function _lastUpdatedText() {
        let timestamp = Number(lastUpdated || 0);
        if (timestamp <= 0)
            return "";

        let updated = new Date(timestamp);
        let elapsedMinutes = Math.max(0, Math.floor((_relativeTimeReferenceMs - timestamp) / 60000));
        let elapsedHours = Math.floor(elapsedMinutes / 60);
        let elapsedMinutePart = elapsedMinutes % 60;
        return "Updated " + _padTwo(updated.getHours()) + ":" + _padTwo(updated.getMinutes()) + " " + _padTwo(updated.getDate()) + "/" + _padTwo(updated.getMonth() + 1) + "/" + _padTwo(updated.getFullYear() % 100) + " (" + _padTwo(elapsedHours) + ":" + _padTwo(elapsedMinutePart) + " min. ago)";
    }
    // Keep timestamp label fields at a stable width.
    function _padTwo(value) {
        let text = String(Math.max(0, Math.floor(value)));
        return text.length < 2 ? "0" + text : text;
    }
    // Route group controls to the model selected by the current grouping mode.
    function activeGroupingModel() {
        return groupingMode === "date" ? dateGrouping : repoGrouping;
    }

    onLastUpdatedChanged: _relativeTimeReferenceMs = Date.now()
    onPopupOpenChanged: {
        if (popupOpen)
            _relativeTimeReferenceMs = Date.now();
    }

    // -- Models ---------------------------------------------------------------
    RepoGroupingModel {
        id: repoGrouping

        expandedGroupsState: panel.expandedReposState
        groupItemLimit: panel.groupItemLimit
        messages: panel.messages
        participationFilter: panel.participationFilter
        readFilter: panel.readFilter

        onPersistExpandedGroups: function (state) {
            panel.persistExpandedRepos(state);
        }
    }
    DateGroupingModel {
        id: dateGrouping

        expandedGroupsState: panel.expandedDateGroupsState
        groupItemLimit: panel.groupItemLimit
        messages: panel.messages
        participationFilter: panel.participationFilter
        readFilter: panel.readFilter

        onPersistExpandedGroups: function (state) {
            panel.persistExpandedDateGroups(state);
        }
    }

    // =========================================================================
    //  HEADER HOVER BUTTONS
    // =========================================================================

    StyledText {
        id: lastUpdatedLabel

        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        color: Theme.surfaceVariantText
        font.pixelSize: Math.max(6, Theme.fontSizeSmall - 4)
        opacity: 0.4
        text: panel._lastUpdatedText()
        visible: panel.lastUpdated > 0 && !headerButtons.visible
        y: -panel.headerOffset + (panel.headerHoverHeight - height) / 2
        z: 101
    }
    MouseArea {
        id: headerHoverArea

        acceptedButtons: Qt.NoButton
        height: panel.headerHoverHeight
        hoverEnabled: true
        width: parent.width
        x: 0
        y: -panel.headerHoverBottomInset - panel.headerHoverHeight
        z: 100
    }
    Row {
        id: headerButtons

        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        opacity: visible ? 1 : 0
        spacing: Theme.spacingS + GitHubConstants.popoutHeaderButtonSpacingDelta
        visible: panel.anyBusy || panel.hasError || panel._headerHovered
        y: -panel.headerOffset + Theme.spacingXS
        z: 101

        Behavior on opacity {
            NumberAnimation {
                duration: GitHubConstants.popoutHeaderFadeDurationMs
            }
        }

        DActionButton {
            id: expandAllArea

            backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
            buttonSize: GitHubConstants.popoutHeaderButtonSizePx
            color: backgroundColor
            enabled: panel.tokenConfigured
            iconColor: expandAllArea.hovered ? Theme.primary : Theme.surfaceText
            iconName: enabled ? "unfold_more" : ""
            iconSize: GitHubConstants.popoutHeaderButtonIconSizePx
            objectName: "expandAllButton"
            radius: width / 2
            tooltipText: "Expand all groups"
            visible: panel._headerHovered

            onClicked: panel.activeGroupingModel().expandAllGroups()

            // Keep the legacy glyph color without enabling the disabled native control.
            DIcon {
                anchors.centerIn: parent
                color: expandAllArea.iconColor
                name: "unfold_more"
                objectName: "disabledToolbarIcon"
                size: expandAllArea.iconSize
                visible: !expandAllArea.enabled
            }
        }
        DActionButton {
            id: collapseAllArea

            backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
            buttonSize: GitHubConstants.popoutHeaderButtonSizePx
            color: backgroundColor
            enabled: panel.tokenConfigured
            iconColor: collapseAllArea.hovered ? Theme.primary : Theme.surfaceText
            iconName: enabled ? "unfold_less" : ""
            iconSize: GitHubConstants.popoutHeaderButtonIconSizePx
            objectName: "collapseAllButton"
            radius: width / 2
            tooltipText: "Collapse all groups"
            visible: panel._headerHovered

            onClicked: panel.activeGroupingModel().collapseAllGroups()

            // Keep the legacy glyph color without enabling the disabled native control.
            DIcon {
                anchors.centerIn: parent
                color: collapseAllArea.iconColor
                name: "unfold_less"
                objectName: "disabledToolbarIcon"
                size: collapseAllArea.iconSize
                visible: !collapseAllArea.enabled
            }
        }
        DActionButton {
            id: refreshAllArea

            backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
            buttonSize: GitHubConstants.popoutHeaderButtonSizePx
            color: backgroundColor
            enabled: !panel.anyBusy && panel.tokenConfigured
            iconColor: panel.hasError ? Theme.error : Theme.surfaceText
            iconName: enabled && !panel.anyBusy ? "refresh" : ""
            iconSize: GitHubConstants.popoutHeaderButtonIconSizePx
            objectName: "refreshInboxButton"
            radius: width / 2

            onClicked: panel.refreshNow()

            // Keep the legacy glyph color without enabling the disabled native control.
            DIcon {
                anchors.centerIn: parent
                color: refreshAllArea.iconColor
                name: "refresh"
                objectName: "disabledToolbarIcon"
                size: refreshAllArea.iconSize
                visible: !refreshAllArea.enabled && !panel.anyBusy
            }
            DSpinner {
                anchors.centerIn: parent
                color: Theme.primary
                running: panel.popupOpen && panel.anyBusy
                size: GitHubConstants.popoutHeaderButtonIconSizePx
                visible: panel.anyBusy
            }
            MouseArea {
                id: refreshTooltipHover

                acceptedButtons: Qt.NoButton
                anchors.fill: parent
                hoverEnabled: true
            }
            LeftAlignedTooltip {
                hoverArea: refreshTooltipHover
                multiline: true
                objectName: "refreshErrorTooltip"
                target: refreshAllArea
                text: panel.refreshTooltipText
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                color: Theme.error
                height: width
                radius: width / 2
                visible: panel.hasError && !panel.anyBusy
                width: Theme.fontSizeSmall

                StyledText {
                    anchors.centerIn: parent
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall + GitHubConstants.popoutErrorBadgeFontSizeDelta
                    text: "!"
                }
            }
        }
        DActionButton {
            id: markAllArea

            backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
            buttonSize: GitHubConstants.popoutHeaderButtonSizePx
            color: backgroundColor
            enabled: !panel.anyBusy
            iconColor: markAllArea.hovered ? Theme.primary : Theme.surfaceText
            iconName: enabled ? "done_all" : ""
            iconSize: GitHubConstants.popoutHeaderButtonIconSizePx
            objectName: "markAllReadButton"
            radius: width / 2
            tooltipText: "Mark all as read"
            visible: panel._headerHovered && panel.tokenConfigured && panel.unreadCount > 0

            onClicked: panel.markAllRead()

            // Keep the legacy glyph color without enabling the disabled native control.
            DIcon {
                anchors.centerIn: parent
                color: markAllArea.iconColor
                name: "done_all"
                objectName: "disabledToolbarIcon"
                size: markAllArea.iconSize
                visible: !markAllArea.enabled
            }
        }
        DActionButton {
            id: settingsArea

            backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
            buttonSize: GitHubConstants.popoutHeaderButtonSizePx
            color: backgroundColor
            iconColor: settingsArea.hovered ? Theme.primary : Theme.surfaceText
            iconName: "settings"
            iconSize: GitHubConstants.popoutHeaderButtonIconSizePx
            objectName: "openInboxSettingsButton"
            radius: width / 2
            tooltipText: "Open GitHub Inbox settings"
            visible: panel._headerHovered

            onClicked: panel.openSettings()
        }
        DActionButton {
            id: closeArea

            backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
            buttonSize: GitHubConstants.popoutHeaderButtonSizePx
            color: backgroundColor
            iconColor: closeArea.hovered ? Theme.primary : Theme.surfaceText
            iconName: "close"
            iconSize: GitHubConstants.popoutHeaderButtonIconSizePx
            objectName: "closeInboxButton"
            radius: width / 2
            tooltipText: "Close inbox"
            visible: panel._headerHovered

            onClicked: panel.closePopout()
        }
    }

    // =========================================================================
    //  GROUPED INBOX MESSAGE LIST
    // =========================================================================

    DFlickable {
        id: groupedFlick

        anchors.bottom: filterBar.visible ? filterBar.top : parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        contentHeight: groupsColumn.implicitHeight
        contentWidth: width
        fadeEdges: false
        objectName: "inboxMessageScroller"
        visible: panel.tokenConfigured && !panel.hasBlockingError && (panel.hasDisplayedMessages || panel.isLoading)

        Column {
            id: groupsColumn

            spacing: Theme.spacingS
            width: groupedFlick.width

            RepoGroupingView {
                authorsByThread: panel.authorsByThread
                groupingModel: repoGrouping
                groups: repoGrouping.groups
                height: visible ? implicitHeight : 0
                isBusy: panel.anyBusy
                showAuthorInfo: panel.showAuthorInfo
                titleLines: panel.titleLines
                visible: panel.groupingMode === "repo"
                width: groupsColumn.width

                onClosePopout: panel.closePopout()
                onMarkRepoDone: function (items) {
                    panel.markRepoDone(items);
                }
                onMarkRepoRead: function (items) {
                    panel.markRepoRead(items);
                }
                onMarkThreadDone: function (threadId) {
                    panel.markThreadDone(threadId);
                }
                onMarkThreadRead: function (threadId) {
                    panel.markThreadRead(threadId);
                }
                onMarkThreadReadAfterOpen: function (threadId) {
                    panel.markThreadReadAfterOpen(threadId);
                }
                onMarkThreadUnread: function (threadId) {
                    panel.markThreadUnread(threadId);
                }
                onRequestThreadAuthors: function (threadId, subjectApiUrl, subjectType) {
                    panel.requestThreadAuthors(threadId, subjectApiUrl, subjectType);
                }
            }
            DateGroupingView {
                authorsByThread: panel.authorsByThread
                groupingModel: dateGrouping
                groups: dateGrouping.groups
                height: visible ? implicitHeight : 0
                isBusy: panel.anyBusy
                showAuthorInfo: panel.showAuthorInfo
                titleLines: panel.titleLines
                visible: panel.groupingMode === "date"
                width: groupsColumn.width

                onClosePopout: panel.closePopout()
                onMarkGroupDone: function (items) {
                    panel.markDateGroupDone(items);
                }
                onMarkGroupRead: function (items) {
                    panel.markDateGroupRead(items);
                }
                onMarkThreadDone: function (threadId) {
                    panel.markThreadDone(threadId);
                }
                onMarkThreadRead: function (threadId) {
                    panel.markThreadRead(threadId);
                }
                onMarkThreadReadAfterOpen: function (threadId) {
                    panel.markThreadReadAfterOpen(threadId);
                }
                onMarkThreadUnread: function (threadId) {
                    panel.markThreadUnread(threadId);
                }
                onRequestThreadAuthors: function (threadId, subjectApiUrl, subjectType) {
                    panel.requestThreadAuthors(threadId, subjectApiUrl, subjectType);
                }
            }
        }
    }
    Item {
        id: filterBar

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: filterRow.implicitHeight + Theme.spacingS + GitHubConstants.popoutFilterBarVerticalPaddingDelta
        visible: panel.tokenConfigured && !panel.hasBlockingError
        z: 5

        Item {
            id: filterRow

            readonly property bool stacked: readGroup.implicitWidth + participatedGroup.implicitWidth + Theme.spacingS > width

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingS
            implicitHeight: stacked ? readGroup.implicitHeight + participatedGroup.implicitHeight + Theme.spacingS : Math.max(readGroup.implicitHeight, participatedGroup.implicitHeight)

            Row {
                id: readGroup

                anchors.left: parent.left
                anchors.top: parent.top
                spacing: Theme.spacingXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    text: "Read"
                }
                DButtonGroup {
                    id: readFilterSegments

                    buttonHeight: GitHubConstants.popoutFilterSegmentHeightPx
                    buttonPadding: Theme.spacingXS
                    checkEnabled: false
                    currentIndex: ["yes", "no", "both"].indexOf(panel.readFilter)
                    minButtonWidth: Theme.fontSizeSmall * 3
                    model: ["Yes", "No", "Both"]
                    objectName: "readFilterControl"
                    selectedColor: Theme.withAlpha(Theme.primary, GitHubConstants.filterSelectionOpacity)
                    selectedContentColor: Theme.primary
                    size: "small"
                    unselectedColor: Theme.nestedSurface
                    unselectedContentColor: Theme.surfaceVariantText

                    onSelectionChanged: function (index, selected) {
                        if (selected)
                            panel.readFilterChangedByUser(["yes", "no", "both"][index]);
                    }
                }
            }
            Row {
                id: participatedGroup

                anchors.right: parent.right
                spacing: Theme.spacingXS
                y: filterRow.stacked ? readGroup.implicitHeight + Theme.spacingS : 0

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    text: "Participated"
                }
                DButtonGroup {
                    id: participationFilterSegments

                    buttonHeight: GitHubConstants.popoutFilterSegmentHeightPx
                    buttonPadding: Theme.spacingXS
                    checkEnabled: false
                    currentIndex: ["yes", "no", "both"].indexOf(panel.participationFilter)
                    minButtonWidth: Theme.fontSizeSmall * 3
                    model: ["Yes", "No", "Both"]
                    objectName: "participationFilterControl"
                    selectedColor: Theme.withAlpha(Theme.primary, GitHubConstants.filterSelectionOpacity)
                    selectedContentColor: Theme.primary
                    size: "small"
                    unselectedColor: Theme.nestedSurface
                    unselectedContentColor: Theme.surfaceVariantText

                    onSelectionChanged: function (index, selected) {
                        if (selected)
                            panel.participationFilterChangedByUser(["yes", "no", "both"][index]);
                    }
                }
            }
        }
    }

    // =========================================================================
    //  STATES
    // =========================================================================

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingM
        visible: !panel.tokenConfigured

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            name: "vpn_key"
            size: 46
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
            text: "GitHub token required"
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            text: "Open Settings -> GitHub Inbox and add a classic token"
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingS
        visible: panel.tokenConfigured && panel.hasBlockingError
        width: parent.width - Theme.spacingXL

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.error
            name: "error_outline"
            size: 42
        }
        StyledText {
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            text: panel.errorMessage
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingM
        visible: panel.tokenConfigured && !panel.hasBlockingError && !panel.hasDisplayedMessages && panel.isLoading

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.primary
            name: "hourglass_top"
            size: 42
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: "Loading messages..."
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingM
        visible: panel.tokenConfigured && !panel.hasBlockingError && !panel.hasDisplayedMessages && !panel.isLoading

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            name: "notifications_none"
            size: 48
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
            text: "No messages"
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: "Your GitHub inbox is clear"
        }
    }
}
