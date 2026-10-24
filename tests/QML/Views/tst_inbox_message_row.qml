// tst_inbox_message_row.qml - tests the real message row's rendered state.

import QtQuick
import QtTest

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
    function test_authorCountDoesNotResizeMessageCard() {
        let oneAuthorRow = createRow(1);
        let threeAuthorRow = createRow(3);
        compare(threeAuthorRow.height, oneAuthorRow.height);
        oneAuthorRow.destroy();
        threeAuthorRow.destroy();
    }
    function test_authorsAreCappedAtThree() {
        let row = createRow(5);
        compare(row.limitedAuthors.length, 3);
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

    name: "InboxMessageRow"

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
