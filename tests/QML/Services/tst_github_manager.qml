// tst_github_manager.qml - tests the loaded GitHub manager and provider facade.

import QtQuick
import QtTest
import "../../../src/QML/Services" as Services

TestCase {
    function test_githubProviderIsAvailableThroughTheManager() {
        let manager = Services.GitHubManager;
        compare(manager.loadErrors.length, 0);
        compare(manager.providerTypes.length, 1);
        compare(manager.providerTypes[0], "github");
        verify(manager.properties.apiBaseUrl.length > 0);

        let api = manager.getProviderApi("github");
        verify(api !== null);
        compare(api.providerId, "github");
        compare(api.buildInboxUrl(), manager.properties.apiBaseUrl + manager.properties.inboxPath);
        compare(api.reasonLabel("ci_activity"), "CI Activity");
    }
    function test_managerRejectsAnUnsupportedProvider() {
        compare(Services.GitHubManager.getProviderApi("unsupported"), null);
    }

    name: "GitHubManager"
}
