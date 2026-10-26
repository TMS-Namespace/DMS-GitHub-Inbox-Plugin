// tst_author_utils.qml - exercises the QML adapter against the real JavaScript facade.

import QtQuick
import QtTest
import "../../../src/QML" as Plugin

TestCase {
    function test_adapterKeepsAuthorNormalizationAndEndpointPlanning() {
        let subjectApiUrl = "https://api.github.com/repos/owner/repository/pulls/42";
        compare(Plugin.AuthorUtils.apiUrlFromWebUrl("https://github.com/owner/repository/pull/42"), subjectApiUrl);
        compare(Plugin.AuthorUtils.buildAuthorFetchUrls(subjectApiUrl, "PullRequest", false).length, 1);
        compare(Plugin.AuthorUtils.authorKey(" ALICE ", "", ""), "alice");
        let authors = Plugin.AuthorUtils.mergeAuthorLists([
            {
                login: "Alice",
                type: "User"
            }
        ], [
            {
                login: "Bob",
                type: "User"
            },
            {
                login: "alice",
                type: "User"
            }
        ]);
        compare(authors.length, 2);
        compare(authors[0].login, "Alice");
        compare(authors[1].login, "Bob");
    }

    name: "AuthorUtils"
}
