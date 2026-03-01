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

    property bool anyBusy: isLoading || isMutating
    property var expandedRepos: ({})

    Component.onCompleted: {
        expandedRepos = normalizeExpandedState(expandedReposState)
    }

    onExpandedReposStateChanged: {
        expandedRepos = normalizeExpandedState(expandedReposState)
    }
    property string readFilter: "both"                // yes(read) | no(unread) | both
    property string participationFilter: "both"       // yes | no | both

    property var filteredNotifications: {
        var result = []
        for (var index = 0; index < notifications.length; index++) {
            var item = notifications[index]
            var participated = !!item.participated

            if (readFilter === "yes" && item.unread) continue
            if (readFilter === "no" && !item.unread) continue

            if (participationFilter === "yes" && !participated) continue
            if (participationFilter === "no" && participated) continue

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
                    repoOwnerLogin: "",
                    repoAvatarUrl: "",
                    items: []
                }
                repoOrder.push(repo)
            }

            if (!groupsByRepo[repo].repoAvatarUrl) {
                groupsByRepo[repo].repoOwnerLogin = item.repositoryOwnerLogin || ""
                groupsByRepo[repo].repoAvatarUrl = item.repositoryOwnerAvatarUrl || ""
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
        anchors.rightMargin: Theme.spacingXS
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
                            height: 28

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

                                Item {
                                    width: 20
                                    height: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        id: repoAvatarMask
                                        anchors.fill: parent
                                        radius: width / 2
                                        clip: true
                                        color: Theme.surfaceContainerHighest

                                        Image {
                                            id: repoAvatarImage
                                            anchors.fill: parent
                                            source: groupCard.groupData.repoAvatarUrl || ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            visible: status === Image.Ready
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "folder"
                                            size: 18
                                            color: Theme.surfaceVariantText
                                            visible: repoAvatarImage.status !== Image.Ready
                                        }
                                    }
                                }

                                StyledText {
                                    width: parent.width - 30
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
                                        onClicked: panel.markRepoDone(groupCard.groupData.repository)
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
                                    authors: panel.showAuthorInfo ? (panel.authorsByThread[modelData.threadId] || []) : []
                                    showAuthors: panel.showAuthorInfo
                                    isBusy: panel.anyBusy
                                    titleLines: panel.titleLines
                                    onMarkRead: function(threadId) { panel.markThreadRead(threadId) }
                                    onMarkUnread: function(threadId) { panel.markThreadUnread(threadId) }
                                    onMarkDone: function(threadId) { panel.markThreadDone(threadId) }
                                    onRequestAuthors: function(threadId, subjectApiUrl, subjectType) {
                                        panel.requestThreadAuthors(threadId, subjectApiUrl, subjectType)
                                    }
                                }
                            }
                        }
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
                return Math.max(96, Math.min(132, fit))
            }

            StyledText {
                id: readLabel
                width: 34
                text: "Read"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: filterRow.segmentWidth
                height: 24
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.80)
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
                            color: panel.readFilter === modelData.value
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                                   : "transparent"
                            border.width: panel.readFilter === modelData.value ? 1 : 0
                            border.color: Theme.primary

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
            Item {
                width: filterRow.groupGap
                height: 1
            }

            StyledText {
                id: participatedLabel
                width: 72
                text: "Participated"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: filterRow.segmentWidth
                height: 24
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.80)
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
                            color: panel.participationFilter === modelData.value
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                                   : "transparent"
                            border.width: panel.participationFilter === modelData.value ? 1 : 0
                            border.color: Theme.primary

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
