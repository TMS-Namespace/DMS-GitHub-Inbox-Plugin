// InboxMessageRow.qml - Single GitHub inbox message row for popout list

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common
import qs.DCommon.Widgets

Item {
    id: row

    property bool allowAuthorRequests: true
    // Keep the existing card-height budget independent of the fitted avatar dimensions.
    property int authorColumnHeight: showAuthors ? GitHubConstants.maxAuthorsDisplayedPerMessage * (Theme.fontSizeMedium + GitHubConstants.messageAuthorRowHeightDelta) : 0
    property bool authorRequestSent: false
    readonly property int authorRowHeight: Math.max(0, Math.min(Theme.fontSizeMedium + GitHubConstants.messageAuthorRowHeightDelta, Math.floor((height - 2 * Theme.spacingS - (GitHubConstants.maxAuthorsDisplayedPerMessage - 1) * authorRowSpacing) / GitHubConstants.maxAuthorsDisplayedPerMessage)))
    readonly property real authorRowSpacing: Math.max(0, (Theme.spacingXXS || 0) + GitHubConstants.messageAuthorColumnItemSpacingDelta)
    property var authors: []
    readonly property int avatarSize: authorRowHeight
    property int contentMinHeight: Theme.fontSizeMedium * 2 + GitHubConstants.messageRowContentMinHeightDelta + (Math.max(1, titleLines) * (Theme.fontSizeMedium + GitHubConstants.messageRowTitleLineHeightDelta)) + repositoryRowHeight + repositoryRowSpacing
    property int extraHeight: 0
    property bool isBusy: false
    property var limitedAuthors: {
        let list = resolvedAuthors || [];
        if (list.length <= GitHubConstants.maxAuthorsDisplayedPerMessage)
            return list;
        return list.slice(0, GitHubConstants.maxAuthorsDisplayedPerMessage);
    }
    property var messageData: ({})
    property var openExternalUrlHandler: function (url) {
        Qt.openUrlExternally(url);
    }
    readonly property var providerApi: GitHubManager.getProviderApi(GitHubManager.providerTypes[0])
    property string reason: providerApi ? providerApi.reasonLabel(messageData.reason) : "Activity"
    property int repositoryRowHeight: showRepositoryInfo ? Theme.fontSizeMedium + GitHubConstants.messageAuthorRowHeightDelta : 0
    property int repositoryRowSpacing: showRepositoryInfo ? Theme.spacingXS + GitHubConstants.messageMainInfoColumnSpacingDelta : 0
    property var resolvedAuthors: authors || []
    property int rowHeight: Math.max(contentMinHeight, authorColumnHeight + Theme.spacingM + GitHubConstants.messageRowAuthorColumnPaddingDelta)
    property bool shouldRequestAuthors: allowAuthorRequests && showAuthors && !authorRequestSent && threadId !== "" && resolvedAuthors.length === 0
    property bool showAuthors: true
    property bool showRepositoryInfo: false
    property string subjectApiUrl: messageData.subjectApiUrl || ""
    property string subjectDisplay: subjectReference ? (subjectLabel + " " + subjectReference) : subjectLabel
    property string subjectIcon: providerApi ? providerApi.subjectIconName(subjectType) : "notifications"
    property string subjectLabel: providerApi ? providerApi.subjectDisplayLabel(subjectType) : subjectType
    property string subjectReference: providerApi ? providerApi.subjectReferenceLabel(subjectType, subjectApiUrl, webUrl, messageData.subjectReference || "") : ""
    property string subjectType: messageData.subjectType || "Message"
    property string threadId: messageData.threadId || ""
    property string title: messageData.title || "(untitled)"
    property int titleLines: GitHubConstants.defaultTitleLines
    property bool unread: messageData.unread || false
    property string updatedAt: messageData.updatedAt || ""
    property string updatedText: providerApi ? providerApi.relativeTimeFromIso(updatedAt) : ""
    property string webUrl: effectiveWebUrl()

    signal closePopout
    signal markDone(string threadId)
    signal markRead(string threadId)
    signal markReadAfterOpen(string threadId)
    signal markUnread(string threadId)
    signal requestAuthors(string threadId, string subjectApiUrl, string subjectType)

    // Prefer a login while retaining a usable label for app-style author profiles.
    function authorDisplayName(author) {
        if (!author)
            return "unknown";
        let display = String(author.login || "").trim();
        if (display)
            return display;
        let profile = String(author.htmlUrl || "").trim();
        if (!profile)
            return "unknown";
        let slash = profile.lastIndexOf("/");
        if (slash < 0 || slash + 1 >= profile.length)
            return "unknown";
        return profile.substring(slash + 1);
    }
    // Build a validated profile destination without trusting arbitrary external URLs.
    function authorProfile(author) {
        if (!author)
            return "";
        if (author.htmlUrl && providerApi && providerApi.isAllowedWebUrl(author.htmlUrl))
            return author.htmlUrl;
        let login = String(author.login || "").trim();
        return providerApi ? providerApi.buildUserProfileUrl(login) : "";
    }
    // Stagger row requests deterministically so popup creation cannot start a burst.
    function authorRequestDelayMs() {
        let numericId = parseInt(threadId || "0");
        if (isNaN(numericId))
            numericId = 0;
        return 300 + (numericId % 8) * 120;
    }
    // Render cached local files directly while validating network avatar destinations.
    function avatarSource(author) {
        if (!author)
            return "";
        let avatarUrl = String(author.avatarUrl || author.avatar_url || "").trim();
        // Cached files are rendered locally; the provider validator only governs network requests.
        if (avatarUrl.indexOf("file://") === 0)
            return avatarUrl;
        if (avatarUrl && providerApi && providerApi.isAllowedAvatarUrl(avatarUrl))
            return avatarUrl;
        let login = String(author.login || "").trim();
        return providerApi ? providerApi.buildAvatarUrl(login) : "";
    }
    // Choose a validated subject destination and handle unresolved release links explicitly.
    function effectiveWebUrl() {
        let rawUrl = String(messageData.webUrl || "").trim();
        if (!providerApi || !providerApi.isAllowedWebUrl(rawUrl))
            return repositoryWebUrl();
        if (rawUrl.indexOf(GitHubConstants.githubWebBaseUrl + "/notifications/threads/") === 0)
            return repositoryWebUrl();
        if (String(row.subjectType || "").toLowerCase() === "release" && String(row.subjectApiUrl || "").match(/\/releases\/[0-9]+$/) && rawUrl.indexOf("/releases/tag/") >= 0 && !messageData.webUrlResolved)
            return repositoryWebUrl() + "/releases";
        return rawUrl;
    }
    // Close the popup before opening a validated author destination.
    function openAuthorProfile(url) {
        if (providerApi && providerApi.isAllowedWebUrl(url)) {
            row.closePopout();
            row.openExternalUrlHandler(url);
        }
    }
    // Close first, open the destination, then request optimistic read synchronization.
    function openMessageUrl() {
        if (!providerApi || !providerApi.isAllowedWebUrl(webUrl))
            return;
        let shouldMarkRead = row.unread && row.threadId;
        row.closePopout();
        row.openExternalUrlHandler(webUrl);
        if (shouldMarkRead)
            row.markReadAfterOpen(row.threadId);
    }
    // Close the popup before opening the validated repository destination.
    function openRepository() {
        let repoUrl = repositoryWebUrl();
        if (!providerApi || !providerApi.isAllowedWebUrl(repoUrl))
            return;
        row.closePopout();
        row.openExternalUrlHandler(repoUrl);
    }
    // Prefer a restored local repository avatar before a permitted remote fallback.
    function repositoryAvatarSource() {
        let avatarUrl = String(messageData.repositoryOwnerAvatarUrl || "").trim();
        if (avatarUrl.indexOf("file://") === 0)
            return avatarUrl;
        if (providerApi && providerApi.isAllowedAvatarUrl(avatarUrl))
            return avatarUrl;
        return providerApi ? providerApi.buildAvatarUrl(messageData.repositoryOwnerLogin || "") : "";
    }
    // Prefer a validated repository destination over any untrusted message URL.
    function repositoryWebUrl() {
        let repoUrl = String(messageData.repositoryUrl || "").trim();
        if (providerApi && providerApi.isAllowedWebUrl(repoUrl))
            return repoUrl;
        let repo = String(messageData.repository || "").trim();
        return providerApi ? providerApi.buildRepositoryWebUrl(repo) : "";
    }
    // Request missing author information once per row rather than on every binding update.
    function requestAuthorsIfNeeded() {
        if (!shouldRequestAuthors)
            return;
        authorRequestSent = true;
        requestAuthors(threadId, subjectApiUrl, subjectType);
    }

    height: Math.max(Theme.fontSizeMedium * 3 + GitHubConstants.messageRowMinHeightDelta, rowHeight) + extraHeight

    onResolvedAuthorsChanged: {
        if (resolvedAuthors.length > 0)
            authorRequestSent = true;
    }
    onThreadIdChanged: authorRequestSent = false
    onUpdatedAtChanged: authorRequestSent = false

    Timer {
        id: authorRequestTimer

        interval: row.authorRequestDelayMs()
        repeat: false
        running: row.shouldRequestAuthors

        onTriggered: row.requestAuthorsIfNeeded()
    }
    Rectangle {
        anchors.fill: parent
        border.color: row.unread ? Theme.withAlpha(Theme.primary, 0.3) : Theme.outlineMedium
        border.width: row.unread ? 1 : GitHubConstants.messageRowBorderWidthPx
        color: row.unread ? Theme.withAlpha(Theme.primary, 0.1) : Theme.nestedSurface
        radius: Theme.cornerRadius
    }
    MouseArea {
        id: rowArea

        acceptedButtons: Qt.NoButton
        anchors.fill: parent
        hoverEnabled: true
    }
    Row {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Item {
            id: iconSlot

            height: parent.height
            width: GitHubConstants.messageIconSlotWidthPx

            Rectangle {
                anchors.top: parent.top
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, GitHubConstants.messageIconBadgeBackgroundOpacity)
                height: GitHubConstants.messageIconBadgeHeightPx
                radius: Math.max(0, Math.min(GitHubConstants.messageIconBadgeWidthPx / 2, Theme.cornerRadius + GitHubConstants.messageIconBadgeRadiusDelta))
                width: GitHubConstants.messageIconBadgeWidthPx

                DIcon {
                    anchors.centerIn: parent
                    color: row.unread ? Theme.primary : Theme.surfaceVariantText
                    name: row.subjectIcon
                    size: GitHubConstants.messageSubjectIconSizePx
                }
            }
        }
        Item {
            id: bodySlot

            height: parent.height
            width: parent.width - iconSlot.width - Theme.spacingS

            Row {
                anchors.fill: parent
                spacing: Theme.spacingS

                Column {
                    id: mainInfo

                    anchors.top: parent.top
                    spacing: Theme.spacingXS + GitHubConstants.messageMainInfoColumnSpacingDelta
                    width: (row.showAuthors && row.limitedAuthors.length > 0) ? Math.max(GitHubConstants.messageMainInfoMinWidthPx, Math.floor(bodySlot.width * GitHubConstants.messageMainInfoWidthRatio)) : bodySlot.width

                    Item {
                        id: titleHost

                        height: Math.max(titleText.paintedHeight, titleText.implicitHeight)
                        width: parent.width

                        StyledText {
                            id: titleText

                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: row.unread ? Font.DemiBold : Font.Medium
                            maximumLineCount: Math.max(1, row.titleLines)
                            text: row.title
                            width: parent.width
                            wrapMode: Text.Wrap
                        }
                        MouseArea {
                            cursorShape: row.webUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
                            height: titleHost.height
                            hoverEnabled: true
                            objectName: "messageTitleLink"
                            width: Math.min(titleText.paintedWidth, titleText.width)

                            onClicked: row.openMessageUrl()
                        }
                    }
                    Item {
                        id: repositoryInfoRow

                        height: row.showRepositoryInfo ? Theme.fontSizeMedium + GitHubConstants.messageAuthorRowHeightDelta : 0
                        visible: row.showRepositoryInfo
                        width: parent.width

                        Item {
                            id: repositoryAvatar

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            height: row.avatarSize
                            objectName: "repositoryAvatar"
                            width: row.avatarSize

                            RoundedAvatar {
                                anchors.fill: parent
                                fallbackIcon: "folder"
                                fallbackIconSize: GitHubConstants.popoutRepoAvatarFallbackIconSizePx
                                source: row.repositoryAvatarSource()
                            }
                        }
                        StyledText {
                            anchors.left: repositoryAvatar.right
                            anchors.leftMargin: Theme.spacingXS
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                            font.weight: Font.Medium
                            maximumLineCount: 1
                            text: row.messageData.repository || "Unknown repository"
                            wrapMode: Text.NoWrap
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: row.repositoryWebUrl() ? Qt.PointingHandCursor : Qt.ArrowCursor
                            hoverEnabled: true
                            objectName: "repositoryLink"

                            onClicked: row.openRepository()
                        }
                    }
                    Row {
                        spacing: Theme.spacingXS
                        width: parent.width

                        StyledText {
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                            text: row.subjectDisplay
                        }
                        StyledText {
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                            text: "\u2022"
                        }
                        StyledText {
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                            text: row.reason
                        }
                        StyledText {
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                            text: "\u2022"
                        }
                        StyledText {
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                            text: row.updatedText
                        }
                    }
                }
                Item {
                    id: authorInfo

                    height: parent.height
                    visible: row.showAuthors && row.limitedAuthors.length > 0
                    width: Math.max(GitHubConstants.messageAuthorColumnMinWidthPx, bodySlot.width - mainInfo.width - Theme.spacingS)

                    Column {
                        id: authorColumn

                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: row.authorRowSpacing

                        Repeater {
                            model: row.limitedAuthors

                            delegate: Item {
                                id: authorDelegate

                                required property var modelData

                                height: row.authorRowHeight
                                width: authorInfo.width

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    Item {
                                        id: avatarHost

                                        height: row.avatarSize
                                        width: row.avatarSize

                                        RoundedAvatar {
                                            anchors.fill: parent
                                            fallbackIcon: "person"
                                            fallbackIconSize: GitHubConstants.authorAvatarFallbackIconSizePx
                                            objectName: "authorAvatar"
                                            source: row.avatarSource(authorDelegate.modelData)
                                        }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeSmall + GitHubConstants.authorNameFontSizeDelta
                                        maximumLineCount: 1
                                        text: row.authorDisplayName(authorDelegate.modelData)
                                        width: Math.max(GitHubConstants.authorNameMinWidthPx, authorInfo.width - avatarHost.width - Theme.spacingXS)
                                        wrapMode: Text.NoWrap
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    objectName: "authorProfileLink"

                                    onClicked: row.openAuthorProfile(row.authorProfile(authorDelegate.modelData))
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

        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacingXS + GitHubConstants.messageActionsHostMarginDelta
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingXS + GitHubConstants.messageActionsHostMarginDelta
        height: GitHubConstants.messageActionsHostHeightPx
        width: GitHubConstants.messageActionsHostWidthPx
        z: 10

        MouseArea {
            id: actionsHoverArea

            acceptedButtons: Qt.NoButton
            anchors.fill: parent
            hoverEnabled: true
        }
        Row {
            id: actionButtons

            opacity: visible ? 1 : 0
            spacing: Theme.spacingXS + GitHubConstants.messageActionButtonsSpacingDelta
            visible: rowArea.containsMouse || actionsHoverArea.containsMouse || readToggleArea.hovered || doneArea.hovered

            Behavior on opacity {
                NumberAnimation {
                    duration: GitHubConstants.messageActionsFadeDurationMs
                }
            }

            DActionButton {
                id: readToggleArea

                backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
                buttonSize: GitHubConstants.messageActionButtonSizePx
                enabled: !row.isBusy && row.threadId !== ""
                iconColor: readToggleArea.hovered ? Theme.primary : Theme.surfaceText
                iconName: row.unread ? "mark_email_read" : "mark_email_unread"
                iconSize: GitHubConstants.messageActionButtonIconSizePx
                objectName: "messageReadButton"
                radius: width / 2
                tooltipText: row.unread ? "Mark as read" : "Mark as unread"

                onClicked: {
                    if (row.unread)
                        row.markRead(row.threadId);
                    else
                        row.markUnread(row.threadId);
                }
            }
            DActionButton {
                id: doneArea

                backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
                buttonSize: GitHubConstants.messageActionButtonSizePx
                enabled: !row.isBusy && row.threadId !== ""
                iconColor: doneArea.hovered ? Theme.primary : Theme.surfaceText
                iconName: "done"
                iconSize: GitHubConstants.messageActionButtonIconSizePx
                objectName: "messageDoneButton"
                radius: width / 2
                tooltipText: "Mark as done"

                onClicked: row.markDone(row.threadId)
            }
        }
    }
}
