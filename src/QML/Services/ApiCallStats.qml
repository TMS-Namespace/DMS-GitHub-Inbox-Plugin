// ApiCallStats.qml --- Singleton for tracking GitHub API call statistics.
// Shared between Widget.qml (writer) and Settings.qml (reader).

pragma Singleton

import QtQuick
import ".."

QtObject {
    id: stats

    property var _hourlyRefreshes: []  // [{ms, calls, durationMs}] within last hour
    property var _pruneTimer: Timer {
        interval: GitHubConstants.statsHourlyPruneIntervalMs
        repeat: true
        running: GitHubConstants.apiCallStatsEnabled

        onTriggered: stats._prune()
    }
    property real _refreshStartMs: 0

    // -- Private state -------------------------------------------------------
    property var _timestamps: []       // one entry per API call (ms)
    property real _totalDurationMs: 0   // lifetime ms sum across completed refreshes

    property real lastHourAvgDurationSecs: 0

    // -- Last-hour window ----------------------------------------------------
    property int lastHourCalls: 0
    property int lastHourRefreshCount: 0

    // -- Last completed refresh snapshot -------------------------------------
    property int lastSessionCalls: 0
    property real lastSessionDurationSecs: 0
    property bool lastSessionSleepDetected: false

    // -- Current in-progress session -----------------------------------------
    property int sessionCalls: 0
    property real totalAvgDurationSecs: 0

    // -- All-time totals -----------------------------------------------------
    property int totalCalls: 0
    property int totalRefreshCount: 0

    // -- Private -------------------------------------------------------------

    // Keep only statistics inside the configured UTC retention window.
    function _prune() {
        if (!GitHubConstants.apiCallStatsEnabled)
            return;
        let cutoff = Date.now() - GitHubConstants.statsOneHourWindowMs;  // 1 hour in ms

        // API-call timestamp window
        let ts = _timestamps;
        let i = 0;
        while (i < ts.length && ts[i] < cutoff)
            i++;
        if (i > 0)
            _timestamps = ts.slice(i);
        lastHourCalls = _timestamps.length;

        // Per-refresh hourly window
        let hrs = _hourlyRefreshes;
        let j = 0;
        while (j < hrs.length && hrs[j].ms < cutoff)
            j++;
        if (j > 0)
            _hourlyRefreshes = hrs.slice(j);

        lastHourRefreshCount = _hourlyRefreshes.length;

        if (lastHourRefreshCount > 0) {
            let sum = 0;
            for (let index = 0; index < _hourlyRefreshes.length; index++)
                sum += _hourlyRefreshes[index].durationMs;
            lastHourAvgDurationSecs = Math.round(sum / lastHourRefreshCount / 100) / 10;
        } else {
            lastHourAvgDurationSecs = 0;
        }

        totalAvgDurationSecs = (totalRefreshCount > 0) ? Math.round(_totalDurationMs / totalRefreshCount / 100) / 10 : 0;
    }

    // Record `count` API calls that just fired.
    function recordCalls(count) {
        if (!GitHubConstants.apiCallStatsEnabled)
            return;
        let n = (count > 0) ? count : 1;
        totalCalls += n;
        sessionCalls += n;

        let now = Date.now();
        let ts = _timestamps.slice();
        for (let i = 0; i < n; i++)
            ts.push(now);
        _timestamps = ts;

        _prune();
    }

    // Call once when a refresh cycle fully completes (success or error).
    function recordRefreshComplete() {
        if (!GitHubConstants.apiCallStatsEnabled || _refreshStartMs <= 0)
            return;
        let durationMs = (_refreshStartMs > 0) ? Math.max(0, Date.now() - _refreshStartMs) : 0;

        // If the measured duration exceeds the reasonable maximum the machine
        // was almost certainly suspended mid-refresh; skip duration accounting
        // so sleep time never inflates the averages.
        let sleepDetected = durationMs > GitHubConstants.statsMaxReasonableRefreshDurationMs;

        lastSessionCalls = sessionCalls;
        lastSessionSleepDetected = sleepDetected;
        lastSessionDurationSecs = sleepDetected ? 0 : Math.round(durationMs / 100) / 10;

        if (!sleepDetected) {
            let now = Date.now();
            let hrs = _hourlyRefreshes.slice();
            hrs.push({
                ms: now,
                calls: sessionCalls,
                durationMs: durationMs
            });
            _hourlyRefreshes = hrs;

            totalRefreshCount += 1;
            _totalDurationMs += durationMs;
        }

        _refreshStartMs = 0;
        _prune();
    }

    // -- Public API ----------------------------------------------------------

    // Call at the very start of each fetchNotifications().
    function resetSession() {
        if (!GitHubConstants.apiCallStatsEnabled)
            return;
        sessionCalls = 0;
        _refreshStartMs = Date.now();
    }
}
