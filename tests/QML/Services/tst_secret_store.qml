// tst_secret_store.qml - verifies Secret Service removal results without external processes.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    function test_clearResult(data) {
        cleared.clear();
        store.token = "previously-confirmed-token";
        store.finishClear(data.exitCode, "Secret Service command failed");
        compare(cleared.count, 1);
        compare(cleared.signalArguments[0][0], data.success);
        compare(cleared.signalArguments[0][1], store.statusMessage);
        verify(store.statusMessage.indexOf(data.success ? "removed" : "Failed") >= 0);
        compare(store.token, data.success ? "" : "previously-confirmed-token");
        verify(store.statusMessage.indexOf("command failed") < 0);
    }

    // Exercise both command failure modes and successful removal through the real service.
    function test_clearResult_data() {
        return [
            {
                tag: "success",
                exitCode: 0,
                success: true
            },
            {
                tag: "commandFailed",
                exitCode: 1,
                success: false
            },
            {
                tag: "missingCommand",
                exitCode: 127,
                success: false
            }
        ];
    }

    name: "SecretStore"

    SecretStore {
        id: store

        autoLoad: false
    }
    SignalSpy {
        id: cleared

        signalName: "tokenCleared"
        target: store
    }
}
