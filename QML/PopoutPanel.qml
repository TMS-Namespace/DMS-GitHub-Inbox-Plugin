// PopoutPanel.qml - Popup content for GitHub notifications list

import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: panel

    // -- Inputs ---------------------------------------------------------------
    property var notifications: []
    property int unreadCount: 0
    property bool tokenConfigured: false
    property bool isLoading: false
    property bool isMutating: false
    property string errorMessage: ""
    property real headerOffset: 0
    property int titleLines: 2
    property int groupItemLimit: 25
    property var expandedReposState: ({ "__defaultExpanded": true })

    // -- Actions --------------------------------------------------------------
    signal refreshNow()
    signal markAllRead()
    signal markRepoRead(string repositoryFullName)
    signal markThreadRead(string threadId)
    signal markThreadUnread(string threadId)
    signal markThreadDone(string threadId)
    signal closePopout()
    signal persistExpandedRepos(var state)

    property bool anyBusy: isLoading || isMutating
    property var expandedRepos: ({})

    Component.onCompleted: {
        expandedRepos = normalizeExpandedState(expandedReposState)
    }

    onExpandedReposStateChanged: {
        expandedRepos = normalizeExpandedState(expandedReposState)
    }
    property string readFilter: "all"                 // unread | read | all
    property string participationFilter: "all"        // participated | not_participated | all

    property var filteredNotifications: {
        var result = []
        for (var index = 0; index < notifications.length; index++) {
            var item = notifications[index]
            var participated = !!item.participated

            if (readFilter === "unread" && !item.unread) continue
            if (readFilter === "read" && item.unread) continue

            if (participationFilter === "participated" && !participated) continue
            if (participationFilter === "not_participated" && participated) continue

            result.push(item)
        }
        return result
    }

    property var groupedNotifications: {
        var groupsByRepo = {}
        var repoOrder = []

        for (var index = 0; index < filteredNotifications.length; index++) {
            var item = filteredNotifications[index]
            var repo = item.repository || "Unknown repository"

            if (!groupsByRepo[repo]) {
                groupsByRepo[repo] = {
                    repository: repo,
                    unreadCount: 0,
                    items: []
                }
                repoOrder.push(repo)
            }

            if (groupsByRepo[repo].items.length >= groupItemLimit)
                continue

            groupsByRepo[repo].items.push(item)
            if (item.unread)
                groupsByRepo[repo].unreadCount++
        }

        var result = []
        for (var repoIndex = 0; repoIndex < repoOrder.length; repoIndex++)
            result.push(groupsByRepo[repoOrder[repoIndex]])
        return result
    }

    function normalizeExpandedState(state) {
        var next = {}
        var source = state || {}
        for (var key in source)
            next[key] = source[key]
        if (next.__defaultExpanded === undefined)
            next.__defaultExpanded = true
        return next
    }

    function defaultExpandedGroups() {
        return expandedRepos.__defaultExpanded !== false
    }

    function _persistExpandedState(state) {
        persistExpandedRepos(normalizeExpandedState(state))
    }

    function isRepoExpanded(repoName) {
        if (expandedRepos.hasOwnProperty(repoName))
            return expandedRepos[repoName] !== false
        return defaultExpandedGroups()
    }

    function toggleRepo(repoName) {
        var nextState = normalizeExpandedState(expandedRepos)
        var defaultState = nextState.__defaultExpanded !== false
        var nextValue = !isRepoExpanded(repoName)

        if (nextValue === defaultState)
            delete nextState[repoName]
        else
            nextState[repoName] = nextValue

        expandedRepos = nextState
        _persistExpandedState(nextState)
    }

    function expandAllGroups() {
        var nextState = { "__defaultExpanded": true }
        expandedRepos = nextState
        _persistExpandedState(nextState)
    }

    function collapseAllGroups() {
        var nextState = { "__defaultExpanded": false }
        expandedRepos = nextState
        _persistExpandedState(nextState)
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
        anchors.rightMargin: Theme.spacingS
        y: -panel.headerOffset + Theme.spacingS
        spacing: 6
        visible: headerHoverArea.containsMouse
                 || expandAllArea.containsMouse
                 || collapseAllArea.containsMouse
                 || refreshAllArea.containsMouse
                 || markAllArea.containsMouse
                 || closeArea.containsMouse
        z: 101
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }

        Rectangle {
            width: 28
            height: 28
            radius: 14
            color: expandAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

            MouseArea {
                id: expandAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                onClicked: panel.expandAllGroups()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "unfold_more"
                size: 18
                color: Theme.surfaceText
            }
        }

        Rectangle {
            width: 28
            height: 28
            radius: 14
            color: collapseAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

            MouseArea {
                id: collapseAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: panel.tokenConfigured
                onClicked: panel.collapseAllGroups()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "unfold_less"
                size: 18
                color: Theme.surfaceText
            }
        }

        // -- Refresh ---------------------------------------------------
        Rectangle {
            width: 28
            height: 28
            radius: 14
            color: refreshAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

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
                size: 18
                color: panel.anyBusy ? Theme.primary : Theme.surfaceText

                RotationAnimation on rotation {
                    running: panel.anyBusy
                    from: 0
                    to: 360
                    duration: 800
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
            width: 28
            height: 28
            radius: 14
            visible: panel.tokenConfigured && panel.unreadCount > 0
            color: markAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

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
                size: 18
                color: Theme.surfaceText
            }
        }

        // -- Close ----------------------------------------------------
        Rectangle {
            width: 28
            height: 28
            radius: 14
            color: closeArea.containsMouse
                   ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

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
                size: 18
                color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
            }
        }
    }

    // =========================================================================
    //  GROUPED NOTIFICATION LIST
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
                 && (panel.filteredNotifications.length > 0 || panel.isLoading)

        Column {
            id: groupsColumn
            width: groupedFlick.width
            spacing: Theme.spacingS

            Repeater {
                model: panel.groupedNotifications

                delegate: Rectangle {
                    id: groupCard
                    property var groupData: modelData
                    property bool expanded: panel.isRepoExpanded(groupData.repository)

                    width: groupsColumn.width
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.width: 1
                    border.color: Theme.outlineVariant
                    implicitHeight: groupColumn.implicitHeight + Theme.spacingS * 2

                    Column {
                        id: groupColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS

                        Item {
                            id: repoHeader
                            width: parent.width
                            height: 22

                            MouseArea {
                                id: repoHeaderArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.toggleRepo(groupCard.groupData.repository)
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.right: repoMeta.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: "folder"
                                    size: 16
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    width: parent.width - 22
                                    text: groupCard.groupData.repository
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Row {
                                id: repoMeta
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 10
                                    visible: groupCard.groupData.items.length > 0
                                             && (repoHeaderArea.containsMouse || repoDoneArea.containsMouse)
                                    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)
                                    z: 2

                                    MouseArea {
                                        id: repoDoneArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: panel.anyBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        enabled: !panel.anyBusy
                                        onClicked: panel.markRepoRead(groupCard.groupData.repository)
                                    }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "done"
                                        size: 13
                                        color: repoDoneArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                    }
                                }

                                Rectangle {
                                    visible: groupCard.groupData.items.length > 0
                                    height: 18
                                    radius: 9
                                    width: groupCountText.implicitWidth + Theme.spacingS
                                    color: groupCard.groupData.unreadCount > 0
                                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                           : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.20)

                                    StyledText {
                                        id: groupCountText
                                        anchors.centerIn: parent
                                        text: groupCard.groupData.unreadCount < groupCard.groupData.items.length
                                              ? (groupCard.groupData.unreadCount + "/" + groupCard.groupData.items.length)
                                              : String(groupCard.groupData.items.length)
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: groupCard.groupData.unreadCount > 0
                                               ? Theme.primary
                                               : Theme.surfaceVariantText
                                    }
                                }

                                DankIcon {
                                    name: "expand_more"
                                    size: 18
                                    color: Theme.surfaceVariantText
                                    rotation: groupCard.expanded ? 0 : -90

                                    Behavior on rotation {
                                        NumberAnimation { duration: 120 }
                                    }
                                }
                            }
                        }

                        Column {
                            id: repoItems
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: groupCard.expanded
                            height: visible ? implicitHeight : 0
                            clip: true

                            Repeater {
                                model: groupCard.groupData.items

                                delegate: NotificationRow {
                                    width: parent.width
                                    notificationData: modelData
                                    isBusy: panel.anyBusy
                                    titleLines: panel.titleLines
                                    onMarkRead: function(threadId) { panel.markThreadRead(threadId) }
                                    onMarkUnread: function(threadId) { panel.markThreadUnread(threadId) }
                                    onMarkDone: function(threadId) { panel.markThreadDone(threadId) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: filterBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: panel.tokenConfigured && panel.errorMessage === ""
        height: filterColumn.implicitHeight + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: Qt.rgba(Theme.surfaceContainerHigh.r, Theme.surfaceContainerHigh.g, Theme.surfaceContainerHigh.b, 0.85)
        border.color: Theme.outlineVariant
        border.width: 1
        z: 5

        Column {
            id: filterColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingXS

            Row {
                spacing: Theme.spacingXS

                StyledText {
                    text: "Read"
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                    width: 52
                }

                Repeater {
                    model: [
                        { label: "Unread", value: "unread" },
                        { label: "Read", value: "read" },
                        { label: "All", value: "all" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        height: 22
                        radius: 11
                        width: label.implicitWidth + Theme.spacingS
                        color: panel.readFilter === modelData.value
                               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                               : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                        border.width: 1
                        border.color: panel.readFilter === modelData.value ? Theme.primary : Theme.outlineVariant

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.readFilter = modelData.value
                        }

                        StyledText {
                            id: label
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 10
                            color: panel.readFilter === modelData.value ? Theme.primary : Theme.surfaceVariantText
                        }
                    }
                }
            }

            Row {
                spacing: Theme.spacingXS

                StyledText {
                    text: "Part."
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                    width: 52
                }

                Repeater {
                    model: [
                        { label: "Participated", value: "participated" },
                        { label: "Not Participated", value: "not_participated" },
                        { label: "All", value: "all" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        height: 22
                        radius: 11
                        width: label.implicitWidth + Theme.spacingS
                        color: panel.participationFilter === modelData.value
                               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                               : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                        border.width: 1
                        border.color: panel.participationFilter === modelData.value ? Theme.primary : Theme.outlineVariant

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.participationFilter = modelData.value
                        }

                        StyledText {
                            id: label
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 10
                            color: panel.participationFilter === modelData.value ? Theme.primary : Theme.surfaceVariantText
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
        width: 4
        color: "transparent"

        Rectangle {
            width: parent.width
            radius: 2
            color: Theme.outlineVariant
            opacity: groupedFlick.moving ? 0.8 : 0.4

            property real ratio: groupedFlick.height / groupedFlick.contentHeight
            height: Math.max(20, parent.height * ratio)
            y: groupedFlick.contentHeight > groupedFlick.height
               ? (groupedFlick.contentY / (groupedFlick.contentHeight - groupedFlick.height)) * (parent.height - height)
               : 0

            Behavior on opacity { NumberAnimation { duration: 200 } }
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
                 && panel.filteredNotifications.length === 0
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
            text: "Loading notifications..."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Column {
        visible: panel.tokenConfigured
                 && panel.errorMessage === ""
                 && panel.filteredNotifications.length === 0
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
            text: "No notifications"
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
