// tst_inbox_refresh_coordinator.qml - tests inbox refresh scheduling rules.

import QtQuick
import QtTest
import "../../../src/QML/Services"

TestCase {
    id: testCase

    property int fetchCount: 0
    property bool lastFetchWasManual: false
    property int missingTokenRequests: 0

    // Each scenario starts with idle work and no deferred refresh from an earlier test.
    function init() {
        coordinator.token = "token";
        coordinator.isRefreshBusy = false;
        coordinator.popoutVisible = false;
        coordinator.refreshAfterPopoutClose = false;
        coordinator.scheduledDelayMs = 0;
        fetchCount = 0;
    }
    function test_manualRefreshReportsMissingToken() {
        missingTokenRequests = 0;
        coordinator.token = "";

        coordinator.refreshNow();

        compare(missingTokenRequests, 1);
    }
    function test_refreshIsDeferredUntilPopoutCloses() {
        fetchCount = 0;
        coordinator.token = "token";
        coordinator.popoutVisible = true;

        coordinator.requestFetch(false);

        compare(fetchCount, 0);
        verify(coordinator.refreshAfterPopoutClose);
        verify(coordinator.resumeAfterPopoutClose());
        verify(!coordinator.refreshAfterPopoutClose);
    }
    function test_refreshRunsOnlyWhenIdleAndTokenExists() {
        fetchCount = 0;
        coordinator.token = "token";
        coordinator.popoutVisible = false;
        coordinator.isRefreshBusy = true;
        coordinator.requestFetch(false);
        compare(fetchCount, 0);

        coordinator.isRefreshBusy = false;
        coordinator.requestFetch(false);
        compare(fetchCount, 1);
        compare(lastFetchWasManual, false);

        coordinator.requestFetch(true);
        compare(fetchCount, 2);
        compare(lastFetchWasManual, true);
    }
    function test_restoreSchedule(data) {
        coordinator.restoreSchedule(data.timestamp, data.interval, 200000);
        compare(fetchCount, data.delay ? 0 : 1);
        compare(coordinator.scheduledDelayMs, data.delay || coordinator.pollIntervalMs);
        // An explicit refresh is never held back by a restored startup delay.
        coordinator.refreshNow();
        compare(lastFetchWasManual, true);
    }
    function test_restoreSchedule_data() {
        return [
            {
                tag: "fresh",
                timestamp: 190000,
                interval: 120000,
                delay: 110000
            },
            {
                tag: "expired",
                timestamp: 10000,
                interval: 120000,
                delay: 0
            },
            {
                tag: "future",
                timestamp: 210000,
                interval: 120000,
                delay: 0
            },
            {
                tag: "missing",
                timestamp: 0,
                interval: 120000,
                delay: 0
            },
            {
                tag: "settingsChanged",
                timestamp: 190000,
                interval: 60000,
                delay: 0
            }
        ];
    }

    name: "InboxRefreshCoordinator"

    QtObject {
        id: fetchService

        property bool isLoading: false

        function cancel() {
        }
        function fetch(manual) {
            testCase.fetchCount++;
            testCase.lastFetchWasManual = manual;
        }
    }
    QtObject {
        id: authorWorker

        property bool isBusy: false
        property var requestQueue: []
        property int requestsInFlight: 0

        function resetState() {
        }
    }
    QtObject {
        id: cacheCoordinator

        property bool isDownloadingAvatars: false

        function resetAvatarDownloads() {
        }
    }
    QtObject {
        id: operations

        property bool isBusy: false

        function resetState() {
        }
    }
    QtObject {
        id: enrichmentService

        function cancelBackgroundEnrichment() {
        }
        function cancelPendingScans() {
        }
    }
    InboxRefreshCoordinator {
        id: coordinator

        authorWorker: authorWorker
        automaticScheduling: false
        cacheCoordinator: cacheCoordinator
        enrichmentService: enrichmentService
        fetchService: fetchService
        operations: operations
        pollIntervalMs: 120000

        onMissingTokenRequested: testCase.missingTokenRequests++
    }
}
