// tst_plugin_cache.qml - verifies remote freshness is not advanced by local message edits.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    // A failed backup must keep the original cache protected from later writes.
    function test_failedBackupDisablesWritesAndReportsFailure() {
        let cache = createTemporaryObject(cacheFactory, this);
        failure.target = cache;
        failure.clear();
        cache._onDamagedCacheBackupDone(1, "The saved cache could not be loaded.", "/tmp/unused-backup");
        compare(failure.count, 1);
        verify(cache._preserveDamagedCache);
        verify(String(failure.signalArguments[0][0]).indexOf("cache writes are disabled") >= 0);
    }
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
    // Staged author and avatar data must be flushed before a cache snapshot is serialized.
    function test_stagedMetadataFlushRetainsAllUpdates() {
        let cache = createTemporaryObject(cacheFactory, this);
        cache.updateChangedAuthors({
            "42": [
                {
                    login: "person"
                }
            ]
        });
        cache.updateAuthorFetchedAt("42", "marker");
        cache.updateAvatarLocalPath("person", "file:///tmp/person.png");
        compare(cache.getAuthorFetchedAt("42"), "marker");
        verify(cache.hasLocalAvatar("person"));
        verify(cache._flushPendingMetadata(false));
        compare(cache.cachedAuthorsByThread["42"][0].login, "person");
        compare(cache.cachedAuthorFetchedAt["42"], "marker");
        compare(cache.avatarLocalPaths.person, "file:///tmp/person.png");
        verify(!cache._flushPendingMetadata(false));
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
