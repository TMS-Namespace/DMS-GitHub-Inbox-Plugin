// tst_contracts.qml - verifies contract types expose typed data-holder defaults.

import QtQuick
import QtTest

TestCase {
    function createContract(relativePath) {
        let component = Qt.createComponent(relativePath);
        compare(component.status, Component.Ready, component.errorString());
        return component.createObject(this);
    }
    function test_authorContractDefaults() {
        let author = createContract("../../../src/QML/Contracts/Author.qml");
        compare(author.login, "");
        compare(author.avatarUrl, "");
        compare(author.htmlUrl, "");
        author.destroy();
    }
    function test_cachePayloadHasTypedDefaults() {
        let payload = createContract("../../../src/QML/Contracts/CachePayload.qml");
        compare(payload.version, 0);
        compare(payload.lastFetched, 0);
        compare(payload.notifications.length, 0);
        compare(Object.keys(payload.doneThreadState).length, 0);
        payload.destroy();
    }
    function test_doneThreadStateIsADataHolder() {
        let state = createContract("../../../src/QML/Contracts/DoneThreadState.qml");
        compare(Object.keys(state.threadIds).length, 0);
        state.threadIds = {
            "thread-a": {
                source: "local"
            }
        };
        compare(state.threadIds["thread-a"].source, "local");
        state.destroy();
    }
    function test_inboxMessageHasTypedDefaults() {
        let message = createContract("../../../src/QML/Contracts/InboxMessage.qml");
        compare(message.threadId, "");
        compare(message.unread, false);
        compare(message.updatedAtMs, 0);
        compare(message.title, "(untitled)");
        message.destroy();
    }

    name: "Contracts"
}
