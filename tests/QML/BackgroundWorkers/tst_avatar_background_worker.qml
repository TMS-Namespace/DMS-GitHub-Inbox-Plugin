// tst_avatar_background_worker.qml - tests avatar queue state and request signals.

import QtQuick
import QtTest
import "../../../src/QML/BackgroundWorkers"

TestCase {
    function createWorker() {
        let component = Qt.createComponent("../../../src/QML/BackgroundWorkers/AvatarBackgroundWorker.qml");
        compare(component.status, Component.Ready, component.errorString());
        let worker = component.createObject(this, {
            cacheReady: true
        });
        downloadRequestSpy.target = worker;
        downloadRequestSpy.clear();
        return worker;
    }
    function test_failedDownloadIsNotImmediatelyRetried() {
        let worker = createWorker();
        let avatarUrl = "https://avatars.githubusercontent.com/octocat?size=128";
        worker.queueAvatarDownload("octocat", avatarUrl);
        worker.onAvatarDownloadFinished("octocat", "", 0, false);
        worker.queueAvatarDownload("octocat", avatarUrl);
        compare(downloadRequestSpy.count, 1);
        worker.destroy();
    }
    function test_requestQueueDeduplicatesActiveLogin() {
        let worker = createWorker();
        let avatarUrl = "https://avatars.githubusercontent.com/octocat?size=128";
        worker.queueAvatarDownload("octocat", avatarUrl);
        worker.queueAvatarDownload("octocat", avatarUrl);
        compare(downloadRequestSpy.count, 1);
        compare(downloadRequestSpy.signalArguments[0][0], "octocat");
        compare(downloadRequestSpy.signalArguments[0][1], avatarUrl);
        worker.onAvatarDownloadFinished("octocat", "file:///tmp/octocat.png", 0, true);
        compare(worker.avatarLocalPaths.octocat, "file:///tmp/octocat.png");
        worker.destroy();
    }

    name: "AvatarBackgroundWorker"

    Component {
        id: workerComponent

        AvatarBackgroundWorker {
            cacheReady: true
        }
    }
    SignalSpy {
        id: downloadRequestSpy

        signalName: "avatarDownloadRequested"
    }
}
