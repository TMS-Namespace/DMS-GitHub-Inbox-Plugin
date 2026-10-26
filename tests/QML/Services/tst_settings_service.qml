// tst_settings_service.qml - token validation must guard keyring writes and pending edits.

import QtQuick
import QtTest
import "../../../src/QML"

TestCase {
    id: testCase

    // Instantiate the real service with isolated process doubles.
    function createService() {
        let component = Qt.createComponent("../../../src/QML/Services/SettingsService.qml");
        compare(component.status, Component.Ready, component.errorString());
        return component.createObject(testCase);
    }
    // Merely tabbing through a loaded token must not trigger another keyring write.
    function test_completionWithoutEditsDoesNotSave() {
        let service = createService();
        let store = findChild(service, "settingsSecretStore");
        store.tokenLoaded("ghp_" + "a".repeat(36));
        service.finishTokenEdit(service.tokenValue);
        compare(store.isStoring, false);
        compare(store._pendingStoreToken, "");
        service.destroy();
    }
    // Drafts are not saved on idle and survive a late initial keyring lookup.
    function test_editsWaitForCompletion() {
        let service = createService();
        let store = findChild(service, "settingsSecretStore");
        let confirmed = "ghp_" + "a".repeat(36);
        store.token = confirmed;
        service.updateTokenDraft("ghp_" + "b".repeat(36));
        service.updateTokenDraft("ghp_short");
        store.tokenLoaded(confirmed);
        compare(service.tokenValue, "ghp_short");
        wait(650);
        compare(store.isStoring, false);
        compare(store._pendingStoreToken, "");
        compare(store.token, confirmed);
        service.destroy();
    }
    // Validation must run before persistence, including when called without the debounce handler.
    function test_invalidInputDoesNotReplaceConfirmedToken() {
        let service = createService();
        let store = findChild(service, "settingsSecretStore");
        let confirmed = "ghp_" + "a".repeat(36);
        store.token = confirmed;
        service.persistToken("ghp_bad;input");
        verify(service.tokenValidationError.length > 0);
        compare(store.token, confirmed);
        compare(store.isStoring, false);
        compare(store._pendingStoreToken, "");
        service.destroy();
    }
    // Consecutive invalid edits with the same explanation must never clear and re-show it.
    function test_liveErrorDoesNotFlashBetweenEdits() {
        let service = createService();
        service.updateTokenDraft("ghp_short");
        let changes = 0;
        service.displayedTokenValidationErrorChanged.connect(function () {
            changes++;
        });
        let message = service.displayedTokenValidationError;
        for (let value of ["ghp_shorter", "ghp_stillshort", "ghp_moreletters"]) {
            service.updateTokenDraft(value);
            compare(service.displayedTokenValidationError, message);
        }
        compare(changes, 0);
        service.updateTokenDraft("ghp_" + "a".repeat(36));
        compare(service.displayedTokenValidationError, "");
        compare(changes, 1);
        service.destroy();
    }
    // Validation is immediate, but whitespace and persistence still wait for completion.
    function test_liveFeedbackPreservesWhitespaceUntilCompletion() {
        let service = createService();
        let store = findChild(service, "settingsSecretStore");
        let draft = "  ghp_short  ";
        service.updateTokenDraft(draft);
        verify(service.tokenValidationError.length > 0);
        compare(service.displayedTokenValidationError, service.tokenValidationError);
        wait(650);
        compare(service.tokenValue, draft);
        compare(service.displayedTokenValidationError, service.tokenValidationError);
        compare(store.isStoring, false);
        service.finishTokenEdit(draft);
        compare(service.tokenValue, "ghp_short");
        verify(service.displayedTokenValidationError.length > 0);
        wait(50);
        verify(service.displayedTokenValidationError.length > 0);
        let valid = "ghp_" + "a".repeat(36);
        service.updateTokenDraft(" " + valid + " ");
        compare(service.displayedTokenValidationError, "");
        store.tokenStored(true, "Token saved to Secret Service.");
        store.tokenCleared(true, "Token removed from Secret Service.");
        compare(service.tokenStatusMessage, "");
        compare(service.tokenValue, " " + valid + " ");
        service.finishTokenEdit(service.tokenValue);
        compare(service.tokenValue, valid);
        compare(service.displayedTokenValidationError, "");
        compare(store._pendingStoreToken, valid);
        compare(store.isStoring, true);
        service.destroy();
    }
    // A corrected, trimmed token reaches Secret Service while empty input still means removal.
    function test_validInputAndEmptyRemoval() {
        let service = createService();
        let store = findChild(service, "settingsSecretStore");
        let valid = "ghp_" + "a".repeat(36);
        service.persistToken("ghp_short");
        service.persistToken(" " + valid + "\n");
        compare(service.tokenValidationError, "");
        compare(service.tokenValue, valid);
        compare(store.isStoring, true);
        compare(store._pendingStoreToken, valid);
        service.destroy();

        service = createService();
        store = findChild(service, "settingsSecretStore");
        service.persistToken("  ");
        compare(service.tokenValidationError, "");
        compare(service.tokenStatusMessage, "");
        compare(store._pendingStoreToken, "");
        service.destroy();
    }

    name: "SettingsService"
}
