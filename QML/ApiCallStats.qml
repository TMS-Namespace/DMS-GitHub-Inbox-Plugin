// ApiCallStats.qml – Singleton for tracking GitHub API call statistics.
// Shared between Widget.qml (writer) and Settings.qml (reader).

pragma Singleton

import QtQuick

QtObject {
    id: stats

    // -- Current in-progress session -----------------------------------------
    property int  sessionCalls: 0
    property int  _refreshStartMs: 0

    // -- Last completed refresh snapshot -------------------------------------
    property int  lastSessionCalls: 0
    property real lastSessionDurationSecs: 0
    property bool lastSessionSleepDetected: false

    // -- Last-hour window ----------------------------------------------------
    property int  lastHourCalls: 0
    property int  lastHourRefreshCount: 0
    property real lastHourAvgDurationSecs: 0

    // -- All-time totals -----------------------------------------------------
    property int  totalCalls: 0
    property int  totalRefreshCount: 0
    property real totalAvgDurationSecs: 0

    // -- Private state -------------------------------------------------------
    property var _timestamps: []       // one entry per API call (ms)
    property var _hourlyRefreshes: []  // [{ms, calls, durationMs}] within last hour
    property int _totalDurationMs: 0   // lifetime ms sum across completed refreshes

    property var _pruneTimer: Timer {
        interval: Constants.statsHourlyPruneIntervalMs
        running: true
        repeat: true
        onTriggered: stats._prune()
    }

    // -- Public API ----------------------------------------------------------

    // Call at the very start of each fetchNotifications().
    function resetSession() {
        sessionCalls    = 0
        _refreshStartMs = Date.now()
    }

    // Record `count` API calls that just fired.
    function recordCalls(count) {
        var n = (count > 0) ? count : 1
        totalCalls   += n
        sessionCalls += n

        var now = Date.now()
        var ts = _timestamps.slice()
        for (var i = 0; i < n; i++)
            ts.push(now)
        _timestamps = ts

        _prune()
    }

    // Call once when a refresh cycle fully completes (success or error).
    function recordRefreshComplete() {
        var durationMs = (_refreshStartMs > 0)
            ? Math.max(0, Date.now() - _refreshStartMs)
            : 0

        // If the measured duration exceeds the reasonable maximum the machine
        // was almost certainly suspended mid-refresh; skip duration accounting
        // so sleep time never inflates the averages.
        var sleepDetected = durationMs > Constants.statsMaxReasonableRefreshDurationMs

        lastSessionCalls         = sessionCalls
        lastSessionSleepDetected = sleepDetected
        lastSessionDurationSecs  = sleepDetected ? 0 : Math.round(durationMs / 100) / 10

        if (!sleepDetected) {
            var now = Date.now()
            var hrs = _hourlyRefreshes.slice()
            hrs.push({ ms: now, calls: sessionCalls, durationMs: durationMs })
            _hourlyRefreshes = hrs

            totalRefreshCount += 1
            _totalDurationMs  += durationMs
        }

        _refreshStartMs = 0
        _prune()
    }

    // -- Private -------------------------------------------------------------

    function _prune() {
        var cutoff = Date.now() - Constants.statsOneHourWindowMs  // 1 hour in ms

        // API-call timestamp window
        var ts = _timestamps
        var i = 0
        while (i < ts.length && ts[i] < cutoff)
            i++
        if (i > 0)
            _timestamps = ts.slice(i)
        lastHourCalls = _timestamps.length

        // Per-refresh hourly window
        var hrs = _hourlyRefreshes
        var j = 0
        while (j < hrs.length && hrs[j].ms < cutoff)
            j++
        if (j > 0)
            _hourlyRefreshes = hrs.slice(j)

        lastHourRefreshCount = _hourlyRefreshes.length

        if (lastHourRefreshCount > 0) {
            var sum = 0
            for (var k = 0; k < _hourlyRefreshes.length; k++)
                sum += _hourlyRefreshes[k].durationMs
            lastHourAvgDurationSecs = Math.round(sum / lastHourRefreshCount / 100) / 10
        } else {
            lastHourAvgDurationSecs = 0
        }

        totalAvgDurationSecs = (totalRefreshCount > 0)
            ? Math.round(_totalDurationMs / totalRefreshCount / 100) / 10
            : 0
    }
}
