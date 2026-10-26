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

    property bool _headerHovered: headerHoverArea.containsMouse || expandAllArea.containsMouse || collapseAllArea.containsMouse || refreshAllArea.containsMouse || markAllArea.containsMouse || closeArea.containsMouse
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

        Rectangle {
            color: expandAllArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: width / 2
            visible: panel._headerHovered
            width: GitHubConstants.popoutHeaderButtonSizePx

            MouseArea {
                id: expandAllArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                hoverEnabled: true

                onClicked: panel.activeGroupingModel().expandAllGroups()
            }
            DIcon {
                anchors.centerIn: parent
                color: Theme.surfaceText
                name: "unfold_more"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
            }
        }
        Rectangle {
            color: collapseAllArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: width / 2
            visible: panel._headerHovered
            width: GitHubConstants.popoutHeaderButtonSizePx

            MouseArea {
                id: collapseAllArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                hoverEnabled: true

                onClicked: panel.activeGroupingModel().collapseAllGroups()
            }
            DIcon {
                anchors.centerIn: parent
                color: Theme.surfaceText
                name: "unfold_less"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
            }
        }

        // -- Refresh ---------------------------------------------------
        Rectangle {
            color: refreshAllArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: width / 2
            width: GitHubConstants.popoutHeaderButtonSizePx

            MouseArea {
                id: refreshAllArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !panel.anyBusy && panel.tokenConfigured
                hoverEnabled: true

                onClicked: panel.refreshNow()
            }
            DIcon {
                id: refreshIcon

                anchors.centerIn: parent
                color: panel.hasError ? Theme.error : (panel.anyBusy ? Theme.primary : Theme.surfaceText)
                name: "refresh"
                size: GitHubConstants.popoutHeaderButtonIconSizePx

                RotationAnimation {
                    duration: GitHubConstants.popoutRefreshIconSpinDurationMs
                    from: 0
                    loops: Animation.Infinite
                    property: "rotation"
                    running: panel.anyBusy
                    target: refreshIcon
                    to: 360
                }
                Connections {
                    // Handle this workflow result at the ownership boundary and preserve failure visibility.
                    function onAnyBusyChanged() {
                        if (!panel.anyBusy)
                            refreshIcon.rotation = 0;
                    }

                    target: panel
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                border.color: Theme.nestedSurface
                border.width: 1
                color: Theme.error
                height: 12
                radius: Math.max(0, Math.min(width / 2, Theme.cornerRadius + GitHubConstants.popoutErrorBadgeRadiusDelta))
                visible: panel.hasError && !panel.anyBusy
                width: 12

                StyledText {
                    anchors.centerIn: parent
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall + GitHubConstants.popoutErrorBadgeFontSizeDelta
                    font.weight: Font.Bold
                    text: "!"
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.bottom
                anchors.topMargin: Theme.spacingXS
                border.color: Theme.outlineMedium
                border.width: 1
                color: Theme.surfaceContainerHighest
                height: refreshTooltipTextItem.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius
                visible: refreshAllArea.containsMouse && panel.refreshTooltipText !== ""
                width: Math.min(360, refreshTooltipTextItem.implicitWidth + Theme.spacingS * 2)
                z: 120

                StyledText {
                    id: refreshTooltipTextItem

                    anchors.centerIn: parent
                    color: panel.hasError ? Theme.error : Theme.surfaceVariantText
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                    maximumLineCount: 3
                    text: panel.refreshTooltipText
                    width: parent.width - Theme.spacingS * 2
                    wrapMode: Text.WordWrap
                }
            }
        }

        // -- Mark all as read -----------------------------------------
        Rectangle {
            color: markAllArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: width / 2
            visible: panel._headerHovered && panel.tokenConfigured && panel.unreadCount > 0
            width: GitHubConstants.popoutHeaderButtonSizePx

            MouseArea {
                id: markAllArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !panel.anyBusy
                hoverEnabled: true

                onClicked: panel.markAllRead()
            }
            DIcon {
                anchors.centerIn: parent
                color: Theme.surfaceText
                name: "done_all"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
            }
        }

        // -- Close ----------------------------------------------------
        Rectangle {
            color: closeArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: width / 2
            visible: panel._headerHovered
            width: GitHubConstants.popoutHeaderButtonSizePx

            MouseArea {
                id: closeArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                onClicked: panel.closePopout()
            }
            DIcon {
                anchors.centerIn: parent
                color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
                name: "close"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
            }
        }
    }

    // =========================================================================
    //  GROUPED INBOX MESSAGE LIST
    // =========================================================================

    Flickable {
        id: groupedFlick

        anchors.bottom: filterBar.visible ? filterBar.top : parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: scrollGutter.visible ? GitHubConstants.popoutScrollIndicatorWidthPx + Theme.spacingS + GitHubConstants.popoutScrollRightEdgeInsetDelta : 0
        anchors.top: parent.top
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        contentHeight: groupsColumn.implicitHeight
        contentWidth: width
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

            property int segmentWidth: {
                let available = (width - readLabel.implicitWidth - participatedLabel.implicitWidth - Theme.spacingXS * 4) / 2;
                return Math.max(GitHubConstants.popoutFilterSegmentMinWidthPx, Math.min(GitHubConstants.popoutFilterSegmentMaxWidthPx, Math.floor(available)));
            }

            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingXS
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingS + GitHubConstants.popoutFilterBarVerticalPaddingDelta
            implicitHeight: GitHubConstants.popoutFilterSegmentHeightPx

            // -- Read filter (left-aligned) -----------------------------------
            Row {
                id: readGroup

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    id: readLabel

                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    text: "Read"
                }
                Rectangle {
                    border.color: Theme.outlineMedium
                    border.width: 1
                    color: Theme.nestedSurface
                    height: GitHubConstants.popoutFilterSegmentHeightPx
                    radius: Theme.cornerRadius
                    width: filterRow.segmentWidth

                    Row {
                        id: readFilterSegments

                        anchors.fill: parent
                        anchors.margins: 0
                        spacing: Math.max(1, (Theme.spacingXXS || 0) + GitHubConstants.popoutFilterSegmentSpacingDelta)

                        Repeater {
                            model: [
                                {
                                    label: "Yes",
                                    value: "yes"
                                },
                                {
                                    label: "No",
                                    value: "no"
                                },
                                {
                                    label: "Both",
                                    value: "both"
                                }
                            ]

                            delegate: Rectangle {
                                id: readFilterOption

                                required property var modelData

                                color: panel.readFilter === readFilterOption.modelData.value ? Theme.withAlpha(Theme.primary, GitHubConstants.popoutFilterActiveTintOpacity) : "transparent"
                                height: parent.height
                                radius: Theme.cornerRadius
                                width: (readFilterSegments.width - readFilterSegments.spacing * 2) / 3

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: panel.readFilterChangedByUser(readFilterOption.modelData.value)
                                }
                                StyledText {
                                    anchors.centerIn: parent
                                    color: panel.readFilter === readFilterOption.modelData.value ? Theme.primary : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: panel.readFilter === readFilterOption.modelData.value ? Font.DemiBold : Font.Normal
                                    text: readFilterOption.modelData.label
                                }
                            }
                        }
                    }
                }
            }

            // -- Participated filter (right-aligned) --------------------------
            Row {
                id: participatedGroup

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    id: participatedLabel

                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    text: "Participated"
                }
                Rectangle {
                    border.color: Theme.outlineMedium
                    border.width: 1
                    color: Theme.nestedSurface
                    height: GitHubConstants.popoutFilterSegmentHeightPx
                    radius: Theme.cornerRadius
                    width: filterRow.segmentWidth

                    Row {
                        id: participationFilterSegments

                        anchors.fill: parent
                        anchors.margins: 0
                        spacing: Math.max(1, (Theme.spacingXXS || 0) + GitHubConstants.popoutFilterSegmentSpacingDelta)

                        Repeater {
                            model: [
                                {
                                    label: "Yes",
                                    value: "yes"
                                },
                                {
                                    label: "No",
                                    value: "no"
                                },
                                {
                                    label: "Both",
                                    value: "both"
                                }
                            ]

                            delegate: Rectangle {
                                id: participationFilterOption

                                required property var modelData

                                color: panel.participationFilter === participationFilterOption.modelData.value ? Theme.withAlpha(Theme.primary, GitHubConstants.popoutFilterActiveTintOpacity) : "transparent"
                                height: parent.height
                                radius: Theme.cornerRadius
                                width: (participationFilterSegments.width - participationFilterSegments.spacing * 2) / 3

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: panel.participationFilterChangedByUser(participationFilterOption.modelData.value)
                                }
                                StyledText {
                                    anchors.centerIn: parent
                                    color: panel.participationFilter === participationFilterOption.modelData.value ? Theme.primary : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: panel.participationFilter === participationFilterOption.modelData.value ? Font.DemiBold : Font.Normal
                                    text: participationFilterOption.modelData.label
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Item {
        id: scrollGutter

        anchors.bottom: filterBar.visible ? filterBar.top : parent.bottom
        anchors.right: parent.right
        // PluginPopout adds Theme.spacingS around its content. Move the track
        // into that shell inset, leaving the requested gap at the popup edge.
        // Accounting for the indicator width above preserves equal outer gaps.
        anchors.rightMargin: Theme.spacingS + GitHubConstants.popoutScrollRightEdgeInsetDelta - Theme.spacingS
        anchors.top: groupedFlick.top
        visible: groupedFlick.visible && groupedFlick.contentHeight > groupedFlick.height
        width: GitHubConstants.popoutScrollGutterWidthPx
        z: 10

        Rectangle {
            id: scrollThumb

            property real ratio: groupedFlick.height / groupedFlick.contentHeight

            anchors.right: parent.right
            color: Theme.outlineVariant
            height: Math.max(GitHubConstants.popoutScrollIndicatorMinHeightPx, parent.height * ratio)
            opacity: groupedFlick.moving || scrollDragArea.pressed || scrollDragArea.containsMouse ? GitHubConstants.popoutScrollIndicatorActiveOpacity : GitHubConstants.popoutScrollIndicatorIdleOpacity
            radius: Math.max(0, Math.min(GitHubConstants.popoutScrollIndicatorWidthPx / 2, Theme.cornerRadius + GitHubConstants.popoutScrollIndicatorRadiusDelta))
            width: GitHubConstants.popoutScrollIndicatorWidthPx
            y: groupedFlick.contentHeight > groupedFlick.height ? (groupedFlick.contentY / (groupedFlick.contentHeight - groupedFlick.height)) * (parent.height - height) : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: GitHubConstants.popoutScrollIndicatorFadeDurationMs
                }
            }
        }
        MouseArea {
            id: scrollDragArea

            property real pressOffsetY: 0

            // Map scrollbar dragging into the available scroll range without exceeding its bounds.
            function scrollToMouse(mouseY) {
                let trackHeight = scrollGutter.height - scrollThumb.height;
                let maxContentY = groupedFlick.contentHeight - groupedFlick.height;
                if (trackHeight <= 0 || maxContentY <= 0) {
                    groupedFlick.contentY = 0;
                    return;
                }

                let thumbY = Math.max(0, Math.min(trackHeight, mouseY - pressOffsetY));
                groupedFlick.contentY = Math.max(0, Math.min(maxContentY, (thumbY / trackHeight) * maxContentY));
            }

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            onPositionChanged: function (mouse) {
                if (pressed)
                    scrollToMouse(mouse.y);
            }
            onPressed: function (mouse) {
                if (mouse.y >= scrollThumb.y && mouse.y <= scrollThumb.y + scrollThumb.height)
                    pressOffsetY = mouse.y - scrollThumb.y;
                else
                    pressOffsetY = scrollThumb.height / 2;

                scrollToMouse(mouse.y);
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
