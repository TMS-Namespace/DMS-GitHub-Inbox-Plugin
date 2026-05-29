// PopoutPanel.qml - Popup content for GitHub inbox messages list
//
// Pure visual component.  Filtering, grouping and expanded-state
// management lives in the grouping models.

import QtQuick
import qs.Common
import qs.Widgets
import ".."

Item {
    id: panel

    // -- Inputs ---------------------------------------------------------------
    property var messages: []
    property int unreadCount: 0
    property bool tokenConfigured: false
    property bool isLoading: false
    property bool isAuthorFetching: false
    property bool isOperating: false
    property bool isDownloadingAvatars: false
    property string errorMessage: ""
    property real headerOffset: 0
    property real headerHoverHeight: headerOffset
    property real headerHoverBottomInset: 0
    property int titleLines: 2
    property int groupItemLimit: 25
    property var expandedReposState: ({ [GitHubConstants.expandedStateDefaultKey]: true })
    property var expandedDateGroupsState: ({ [GitHubConstants.expandedStateDefaultKey]: true })
    property var authorsByThread: ({})
    property bool showAuthorInfo: true
    property string groupingMode: "repo"              // repo | date
    property string readFilter: "both"                // yes | no | both
    property string participationFilter: "both"       // yes | no | both

    // -- Actions --------------------------------------------------------------
    signal refreshNow()
    signal markAllRead()
    signal markRepoRead(var items)
    signal markRepoDone(var items)
    signal markThreadRead(string threadId)
    signal markThreadReadAfterOpen(string threadId)
    signal markThreadUnread(string threadId)
    signal markThreadDone(string threadId)
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)
    signal closePopout()
    signal persistExpandedRepos(var state)
    signal persistExpandedDateGroups(var state)
    signal markDateGroupRead(var items)
    signal markDateGroupDone(var items)

    property bool hasError: errorMessage !== ""
    property bool hasBlockingError: hasError && messages.length === 0 && !isLoading
    property bool isRefreshBusy: isLoading || isAuthorFetching || isDownloadingAvatars || isOperating
    property bool anyBusy: isRefreshBusy
    property string refreshTooltipText: {
        if (panel.anyBusy)
            return "Refresh in progress"
        if (panel.hasError)
            return panel.errorMessage || "Last refresh failed"
        return "Refresh GitHub inbox"
    }
    property bool _headerHovered: headerHoverArea.containsMouse
                                  || expandAllArea.containsMouse
                                  || collapseAllArea.containsMouse
                                  || refreshAllArea.containsMouse
                                  || markAllArea.containsMouse
                                  || closeArea.containsMouse

    property bool hasDisplayedMessages: groupingMode === "date"
                                        ? dateGrouping.hasDisplayedMessages
                                        : repoGrouping.hasDisplayedMessages

    function activeGroupingModel() {
        return groupingMode === "date" ? dateGrouping : repoGrouping
    }

    // -- Models ---------------------------------------------------------------
    RepoGroupingModel {
        id: repoGrouping
        messages: panel.messages
        groupItemLimit: panel.groupItemLimit
        expandedGroupsState: panel.expandedReposState
        readFilter: panel.readFilter
        participationFilter: panel.participationFilter
        onPersistExpandedGroups: function(state) { panel.persistExpandedRepos(state) }
    }

    DateGroupingModel {
        id: dateGrouping
        messages: panel.messages
        groupItemLimit: panel.groupItemLimit
        readFilter: panel.readFilter
        participationFilter: panel.participationFilter
        expandedGroupsState: panel.expandedDateGroupsState
        onPersistExpandedGroups: function(state) { panel.persistExpandedDateGroups(state) }
    }

    // =========================================================================
    //  HEADER HOVER BUTTONS
    // =========================================================================

    MouseArea {
        id: headerHoverArea
        x: 0
        width: parent.width
        y: -panel.headerHoverBottomInset - panel.headerHoverHeight
        height: panel.headerHoverHeight
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 100
    }

    Row {
        id: headerButtons
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        y: -panel.headerOffset + Theme.spacingXS
        spacing: GitHubConstants.popoutHeaderButtonSpacingPx
        visible: panel.anyBusy || panel.hasError || panel._headerHovered
        z: 101
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: GitHubConstants.popoutHeaderFadeDurationMs }
        }

        Rectangle {
            visible: panel._headerHovered
            width: GitHubConstants.popoutHeaderButtonSizePx
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: GitHubConstants.popoutHeaderButtonRadiusPx
            color: expandAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)

            MouseArea {
                id: expandAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                onClicked: panel.activeGroupingModel().expandAllGroups()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "unfold_more"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
                color: Theme.surfaceText
            }
        }

        Rectangle {
            visible: panel._headerHovered
            width: GitHubConstants.popoutHeaderButtonSizePx
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: GitHubConstants.popoutHeaderButtonRadiusPx
            color: collapseAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)

            MouseArea {
                id: collapseAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                onClicked: panel.activeGroupingModel().collapseAllGroups()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "unfold_less"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
                color: Theme.surfaceText
            }
        }

        // -- Refresh ---------------------------------------------------
        Rectangle {
            width: GitHubConstants.popoutHeaderButtonSizePx
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: GitHubConstants.popoutHeaderButtonRadiusPx
            color: refreshAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)

            MouseArea {
                id: refreshAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !panel.anyBusy && panel.tokenConfigured
                onClicked: panel.refreshNow()
            }

            DankIcon {
                id: refreshIcon
                anchors.centerIn: parent
                name: "refresh"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
                color: panel.hasError ? Theme.error : (panel.anyBusy ? Theme.primary : Theme.surfaceText)

                RotationAnimation {
                    target: refreshIcon
                    property: "rotation"
                    running: panel.anyBusy
                    from: 0
                    to: 360
                    duration: GitHubConstants.popoutRefreshIconSpinDurationMs
                    loops: Animation.Infinite
                }

                Connections {
                    target: panel
                    function onAnyBusyChanged() {
                        if (!panel.anyBusy)
                            refreshIcon.rotation = 0
                    }
                }
            }

            Rectangle {
                visible: panel.hasError && !panel.anyBusy
                width: 12
                height: 12
                radius: 6
                anchors.right: parent.right
                anchors.top: parent.top
                color: Theme.error
                border.width: 1
                border.color: Theme.nestedSurface

                StyledText {
                    anchors.centerIn: parent
                    text: "!"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }
            }

            Rectangle {
                visible: refreshAllArea.containsMouse && panel.refreshTooltipText !== ""
                anchors.right: parent.right
                anchors.top: parent.bottom
                anchors.topMargin: Theme.spacingXS
                width: Math.min(360, refreshTooltipTextItem.implicitWidth + Theme.spacingS * 2)
                height: refreshTooltipTextItem.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHighest
                border.width: 1
                border.color: Theme.outlineMedium
                z: 120

                StyledText {
                    id: refreshTooltipTextItem
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingS * 2
                    text: panel.refreshTooltipText
                    font.pixelSize: GitHubConstants.messageMetadataFontSizePx
                    color: panel.hasError ? Theme.error : Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }

        // -- Mark all as read -----------------------------------------
        Rectangle {
            width: GitHubConstants.popoutHeaderButtonSizePx
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: GitHubConstants.popoutHeaderButtonRadiusPx
            visible: panel._headerHovered && panel.tokenConfigured && panel.unreadCount > 0
            color: markAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)

            MouseArea {
                id: markAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !panel.anyBusy
                onClicked: panel.markAllRead()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "done_all"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
                color: Theme.surfaceText
            }
        }

        // -- Close ----------------------------------------------------
        Rectangle {
            visible: panel._headerHovered
            width: GitHubConstants.popoutHeaderButtonSizePx
            height: GitHubConstants.popoutHeaderButtonSizePx
            radius: GitHubConstants.popoutHeaderButtonRadiusPx
            color: closeArea.containsMouse
                   ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, GitHubConstants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.popoutHeaderButtonBackgroundOpacity)

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.closePopout()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "close"
                size: GitHubConstants.popoutHeaderButtonIconSizePx
                color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
            }
        }
    }

    // =========================================================================
    //  GROUPED INBOX MESSAGE LIST
    // =========================================================================

    Flickable {
        id: groupedFlick
        anchors.left: parent.left
        anchors.right: scrollGutter.visible ? scrollGutter.left : parent.right
        anchors.rightMargin: scrollGutter.visible ? GitHubConstants.popoutScrollContentGapPx : 0
        anchors.top: parent.top
        anchors.bottom: filterBar.visible ? filterBar.top : parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: groupsColumn.implicitHeight
        visible: panel.tokenConfigured
                 && !panel.hasBlockingError
                 && (panel.hasDisplayedMessages || panel.isLoading)

        Column {
            id: groupsColumn
            width: groupedFlick.width
            spacing: Theme.spacingS

            RepoGroupingView {
                width: groupsColumn.width
                visible: panel.groupingMode === "repo"
                height: visible ? implicitHeight : 0
                groups: repoGrouping.groups
                groupingModel: repoGrouping
                authorsByThread: panel.authorsByThread
                showAuthorInfo: panel.showAuthorInfo
                isBusy: panel.anyBusy
                titleLines: panel.titleLines
                onMarkRepoRead: function(items) { panel.markRepoRead(items) }
                onMarkRepoDone: function(items) { panel.markRepoDone(items) }
                onMarkThreadRead: function(threadId) { panel.markThreadRead(threadId) }
                onMarkThreadReadAfterOpen: function(threadId) { panel.markThreadReadAfterOpen(threadId) }
                onMarkThreadUnread: function(threadId) { panel.markThreadUnread(threadId) }
                onMarkThreadDone: function(threadId) { panel.markThreadDone(threadId) }
                onRequestThreadAuthors: function(threadId, subjectApiUrl, subjectType) {
                    panel.requestThreadAuthors(threadId, subjectApiUrl, subjectType)
                }
                onClosePopout: panel.closePopout()
            }

            DateGroupingView {
                width: groupsColumn.width
                visible: panel.groupingMode === "date"
                height: visible ? implicitHeight : 0
                groups: dateGrouping.groups
                groupingModel: dateGrouping
                authorsByThread: panel.authorsByThread
                showAuthorInfo: panel.showAuthorInfo
                isBusy: panel.anyBusy
                titleLines: panel.titleLines
                onMarkGroupRead: function(items) { panel.markDateGroupRead(items) }
                onMarkGroupDone: function(items) { panel.markDateGroupDone(items) }
                onMarkThreadRead: function(threadId) { panel.markThreadRead(threadId) }
                onMarkThreadReadAfterOpen: function(threadId) { panel.markThreadReadAfterOpen(threadId) }
                onMarkThreadUnread: function(threadId) { panel.markThreadUnread(threadId) }
                onMarkThreadDone: function(threadId) { panel.markThreadDone(threadId) }
                onRequestThreadAuthors: function(threadId, subjectApiUrl, subjectType) {
                    panel.requestThreadAuthors(threadId, subjectApiUrl, subjectType)
                }
                onClosePopout: panel.closePopout()
            }
        }
    }

    Item {
        id: filterBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: panel.tokenConfigured && !panel.hasBlockingError
        height: filterRow.implicitHeight + GitHubConstants.popoutFilterBarVerticalPaddingPx
        z: 5

        Item {
            id: filterRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingXS
            anchors.rightMargin: Theme.spacingXS
            anchors.top: parent.top
            anchors.topMargin: GitHubConstants.popoutFilterBarVerticalPaddingPx
            implicitHeight: GitHubConstants.popoutFilterSegmentHeightPx

            property int segmentWidth: {
                var available = (width - readLabel.implicitWidth - participatedLabel.implicitWidth - Theme.spacingXS * 4) / 2
                return Math.max(GitHubConstants.popoutFilterSegmentMinWidthPx, Math.min(GitHubConstants.popoutFilterSegmentMaxWidthPx, Math.floor(available)))
            }

            // -- Read filter (left-aligned) -----------------------------------
            Row {
                id: readGroup
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    id: readLabel
                    text: "Read"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: filterRow.segmentWidth
                    height: GitHubConstants.popoutFilterSegmentHeightPx
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.width: 1
                    border.color: Theme.outlineMedium

                    Row {
                        anchors.fill: parent
                        anchors.margins: 0
                        spacing: 1

                        Repeater {
                            model: [
                                { label: "Yes", value: "yes" },
                                { label: "No", value: "no" },
                                { label: "Both", value: "both" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                width: (parent.width - 2) / 3
                                height: parent.height
                                radius: Theme.cornerRadius
                                color: panel.readFilter === modelData.value
                                       ? Theme.withAlpha(Theme.primary, GitHubConstants.popoutFilterActiveTintOpacity)
                                       : "transparent"

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.readFilter = modelData.value
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: panel.readFilter === modelData.value ? Font.DemiBold : Font.Normal
                                    color: panel.readFilter === modelData.value ? Theme.primary : Theme.surfaceVariantText
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
                    text: "Participated"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: filterRow.segmentWidth
                    height: GitHubConstants.popoutFilterSegmentHeightPx
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.width: 1
                    border.color: Theme.outlineMedium

                    Row {
                        anchors.fill: parent
                        anchors.margins: 0
                        spacing: 1

                        Repeater {
                            model: [
                                { label: "Yes", value: "yes" },
                                { label: "No", value: "no" },
                                { label: "Both", value: "both" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                width: (parent.width - 2) / 3
                                height: parent.height
                                radius: Theme.cornerRadius
                                color: panel.participationFilter === modelData.value
                                       ? Theme.withAlpha(Theme.primary, GitHubConstants.popoutFilterActiveTintOpacity)
                                       : "transparent"

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.participationFilter = modelData.value
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: panel.participationFilter === modelData.value ? Font.DemiBold : Font.Normal
                                    color: panel.participationFilter === modelData.value ? Theme.primary : Theme.surfaceVariantText
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
        visible: groupedFlick.visible && groupedFlick.contentHeight > groupedFlick.height
        anchors.right: parent.right
        anchors.top: groupedFlick.top
        anchors.bottom: filterBar.visible ? filterBar.top : parent.bottom
        width: GitHubConstants.popoutScrollGutterWidthPx
        z: 10

        Rectangle {
            id: scrollThumb
            width: GitHubConstants.popoutScrollIndicatorWidthPx
            radius: GitHubConstants.popoutScrollIndicatorRadiusPx
            color: Theme.outlineVariant
            opacity: groupedFlick.moving || scrollDragArea.pressed || scrollDragArea.containsMouse
                     ? GitHubConstants.popoutScrollIndicatorActiveOpacity
                     : GitHubConstants.popoutScrollIndicatorIdleOpacity
            anchors.horizontalCenter: parent.horizontalCenter

            property real ratio: groupedFlick.height / groupedFlick.contentHeight
            height: Math.max(GitHubConstants.popoutScrollIndicatorMinHeightPx, parent.height * ratio)
            y: groupedFlick.contentHeight > groupedFlick.height
               ? (groupedFlick.contentY / (groupedFlick.contentHeight - groupedFlick.height)) * (parent.height - height)
               : 0

            Behavior on opacity { NumberAnimation { duration: GitHubConstants.popoutScrollIndicatorFadeDurationMs } }
        }

        MouseArea {
            id: scrollDragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            property real pressOffsetY: 0

            function scrollToMouse(mouseY) {
                var trackHeight = scrollGutter.height - scrollThumb.height
                var maxContentY = groupedFlick.contentHeight - groupedFlick.height
                if (trackHeight <= 0 || maxContentY <= 0) {
                    groupedFlick.contentY = 0
                    return
                }

                var thumbY = Math.max(0, Math.min(trackHeight, mouseY - pressOffsetY))
                groupedFlick.contentY = Math.max(0, Math.min(maxContentY, (thumbY / trackHeight) * maxContentY))
            }

            onPressed: function(mouse) {
                if (mouse.y >= scrollThumb.y && mouse.y <= scrollThumb.y + scrollThumb.height)
                    pressOffsetY = mouse.y - scrollThumb.y
                else
                    pressOffsetY = scrollThumb.height / 2

                scrollToMouse(mouse.y)
            }

            onPositionChanged: function(mouse) {
                if (pressed)
                    scrollToMouse(mouse.y)
            }
        }
    }

    // =========================================================================
    //  STATES
    // =========================================================================

    Column {
        visible: !panel.tokenConfigured
        anchors.centerIn: parent
        spacing: Theme.spacingM

        DankIcon {
            name: "vpn_key"
            size: 46
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "GitHub token required"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "Open Settings -> GitHub Inbox and add a classic token"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Column {
        visible: panel.tokenConfigured && panel.hasBlockingError
        anchors.centerIn: parent
        spacing: Theme.spacingS
        width: parent.width - Theme.spacingXL

        DankIcon {
            name: "error_outline"
            size: 42
            color: Theme.error
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            width: parent.width
            text: panel.errorMessage
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Column {
        visible: panel.tokenConfigured
                 && !panel.hasBlockingError
                 && !panel.hasDisplayedMessages
                 && panel.isLoading
        anchors.centerIn: parent
        spacing: Theme.spacingM

        DankIcon {
            name: "hourglass_top"
            size: 42
            color: Theme.primary
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "Loading messages..."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Column {
        visible: panel.tokenConfigured
                 && !panel.hasBlockingError
                 && !panel.hasDisplayedMessages
                 && !panel.isLoading
        anchors.centerIn: parent
        spacing: Theme.spacingM

        DankIcon {
            name: "notifications_none"
            size: 48
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "No messages"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "Your GitHub inbox is clear"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
