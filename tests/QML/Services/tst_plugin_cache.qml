// tst_plugin_cache.qml - verifies remote freshness is not advanced by local message edits.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    // A failed reset must not silently overwrite the files that could not be removed.
    function test_failedClearDisablesWritesAndReportsFailure() {
        let cache = createTemporaryObject(cacheFactory, this);
        failure.target = cache;
        failure.clear();
        cache._onClearCacheDone(1, false);
        compare(failure.count, 1);
        verify(cache._preserveDamagedCache);
    }
    // Leave storage uninitialized so this policy test cannot start external I/O.
    function test_localEditsPreserveRemoteFetchTime() {
        let cache = createTemporaryObject(cacheFactory, this);
        cache.updateMessages([
            {
                threadId: "42",
                unread: true
            }
        ], 1000);
        compare(cache.cachedTimestamp, 1000);
        cache.updateMessages([
            {
                threadId: "42",
                unread: false
            }
        ]);
        compare(cache.cachedTimestamp, 1000);
        cache.updateMessages([], 2000);
        compare(cache.cachedTimestamp, 2000);
    }

    name: "PluginCache"

    Component {
        id: cacheFactory

        PluginCache {
            cacheWorkerEnabled: false
        }
    }
    SignalSpy {
        id: failure

        signalName: "cacheFailure"
    }
}
