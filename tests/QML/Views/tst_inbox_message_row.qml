// tst_inbox_message_row.qml - tests the real message row's rendered state.

import QtQuick
import QtTest
import "../../../src/QML" as Plugin
import qs.Common

TestCase {
    id: testCase

    property var activeRow: null
    property var openedUrls: []

    function createRow(authorCount) {
        let authors = [];
        for (let index = 0; index < authorCount; index++)
            authors.push({
                login: "author-" + index,
                avatarUrl: "",
                htmlUrl: ""
            });

        let component = Qt.createComponent("../../../src/QML/Views/InboxMessageRow.qml");
        compare(component.status, Component.Ready, component.errorString());
        return component.createObject(this, {
            width: 420,
            messageData: {
                threadId: "thread-42",
                title: "A representative pull request title",
                subjectType: "PullRequest",
                repository: "owner/repository",
                updatedAt: "2026-04-03T12:00:00Z",
                unread: true,
                webUrl: "https://github.com/owner/repository/pull/42",
                repositoryUrl: "https://github.com/owner/repository"
            },
            authors: authors,
            showAuthors: true,
            titleLines: 2,
            openExternalUrlHandler: function (url) {
                testCase.openedUrls.push(url);
            }
        });
    }
    // Collect repeated avatar instances so all three edges can be checked, not just the first.
    function namedItems(item, name) {
        let matches = item.objectName === name ? [item] : [];
        for (let child of item.children || [])
            matches = matches.concat(namedItems(child, name));
        return matches;
    }
    function test_authorCountDoesNotResizeMessageCard() {
        let oneAuthorRow = createRow(1);
        let threeAuthorRow = createRow(3);
        compare(threeAuthorRow.height, oneAuthorRow.height);
        oneAuthorRow.destroy();
        threeAuthorRow.destroy();
    }
    // Configured title lines control the gaps, while actual author count leaves the slots stable.
    function test_authorSpacingTracksConfiguredTitleLines() {
        for (let showRepository of [false, true]) {
            let row = createRow(3);
            row.showRepositoryInfo = showRepository;
            row.extraHeight = showRepository ? 0 : 6;
            row.titleLines = 1;
            wait(30);
            let compactSpacing = row.authorRowSpacing;
            let compactHeight = row.height;
            row.titleLines = 4;
            wait(30);
            verify(row.height > compactHeight);
            verify(row.authorRowSpacing > compactSpacing);
            let expandedSpacing = row.authorRowSpacing;
            let expandedHeight = row.height;
            row.authors = row.authors.slice(0, 2);
            wait(30);
            compare(row.authorRowSpacing, expandedSpacing);
            compare(row.height, expandedHeight);
            row.destroy();
        }
    }
    function test_authorsAreCappedAtThree() {
        let row = createRow(5);
        compare(row.limitedAuthors.length, 3);
        row.destroy();
    }
    // Fit avatars inside unchanged cards for both grouping styles, widths and title-line settings.
    function test_avatarSizesAndSpacingFitCards() {
        for (let width of [320, 520]) {
            for (let showRepository of [false, true]) {
                for (let lines of [1, 2, 3, 4]) {
                    let row = createRow(3);
                    row.width = width;
                    row.showRepositoryInfo = showRepository;
                    row.extraHeight = showRepository ? 0 : 6;
                    row.titleLines = lines;
                    wait(30);
                    let avatars = namedItems(row, "authorAvatar");
                    compare(avatars.length, 3);
                    avatars.sort((left, right) => left.mapToItem(row, 0, 0).y - right.mapToItem(row, 0, 0).y);
                    let previousBottom = 0;
                    for (let avatar of avatars) {
                        let point = avatar.mapToItem(row, 0, 0);
                        compare(avatar.width, row.avatarSize);
                        compare(avatar.height, row.avatarSize);
                        verify(point.y >= Theme.spacingS, "Top inset: " + point.y + ", width=" + width + ", lines=" + lines + ", repository=" + showRepository);
                        verify(point.y + avatar.height <= row.height - Theme.spacingS);
                        verify(point.x >= Theme.spacingS);
                        verify(point.x + avatar.width <= row.width - Theme.spacingS);
                        if (previousBottom > 0)
                            verify(point.y - previousBottom >= row.authorRowSpacing, "Avatar gap: " + (point.y - previousBottom) + ", expected=" + row.authorRowSpacing + ", width=" + width + ", lines=" + lines + ", repository=" + showRepository);
                        previousBottom = point.y + avatar.height;
                    }
                    let repository = findChild(row, "repositoryAvatar");
                    compare(repository.width, row.avatarSize);
                    compare(repository.height, row.avatarSize);
                    let authorPadding = showRepository ? 2 * Theme.spacingS + 2 * row.minimumAuthorRowSpacing : Theme.spacingM + Plugin.GitHubConstants.messageRowAuthorColumnPaddingDelta;
                    let expectedHeight = Math.max(Theme.fontSizeMedium * 3 + Plugin.GitHubConstants.messageRowMinHeightDelta, row.contentMinHeight, 3 * (Theme.fontSizeMedium + Plugin.GitHubConstants.messageAuthorRowHeightDelta) + authorPadding) + row.extraHeight;
                    compare(row.height, expectedHeight);
                    if (lines === 2)
                        verify(row.avatarSize > 24);
                    row.destroy();
                }
            }
        }
    }
    // Full link text is included only when Qt actually elides it, not based on character counts.
    function test_browserTooltipsFollowElision() {
        let row = createRow(1);
        row.width = 300;
        row.showRepositoryInfo = true;
        row.titleLines = 1;
        row.messageData = Object.assign({}, row.messageData, {
            title: "A long title that cannot fit within the configured single visible line".repeat(3),
            repository: "long-organization-name/long-repository-name"
        });
        row.authors = [
            {
                login: "a-very-long-author-name-that-will-be-truncated"
            }
        ];
        wait(30);
        for (let pair of [["messageTitleText", "messageTitleTooltip", "messageTitleLink", "Open web page"], ["repositoryNameText", "repositoryTooltip", "repositoryLink", "Open repo web page"], ["authorNameText", "authorTooltip", "authorProfileLink", "Open author's web page"]]) {
            let label = findChild(row, pair[0]);
            let tooltip = findChild(row, pair[1]);
            verify(label.truncated);
            compare(tooltip.text, label.text + "\n" + pair[3]);
            compare(tooltip.multiline, true);
            compare(tooltip.target, label);
            compare(tooltip.hoverArea.objectName, pair[2]);
        }
        row.width = 900;
        row.messageData = Object.assign({}, row.messageData, {
            title: "PR",
            repository: "o/r"
        });
        row.authors = [
            {
                login: "a"
            }
        ];
        wait(30);
        for (let pair of [["messageTitleText", "messageTitleTooltip", "Open web page"], ["repositoryNameText", "repositoryTooltip", "Open repo web page"], ["authorNameText", "authorTooltip", "Open author's web page"]]) {
            compare(findChild(row, pair[0]).truncated, false);
            compare(findChild(row, pair[1]).text, pair[2]);
        }
        row.destroy();
    }
    // Verify the cache-to-row-to-image path, rather than only checking author metadata.
    function test_cachedAuthorAvatarLoadsFromDisk() {
        let row = createRow(0);
        let localUrl = String(Qt.resolvedUrl("../../../images/github-mark.svg"));
        row.authors = [
            {
                login: "octocat",
                avatarUrl: localUrl,
                htmlUrl: "https://github.com/octocat"
            }
        ];
        compare(row.avatarSource(row.authors[0]), localUrl);
        let avatar = findChild(row, "authorAvatar");
        verify(avatar);
        compare(avatar.source, localUrl);
        compare(avatar.loadableSource, localUrl);
        tryCompare(avatar, "imageReady", true);
        row.destroy();
    }
    // Date cards use a tighter font budget without changing the repository-group sizing formula.
    function test_dateHeightIsTighterAndIndependentOfActualTitle() {
        let row = createRow(3);
        row.showRepositoryInfo = true;
        row.titleLines = 2;
        let previousDateHeight = Theme.fontSizeMedium * 2 + Plugin.GitHubConstants.messageRowContentMinHeightDelta + 2 * (Theme.fontSizeMedium + Plugin.GitHubConstants.messageRowTitleLineHeightDelta) + 2 * row.mainInfoSpacing + row.repositoryRowHeight;
        verify(row.height < previousDateHeight);
        let height = row.height;
        row.messageData = Object.assign({}, row.messageData, {
            title: "A short title"
        });
        compare(row.height, height);
        row.messageData = Object.assign({}, row.messageData, {
            title: "A very long wrapped title ".repeat(40)
        });
        compare(row.height, height);
        row.authors = row.authors.slice(0, 1);
        compare(row.height, height);

        row.showRepositoryInfo = false;
        row.extraHeight = 6;
        for (let lines of [1, 2, 3, 4]) {
            row.titleLines = lines;
            let contentBudget = Theme.fontSizeMedium * 2 + Plugin.GitHubConstants.messageRowContentMinHeightDelta + lines * (Theme.fontSizeMedium + Plugin.GitHubConstants.messageRowTitleLineHeightDelta) + row.mainInfoSpacing;
            let authorBudget = 3 * (Theme.fontSizeMedium + Plugin.GitHubConstants.messageAuthorRowHeightDelta) + Theme.spacingM + Plugin.GitHubConstants.messageRowAuthorColumnPaddingDelta;
            compare(row.height, Math.max(Theme.fontSizeMedium * 3 + Plugin.GitHubConstants.messageRowMinHeightDelta, contentBudget, authorBudget) + 6);
        }
        row.destroy();
    }
    function test_invalidUrlDoesNotOpenOrClosePopout() {
        openedUrls = [];
        activeRow = createRow(0);
        activeRow.messageData = Object.assign({}, activeRow.messageData, {
            webUrl: "file:///etc/passwd",
            repositoryUrl: "file:///etc/passwd",
            repository: ""
        });
        closeSpy.clear();

        activeRow.openMessageUrl();

        compare(openedUrls.length, 0);
        compare(closeSpy.count, 0);
        activeRow.destroy();
        activeRow = null;
    }
    // The repository row and metadata keep the new theme-relative gap without overflowing cards.
    function test_messageContentGapsFitCard() {
        for (let width of [320, 520]) {
            let row = createRow(3);
            row.width = width;
            row.showRepositoryInfo = true;
            for (let lines of [1, 2, 3, 4]) {
                row.titleLines = lines;
                row.messageData = Object.assign({}, row.messageData, {
                    title: "A wrapped title using the configured line budget ".repeat(20)
                });
                wait(30);
                let title = findChild(row, "messageTitleLink");
                let repository = findChild(row, "repositoryLink");
                let metadata = findChild(row, "messageMetadataRow");
                let gap = Theme.spacingXS + Plugin.GitHubConstants.messageMainInfoColumnSpacingDelta;
                let titleGap = repository.mapToItem(row, 0, 0).y - title.mapToItem(row, 0, 0).y - title.height;
                let metadataGap = metadata.mapToItem(row, 0, 0).y - repository.mapToItem(row, 0, 0).y - repository.height;
                verify(titleGap >= gap, "Title gap=" + titleGap + ", expected=" + gap);
                verify(metadataGap >= gap, "Metadata gap=" + metadataGap + ", expected=" + gap);
                verify(metadata.mapToItem(row, 0, 0).y + metadata.height <= row.height - Theme.spacingS, "Metadata bottom=" + (metadata.mapToItem(row, 0, 0).y + metadata.height) + ", card=" + row.height);
            }
            row.destroy();
        }
    }
    function test_messageTitleAndMetadataRender() {
        let row = createRow(1);
        compare(row.title, "A representative pull request title");
        compare(row.subjectDisplay, "PR #42");
        verify(row.height > 0);
        row.destroy();
    }
    function test_openReadMessageDoesNotRequestReadMutation() {
        openedUrls = [];
        activeRow = createRow(1);
        activeRow.messageData = Object.assign({}, activeRow.messageData, {
            unread: false
        });
        closeSpy.clear();
        readAfterOpenSpy.clear();

        activeRow.openMessageUrl();

        compare(openedUrls.length, 1);
        compare(closeSpy.count, 1);
        compare(readAfterOpenSpy.count, 0);
        activeRow.destroy();
        activeRow = null;
    }
    function test_openUnreadMessageClosesOpensAndRequestsRead() {
        openedUrls = [];
        activeRow = createRow(1);
        closeSpy.clear();
        readAfterOpenSpy.clear();

        let titleLink = findChild(activeRow, "messageTitleLink");
        verify(titleLink);
        verify(titleLink.width > 0);
        verify(titleLink.height > 0);
        activeRow.openMessageUrl();

        compare(openedUrls, ["https://github.com/owner/repository/pull/42"]);
        compare(closeSpy.count, 1);
        compare(readAfterOpenSpy.count, 1);
        compare(readAfterOpenSpy.signalArguments[0][0], "thread-42");
        activeRow.destroy();
        activeRow = null;
    }
    function test_repositoryAndAuthorLinksCloseAndOpenTheirValidatedUrls() {
        openedUrls = [];
        activeRow = createRow(1);
        closeSpy.clear();

        activeRow.openRepository();
        activeRow.openAuthorProfile("https://github.com/author-0");

        compare(openedUrls, ["https://github.com/owner/repository", "https://github.com/author-0"]);
        compare(closeSpy.count, 2);
        activeRow.destroy();
        activeRow = null;
    }
    // Keep all colors theme-derived while names are subdued less than the metadata.
    function test_secondaryTextContrast() {
        let row = createRow(1);
        row.showRepositoryInfo = true;
        let secondary = Theme.withAlpha(Theme.surfaceVariantText, Plugin.GitHubConstants.messageSecondaryTextOpacity);
        let metadata = Theme.withAlpha(Theme.surfaceVariantText, Plugin.GitHubConstants.messageMetadataTextOpacity);
        compare(String(findChild(row, "repositoryNameText").color), String(secondary));
        compare(String(findChild(row, "authorNameText").color), String(secondary));
        compare(findChild(row, "repositoryNameText").font.pixelSize, Theme.fontSizeSmall);
        compare(findChild(row, "authorNameText").font.pixelSize, Theme.fontSizeSmall - 2);
        for (let label of findChild(row, "messageMetadataRow").children)
            compare(String(label.color), String(metadata));
        for (let label of findChild(row, "messageMetadataRow").children)
            compare(label.font.pixelSize, Theme.fontSizeSmall - 1);
        verify(metadata.a < secondary.a);
        compare(findChild(row, "messageTitleText").color, Theme.surfaceText);
        row.destroy();
    }
    // Increasing the configured title lines must remove redundant full-title tooltip text.
    function test_titleTooltipRespectsConfiguredLineLimit() {
        let row = createRow(0);
        row.width = 320;
        row.titleLines = 1;
        row.messageData = Object.assign({}, row.messageData, {
            title: "A title word ".repeat(10)
        });
        let title = findChild(row, "messageTitleText");
        let tooltip = findChild(row, "messageTitleTooltip");
        tryCompare(title, "truncated", true);
        row.titleLines = 4;
        tryCompare(title, "truncated", false);
        compare(tooltip.text, Plugin.GitHubConstants.openWebPageTooltipText);
        row.destroy();
    }

    name: "InboxMessageRow"
    visible: true

    SignalSpy {
        id: closeSpy

        signalName: "closePopout"
        target: testCase.activeRow
    }
    SignalSpy {
        id: readAfterOpenSpy

        signalName: "markReadAfterOpen"
        target: testCase.activeRow
    }
}
