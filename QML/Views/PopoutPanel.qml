// PopoutPanel.qml - Popup content for GitHub inbox messages list
//
// Pure visual component.  All filtering, grouping and expanded-state
// management lives in InboxGroupModel.

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
    property bool isOperating: false
    property string errorMessage: ""
    property real headerOffset: 0
    property int titleLines: 2
    property int groupItemLimit: 25
    property var expandedReposState: ({ [Constants.expandedStateDefaultKey]: true })
    property var authorsByThread: ({})
    property bool showAuthorInfo: true

    // -- Actions --------------------------------------------------------------
    signal refreshNow()
    signal markAllRead()
    signal markRepoDone(string repositoryFullName)
    signal markThreadRead(string threadId)
    signal markThreadUnread(string threadId)
    signal markThreadDone(string threadId)
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)
    signal closePopout()
    signal persistExpandedRepos(var state)

    property bool anyBusy: isLoading || isOperating

    // -- Model ----------------------------------------------------------------
    InboxGroupModel {
        id: groupModel
        messages: panel.messages
        groupItemLimit: panel.groupItemLimit
        expandedReposState: panel.expandedReposState
        onPersistExpandedRepos: function(state) { panel.persistExpandedRepos(state) }
    }

    // =========================================================================
    //  HEADER HOVER BUTTONS
    // =========================================================================

    MouseArea {
        id: headerHoverArea
        x: 0
        width: parent.width
        y: -panel.headerOffset
        height: panel.headerOffset
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 100
    }

    Row {
        id: headerButtons
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        y: -panel.headerOffset + Theme.spacingS
        spacing: Constants.popoutHeaderButtonSpacingPx
        visible: headerHoverArea.containsMouse
                 || expandAllArea.containsMouse
                 || collapseAllArea.containsMouse
                 || refreshAllArea.containsMouse
                 || markAllArea.containsMouse
                 || closeArea.containsMouse
        z: 101
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Constants.popoutHeaderFadeDurationMs }
        }

        Rectangle {
            width: Constants.popoutHeaderButtonSizePx
            height: Constants.popoutHeaderButtonSizePx
            radius: Constants.popoutHeaderButtonRadiusPx
            color: expandAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.popoutHeaderButtonBackgroundOpacity)

            MouseArea {
                id: expandAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                onClicked: groupModel.expandAllGroups()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "unfold_more"
                size: Constants.popoutHeaderButtonIconSizePx
                color: Theme.surfaceText
            }
        }

        Rectangle {
            width: Constants.popoutHeaderButtonSizePx
            height: Constants.popoutHeaderButtonSizePx
            radius: Constants.popoutHeaderButtonRadiusPx
            color: collapseAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.popoutHeaderButtonBackgroundOpacity)

            MouseArea {
                id: collapseAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                onClicked: groupModel.collapseAllGroups()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "unfold_less"
                size: Constants.popoutHeaderButtonIconSizePx
                color: Theme.surfaceText
            }
        }

        // -- Refresh ---------------------------------------------------
        Rectangle {
            width: Constants.popoutHeaderButtonSizePx
            height: Constants.popoutHeaderButtonSizePx
            radius: Constants.popoutHeaderButtonRadiusPx
            color: refreshAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.popoutHeaderButtonBackgroundOpacity)

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
                size: Constants.popoutHeaderButtonIconSizePx
                color: panel.anyBusy ? Theme.primary : Theme.surfaceText

                RotationAnimation on rotation {
                    running: panel.anyBusy
                    from: 0
                    to: 360
                    duration: Constants.popoutRefreshIconSpinDurationMs
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
        }

        // -- Mark all as read -----------------------------------------
        Rectangle {
            width: Constants.popoutHeaderButtonSizePx
            height: Constants.popoutHeaderButtonSizePx
            radius: Constants.popoutHeaderButtonRadiusPx
            visible: panel.tokenConfigured && panel.unreadCount > 0
            color: markAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.popoutHeaderButtonBackgroundOpacity)

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
                size: Constants.popoutHeaderButtonIconSizePx
                color: Theme.surfaceText
            }
        }

        // -- Close ----------------------------------------------------
        Rectangle {
            width: Constants.popoutHeaderButtonSizePx
            height: Constants.popoutHeaderButtonSizePx
            radius: Constants.popoutHeaderButtonRadiusPx
            color: closeArea.containsMouse
                   ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, Constants.popoutHeaderButtonHoverTintOpacity)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.popoutHeaderButtonBackgroundOpacity)

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
                size: Constants.popoutHeaderButtonIconSizePx
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
        anchors.right: scrollIndicator.visible ? scrollIndicator.left : parent.right
        anchors.top: parent.top
        anchors.bottom: filterBar.visible ? filterBar.top : parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: groupsColumn.implicitHeight
        visible: panel.tokenConfigured
                 && panel.errorMessage === ""
                 && (groupModel.filteredMessages.length > 0 || panel.isLoading)

        Column {
            id: groupsColumn
            width: groupedFlick.width
            spacing: Theme.spacingS

            Repeater {
                model: groupModel.groupedMessages

                delegate: InboxMessageGroup {
                    width: groupsColumn.width
                    groupData: modelData
                    expanded: groupModel.isRepoExpanded(modelData.repository)
                    authorsByThread: panel.authorsByThread
                    showAuthorInfo: panel.showAuthorInfo
                    isBusy: panel.anyBusy
                    titleLines: panel.titleLines
                    onToggleExpanded: groupModel.toggleRepo(modelData.repository)
                    onMarkRepoDone: panel.markRepoDone(modelData.repository)
                    onMarkThreadRead: function(threadId) { panel.markThreadRead(threadId) }
                    onMarkThreadUnread: function(threadId) { panel.markThreadUnread(threadId) }
                    onMarkThreadDone: function(threadId) { panel.markThreadDone(threadId) }
                    onRequestThreadAuthors: function(threadId, subjectApiUrl, subjectType) {
                        panel.requestThreadAuthors(threadId, subjectApiUrl, subjectType)
                    }
                }
            }
        }
    }

    Item {
        id: filterBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: panel.tokenConfigured && panel.errorMessage === ""
        height: filterRow.implicitHeight
        z: 5

        Row {
            id: filterRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingXS
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            property int groupGap: Theme.spacingM
            property int segmentWidth: {
                var available = width - readLabel.width - participatedLabel.width - groupGap - filterRow.spacing * 4
                var fit = Math.floor(available / 2)
                return Math.max(Constants.popoutFilterSegmentMinWidthPx, Math.min(Constants.popoutFilterSegmentMaxWidthPx, fit))
            }

            StyledText {
                id: readLabel
                width: Constants.popoutFilterReadLabelWidthPx
                text: "Read"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: filterRow.segmentWidth
                height: Constants.popoutFilterSegmentHeightPx
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.popoutFilterBackgroundOpacity)
                border.width: 1
                border.color: Theme.outlineVariant

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
                            color: groupModel.readFilter === modelData.value
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.popoutFilterActiveTintOpacity)
                                   : "transparent"
                            border.width: groupModel.readFilter === modelData.value ? 1 : 0
                            border.color: Theme.primary

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: groupModel.readFilter = modelData.value
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: groupModel.readFilter === modelData.value ? Font.DemiBold : Font.Normal
                                color: groupModel.readFilter === modelData.value ? Theme.primary : Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
            Item {
                width: filterRow.groupGap
                height: 1
            }

            StyledText {
                id: participatedLabel
                width: Constants.popoutFilterParticipatedLabelWidthPx
                text: "Participated"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: filterRow.segmentWidth
                height: Constants.popoutFilterSegmentHeightPx
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.popoutFilterBackgroundOpacity)
                border.width: 1
                border.color: Theme.outlineVariant

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
                            color: groupModel.participationFilter === modelData.value
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.popoutFilterActiveTintOpacity)
                                   : "transparent"
                            border.width: groupModel.participationFilter === modelData.value ? 1 : 0
                            border.color: Theme.primary

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: groupModel.participationFilter = modelData.value
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: groupModel.participationFilter === modelData.value ? Font.DemiBold : Font.Normal
                                color: groupModel.participationFilter === modelData.value ? Theme.primary : Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: scrollIndicator
        visible: groupedFlick.visible && groupedFlick.contentHeight > groupedFlick.height
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: filterBar.visible ? filterBar.top : parent.bottom
        width: Constants.popoutScrollIndicatorWidthPx
        color: "transparent"

        Rectangle {
            width: parent.width
            radius: Constants.popoutScrollIndicatorRadiusPx
            color: Theme.outlineVariant
            opacity: groupedFlick.moving ? Constants.popoutScrollIndicatorActiveOpacity : Constants.popoutScrollIndicatorIdleOpacity

            property real ratio: groupedFlick.height / groupedFlick.contentHeight
            height: Math.max(Constants.popoutScrollIndicatorMinHeightPx, parent.height * ratio)
            y: groupedFlick.contentHeight > groupedFlick.height
               ? (groupedFlick.contentY / (groupedFlick.contentHeight - groupedFlick.height)) * (parent.height - height)
               : 0

            Behavior on opacity { NumberAnimation { duration: Constants.popoutScrollIndicatorFadeDurationMs } }
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
        visible: panel.tokenConfigured && panel.errorMessage !== "" && !panel.isLoading
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
                 && panel.errorMessage === ""
                 && groupModel.filteredMessages.length === 0
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
                 && panel.errorMessage === ""
                 && groupModel.filteredMessages.length === 0
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
