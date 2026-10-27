// tst_avatar_download_worker.qml - bounds retries and completion for built-in avatar downloads.

import QtQuick
import QtTest
import "../../../src/QML/BackgroundWorkers"

TestCase {
    id: testCase

    // Keep command execution stubbed while exercising real retry and completion state.
    function createWorker() {
        let component = Qt.createComponent("../../../src/QML/BackgroundWorkers/AvatarDownloadWorker.qml");
        compare(component.status, Component.Ready, component.errorString());
        let worker = component.createObject(testCase, {
            autoStart: false,
            maximumRetries: 2,
            retryDelayMs: 1,
            retryWindowMs: 1000
        });
        finished.target = worker;
        finished.clear();
        return worker;
    }
    // A long first attempt must not start retries outside the provider's time window.
    function test_expiredRetryWindow() {
        let worker = createWorker();
        worker.startAttempt();
        worker.startedAtMs = Date.now() - 2000;
        worker.handleExit(1);
        compare(worker.attempts, 1);
        compare(finished.count, 1);
        compare(finished.signalArguments[0][0], false);
        worker.destroy();
    }
    // The provider retry count caps attempts even when failures arrive immediately.
    function test_retryCountIsBounded() {
        let worker = createWorker();
        worker.startAttempt();
        worker.handleExit(1);
        tryCompare(worker, "attempts", 2);
        worker.handleExit(1);
        tryCompare(worker, "attempts", 3);
        worker.handleExit(1);
        compare(finished.count, 1);
        compare(finished.signalArguments[0][0], false);
        compare(worker.completed, true);
        worker.destroy();
    }
    // A recovered request reports success only once and does not continue retrying.
    function test_retryThenSuccess() {
        let worker = createWorker();
        worker.startAttempt();
        worker.handleExit(1);
        tryCompare(worker, "attempts", 2);
        compare(finished.count, 0);
        worker.handleExit(0);
        compare(finished.count, 1);
        compare(finished.signalArguments[0][0], true);
        worker.handleExit(1);
        compare(finished.count, 1);
        worker.destroy();
    }

    name: "AvatarDownloadWorker"

    SignalSpy {
        id: finished

        signalName: "finished"
    }
}
