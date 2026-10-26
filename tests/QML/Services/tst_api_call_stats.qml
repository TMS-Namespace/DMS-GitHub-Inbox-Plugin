// tst_api_call_stats.qml - verifies shared statistics and epoch-safe refresh duration accounting.
import QtQuick
import QtTest
import "../../../src/QML/Services" as Services
import "../../../src/QML/Views" as Views
import "../../../src/QML" as Plugin

TestCase {
    id: testCase

    function cleanup() {
        init();
    }

    // A singleton must start with fresh state for each statistics scenario.
    function init() {
        Plugin.ApiCallStats._hourlyRefreshes = [];
        Plugin.ApiCallStats._timestamps = [];
        Plugin.ApiCallStats._refreshStartMs = 0;
        Plugin.ApiCallStats._totalDurationMs = 0;
        Plugin.ApiCallStats.sessionCalls = 0;
        Plugin.ApiCallStats.totalCalls = 0;
        Plugin.ApiCallStats.totalRefreshCount = 0;
        Plugin.ApiCallStats.lastSessionCalls = 0;
        Plugin.ApiCallStats.lastSessionDurationSecs = 0;
        Plugin.ApiCallStats.lastSessionSleepDetected = false;
        Plugin.ApiCallStats._prune();
    }
    function test_duplicateCompletionDoesNotEraseOrCountTheSnapshotAgain() {
        Plugin.ApiCallStats.resetSession();
        Plugin.ApiCallStats.recordCalls(3);
        Plugin.ApiCallStats.recordRefreshComplete();
        Plugin.ApiCallStats.recordRefreshComplete();
        compare(Plugin.ApiCallStats.totalRefreshCount, 1);
        compare(Plugin.ApiCallStats.lastSessionCalls, 3);
    }
    function test_expiredHourlyRecordsDoNotEraseLifetimeTotals() {
        Plugin.ApiCallStats.resetSession();
        Plugin.ApiCallStats.recordCalls(2);
        Plugin.ApiCallStats.recordRefreshComplete();
        let expired = Date.now() - Plugin.GitHubConstants.statsOneHourWindowMs - 1000;
        Plugin.ApiCallStats._timestamps = [expired, expired];
        Plugin.ApiCallStats._hourlyRefreshes = [
            {
                ms: expired,
                calls: 2,
                durationMs: 1500
            }
        ];
        Plugin.ApiCallStats._prune();
        compare(Plugin.ApiCallStats.lastHourCalls, 0);
        compare(Plugin.ApiCallStats.lastHourRefreshCount, 0);
        compare(Plugin.ApiCallStats.totalCalls, 2);
        compare(Plugin.ApiCallStats.totalRefreshCount, 1);
    }
    function test_lifetimeDurationDoesNotOverflowA32BitInteger() {
        Plugin.ApiCallStats._totalDurationMs = 3000000000;
        Plugin.ApiCallStats.resetSession();
        Plugin.ApiCallStats._refreshStartMs = Date.now() - 1500;
        Plugin.ApiCallStats.recordRefreshComplete();
        verify(Plugin.ApiCallStats._totalDurationMs >= 3000001500);
        verify(Plugin.ApiCallStats.totalAvgDurationSecs > 0);
    }
    function test_refreshStartKeepsFullEpochTimestamp() {
        Plugin.ApiCallStats.resetSession();
        verify(Math.abs(Plugin.ApiCallStats._refreshStartMs - Date.now()) < 1000);
        Plugin.ApiCallStats.recordCalls(3);
        Plugin.ApiCallStats.recordRefreshComplete();
        compare(Plugin.ApiCallStats.lastSessionCalls, 3);
        compare(Plugin.ApiCallStats.lastSessionSleepDetected, false);
        verify(Plugin.ApiCallStats.totalRefreshCount > 0);
    }
    function test_settingsShowCallsDuringAndAfterARefresh() {
        let view = createTemporaryObject(statsView, testCase);
        verify(view);
        compare(view.rows[1].calls, "-");
        Plugin.ApiCallStats.resetSession();
        Plugin.ApiCallStats.recordCalls(4);
        compare(view.rows[1].calls, "4");
        compare(view.rows[2].calls, "4");
        compare(findChild(view, "apiStatsCalls-Last hour").text, "4");
        compare(findChild(view, "apiStatsCalls-All time").text, "4");
        Plugin.ApiCallStats._refreshStartMs = Date.now() - 1500;
        Plugin.ApiCallStats.recordRefreshComplete();
        compare(view.rows[0].calls, "4");
        compare(view.rows[1].refreshes, "1");
        compare(view.rows[2].refreshes, "1");
        verify(Plugin.ApiCallStats.lastSessionDurationSecs >= 1.5);
        verify(Plugin.ApiCallStats.lastSessionDurationSecs < 2);
        verify(view.rows[0].average !== "-");
        verify(view.rows[1].average !== "-");
        verify(view.rows[2].average !== "-");
        compare(findChild(view, "apiStatsCalls-Last refresh").text, "4");
        compare(findChild(view, "apiStatsDuration-Last refresh").text, view.rows[0].average);
    }
    function test_sleepSkipsDurationButKeepsRecordedCallsVisible() {
        let view = createTemporaryObject(statsView, testCase);
        Plugin.ApiCallStats.resetSession();
        Plugin.ApiCallStats._refreshStartMs = Date.now() - Plugin.GitHubConstants.statsMaxReasonableRefreshDurationMs - 1000;
        Plugin.ApiCallStats.recordCalls(2);
        Plugin.ApiCallStats.recordRefreshComplete();
        compare(Plugin.ApiCallStats.lastSessionSleepDetected, true);
        compare(Plugin.ApiCallStats.totalRefreshCount, 0);
        compare(view.rows[0].average, "-");
        compare(view.rows[1].calls, "2");
        compare(view.rows[2].calls, "2");
    }
    function test_statisticsUseOneSharedInstance() {
        compare(Plugin.ApiCallStats, Services.ApiCallStats);
    }

    name: "ApiCallStats"

    Component {
        id: statsView

        Views.SettingsApiStatsView {
            width: 500
        }
    }
}
