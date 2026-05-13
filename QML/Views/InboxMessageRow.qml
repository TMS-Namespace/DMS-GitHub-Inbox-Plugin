// InboxMessageRow.qml - Single GitHub inbox message row for popout list

import QtQuick
import qs.Common
import qs.Widgets
import ".."
import "../../JS/GitHubHelpers.js" as GitHub

Item {
    id: row

    property var messageData: ({})
    property bool isBusy: false
    property int titleLines: 2
    property var authors: []
    property bool showAuthors: true
    property bool showRepositoryInfo: false
    property bool allowAuthorRequests: true
    property int extraHeight: 0

    signal markRead(string threadId)
    signal markUnread(string threadId)
    signal markDone(string threadId)
    signal requestAuthors(string threadId, string subjectApiUrl, string subjectType)
    signal closePopout()

    property string threadId: messageData.threadId || ""
    property bool unread: messageData.unread || false
    property string title: messageData.title || "(untitled)"
    property string subjectType: messageData.subjectType || "Message"
    property string subjectApiUrl: messageData.subjectApiUrl || ""
    property string reason: GitHub.reasonLabel(messageData.reason)
    property string updatedAt: messageData.updatedAt || ""
    property string webUrl: effectiveWebUrl()
    property string updatedText: GitHub.relativeTimeFromIso(updatedAt)
    property string subjectIcon: GitHub.subjectIconName(subjectType)
    property bool authorRequestSent: false

    property var resolvedAuthors: authors || []
    property bool shouldRequestAuthors: allowAuthorRequests
                                        && showAuthors
                                        && !authorRequestSent
                                        && threadId !== ""
                                        && resolvedAuthors.length === 0

    property var limitedAuthors: {
        var list = resolvedAuthors || []
        if (list.length <= GitHubConstants.maxAuthorsDisplayedPerMessage)
            return list
        return list.slice(0, GitHubConstants.maxAuthorsDisplayedPerMessage)
    }

    property int authorRowHeight: GitHubConstants.messageAuthorRowHeightPx
    property int authorColumnHeight: showAuthors ? Math.max(0, limitedAuthors.length * authorRowHeight) : 0
    property int repositoryRowHeight: showRepositoryInfo ? GitHubConstants.messageAuthorRowHeightPx : 0
    property int repositoryRowSpacing: showRepositoryInfo ? GitHubConstants.messageMainInfoColumnSpacingPx : 0
    property int contentMinHeight: GitHubConstants.messageRowContentMinHeightPx
                                   + (Math.max(1, titleLines) * GitHubConstants.messageRowTitleLineHeightPx)
                                   + repositoryRowHeight
                                   + repositoryRowSpacing
    property int rowHeight: Math.max(contentMinHeight, authorColumnHeight + GitHubConstants.messageRowAuthorColumnPaddingPx)

    function openAuthorProfile(url) {
        if (url) {
            row.closePopout()
            Qt.openUrlExternally(url)
        }
    }

    function authorDisplayName(author) {
        if (!author)
            return "unknown"
        var display = String(author.login || "").trim()
        if (display)
            return display
        var profile = String(author.htmlUrl || "").trim()
        if (!profile)
            return "unknown"
        var slash = profile.lastIndexOf("/")
        if (slash < 0 || slash + 1 >= profile.length)
            return "unknown"
        return profile.substring(slash + 1)
    }

    function authorProfile(author) {
        if (!author)
            return ""
        if (author.htmlUrl)
            return author.htmlUrl
        var login = String(author.login || "").trim()
        return login ? ("https://github.com/" + encodeURIComponent(login)) : ""
    }

    function avatarSource(author) {
        if (!author)
            return ""
        var avatarUrl = String(author.avatarUrl || author.avatar_url || "").trim()
        if (avatarUrl)
            return avatarUrl
        var login = String(author.login || "").trim()
        if (!login)
            return ""
        return GitHubConstants.githubAvatarsBaseUrl + "/" + encodeURIComponent(login) + "?size=" + GitHubConstants.avatarDefaultSizePx
    }

    function requestAuthorsIfNeeded() {
        if (!shouldRequestAuthors)
            return

        authorRequestSent = true
        requestAuthors(threadId, subjectApiUrl, subjectType)
    }

    function repositoryWebUrl() {
        var repoUrl = String(messageData.repositoryUrl || "").trim()
        if (repoUrl)
            return repoUrl
        var repo = String(messageData.repository || "").trim()
        return repo ? (GitHubConstants.githubWebBaseUrl + "/" + repo) : ""
    }

    function effectiveWebUrl() {
        var rawUrl = String(messageData.webUrl || "").trim()
        if (rawUrl.indexOf(GitHubConstants.githubWebBaseUrl + "/notifications/threads/") === 0)
            return repositoryWebUrl()
        return rawUrl
    }

    function openRepository() {
        var repoUrl = repositoryWebUrl()
        if (!repoUrl)
            return
        row.closePopout()
        Qt.openUrlExternally(repoUrl)
    }

    function authorRequestDelayMs() {
        var numericId = parseInt(threadId || "0")
        if (isNaN(numericId))
            numericId = 0
        return 300 + (numericId % 8) * 120
    }

    height: Math.max(GitHubConstants.messageRowMinHeightPx, rowHeight) + extraHeight

    onThreadIdChanged: authorRequestSent = false
    onUpdatedAtChanged: authorRequestSent = false
    onResolvedAuthorsChanged: {
        if (resolvedAuthors.length > 0)
            authorRequestSent = true
    }

    Timer {
        id: authorRequestTimer
        interval: row.authorRequestDelayMs()
        repeat: false
        running: row.shouldRequestAuthors
        onTriggered: row.requestAuthorsIfNeeded()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: row.unread ? Theme.withAlpha(Theme.primary, 0.1) : Theme.nestedSurface
        border.color: row.unread ? Theme.withAlpha(Theme.primary, 0.3) : Theme.outlineMedium
        border.width: row.unread ? 1 : GitHubConstants.messageRowBorderWidthPx
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: webUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (webUrl) {
                row.closePopout()
                Qt.openUrlExternally(webUrl)
            }
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Item {
            id: iconSlot
            width: GitHubConstants.messageIconSlotWidthPx
            height: parent.height

            Rectangle {
                width: GitHubConstants.messageIconBadgeWidthPx
                height: GitHubConstants.messageIconBadgeHeightPx
                radius: GitHubConstants.messageIconBadgeRadiusPx
                anchors.top: parent.top
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, GitHubConstants.messageIconBadgeBackgroundOpacity)

                DankIcon {
                    anchors.centerIn: parent
                    name: row.subjectIcon
                    size: GitHubConstants.messageSubjectIconSizePx
                    color: row.unread ? Theme.primary : Theme.surfaceVariantText
                }
            }
        }

        Item {
            id: bodySlot
            width: parent.width - iconSlot.width - Theme.spacingS
            height: parent.height

            Row {
                anchors.fill: parent
                spacing: Theme.spacingS

                Column {
                    id: mainInfo
                    width: (showAuthors && row.limitedAuthors.length > 0)
                           ? Math.max(GitHubConstants.messageMainInfoMinWidthPx, Math.floor(bodySlot.width * GitHubConstants.messageMainInfoWidthRatio))
                           : bodySlot.width
                    anchors.top: parent.top
                    spacing: GitHubConstants.messageMainInfoColumnSpacingPx

                    StyledText {
                        width: parent.width
                        text: row.title
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: row.unread ? Font.DemiBold : Font.Medium
                        color: Theme.surfaceText
                        wrapMode: Text.Wrap
                        maximumLineCount: Math.max(1, row.titleLines)
                        elide: Text.ElideRight
                    }

                    Item {
                        id: repositoryInfoRow
                        width: parent.width
                        height: row.showRepositoryInfo ? GitHubConstants.messageAuthorRowHeightPx : 0
                        visible: row.showRepositoryInfo

                        Item {
                            id: repositoryAvatar
                            width: GitHubConstants.popoutRepoAvatarSizePx
                            height: GitHubConstants.popoutRepoAvatarSizePx
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter

                            RoundedAvatar {
                                anchors.fill: parent
                                source: row.messageData.repositoryOwnerAvatarUrl || ""
                                fallbackIcon: "folder"
                                fallbackIconSize: GitHubConstants.popoutRepoAvatarFallbackIconSizePx
                            }
                        }

                        StyledText {
                            anchors.left: repositoryAvatar.right
                            anchors.leftMargin: Theme.spacingXS
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.messageData.repository || "Unknown repository"
                            font.pixelSize: GitHubConstants.messageMetadataFontSizePx
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: row.repositoryWebUrl() ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: row.openRepository()
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: row.subjectType
                            font.pixelSize: GitHubConstants.messageMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: "\u2022"
                            font.pixelSize: GitHubConstants.messageMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: row.reason
                            font.pixelSize: GitHubConstants.messageMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: "\u2022"
                            font.pixelSize: GitHubConstants.messageMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: row.updatedText
                            font.pixelSize: GitHubConstants.messageMetadataFontSizePx
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                        }
                    }
                }

                Item {
                    id: authorInfo
                    width: Math.max(GitHubConstants.messageAuthorColumnMinWidthPx, bodySlot.width - mainInfo.width - Theme.spacingS)
                    height: parent.height
                    visible: row.showAuthors && row.limitedAuthors.length > 0

                    Column {
                        id: authorColumn
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: GitHubConstants.messageAuthorColumnItemSpacingPx

                        Repeater {
                            model: row.limitedAuthors

                            delegate: Item {
                                required property var modelData
                                width: authorInfo.width
                                height: row.authorRowHeight

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    Item {
                                        id: avatarHost
                                        width: GitHubConstants.authorAvatarSizePx
                                        height: GitHubConstants.authorAvatarSizePx

                                        RoundedAvatar {
                                            anchors.fill: parent
                                            source: row.avatarSource(modelData)
                                            fallbackIcon: "person"
                                            fallbackIconSize: GitHubConstants.authorAvatarFallbackIconSizePx
                                        }
                                    }

                                    StyledText {
                                        width: Math.max(GitHubConstants.authorNameMinWidthPx, authorInfo.width - avatarHost.width - Theme.spacingXS)
                                        text: row.authorDisplayName(modelData)
                                        font.pixelSize: GitHubConstants.authorNameFontSizePx
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        wrapMode: Text.NoWrap
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: row.openAuthorProfile(row.authorProfile(modelData))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // -- Hover actions --------------------------------------------------------
    Item {
        id: actionsHost
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: GitHubConstants.messageActionsHostMarginPx
        anchors.bottomMargin: GitHubConstants.messageActionsHostMarginPx
        width: GitHubConstants.messageActionsHostWidthPx
        height: GitHubConstants.messageActionsHostHeightPx
        z: 10

        MouseArea {
            id: actionsHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Row {
            id: actionButtons
            spacing: GitHubConstants.messageActionButtonsSpacingPx
            visible: rowArea.containsMouse
                     || actionsHoverArea.containsMouse
                     || readToggleArea.containsMouse
                     || doneArea.containsMouse
            opacity: visible ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: GitHubConstants.messageActionsFadeDurationMs }
            }

            Rectangle {
                width: GitHubConstants.messageActionButtonSizePx
                height: GitHubConstants.messageActionButtonSizePx
                radius: GitHubConstants.messageActionButtonRadiusPx
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.messageActionButtonBgOpacity)

                MouseArea {
                    id: readToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !row.isBusy && row.threadId !== ""
                    onClicked: {
                        if (row.unread)
                            row.markRead(row.threadId)
                        else
                            row.markUnread(row.threadId)
                    }
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: row.unread ? "mark_email_read" : "mark_email_unread"
                    size: GitHubConstants.messageActionButtonIconSizePx
                    color: readToggleArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: GitHubConstants.messageActionButtonSizePx
                height: GitHubConstants.messageActionButtonSizePx
                radius: GitHubConstants.messageActionButtonRadiusPx
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, GitHubConstants.messageActionButtonBgOpacity)

                MouseArea {
                    id: doneArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !row.isBusy && row.threadId !== ""
                    onClicked: row.markDone(row.threadId)
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: "done"
                    size: GitHubConstants.messageActionButtonIconSizePx
                    color: doneArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                }
            }
        }
    }
}
