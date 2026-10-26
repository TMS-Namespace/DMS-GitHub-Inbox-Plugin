// CalendarTime.test.js - calendar-first age labels and grouping use identical UTC boundaries.

"use strict";

const assert = require("node:assert/strict");
const { createRegistry, loadModule } = require("../../../audit/QmlJavaScript");
const registry = createRegistry();
const calendar = loadModule("src/JS/Helpers/CalendarTime.js", registry);
const github = loadModule("src/JS/Integrations/GitHub/GitHubHelpers.js", registry);

const scenarios = [
    ["2026-10-22T12:00:00Z", "2026-10-22T11:59:55Z", "today", "just now"],
    ["2026-10-22T12:00:00Z", "2026-10-22T11:59:40Z", "today", "20 sec ago"],
    ["2026-10-22T12:00:00Z", "2026-10-22T11:58:00Z", "today", "2 min ago"],
    ["2026-10-22T12:00:00Z", "2026-10-22T09:00:00Z", "today", "3 hr ago"],
    // Calendar midnight matters even when much less than 24 hours has elapsed.
    ["2026-10-22T00:10:00Z", "2026-10-21T23:50:00Z", "yesterday", "1 day ago"],
    // Only 25 hours have elapsed, but these dates are two calendar days apart.
    ["2026-10-22T00:30:00Z", "2026-10-20T23:30:00Z", "two_days_ago", "2 days ago"],
    ["2026-10-22T12:00:00Z", "2026-10-19T00:00:00Z", "this_week", "3 days ago"],
    ["2026-10-19T00:30:00Z", "2026-10-18T23:30:00Z", "previous_week", "1 week ago"],
    ["2026-10-22T12:00:00Z", "2026-10-05T12:00:00Z", "two_weeks_ago", "2 weeks ago"],
    ["2026-10-30T12:00:00Z", "2026-10-01T12:00:00Z", "this_month", "4 weeks ago"],
    ["2026-10-01T00:30:00Z", "2026-09-30T23:30:00Z", "previous_month", "1 month ago"],
    ["2026-10-22T12:00:00Z", "2026-08-31T23:59:00Z", "this_year", "2 months ago"],
    ["2026-01-01T00:30:00Z", "2025-12-31T23:30:00Z", "previous_year", "1 year ago"],
    ["2026-01-01T00:00:00Z", "2024-12-31T23:59:00Z", "older", "2 years ago"],
    ["2026-03-01T00:00:00Z", "2026-02-28T23:59:00Z", "previous_month", "1 month ago"],
    ["2024-03-01T00:00:00Z", "2024-02-29T23:59:00Z", "previous_month", "1 month ago"],
    // An explicit offset is converted to UTC before comparing calendar dates.
    ["2026-10-22T00:10:00Z", "2026-10-22T01:50:00+02:00", "yesterday", "1 day ago"]
];
const previousTimezone = process.env.TZ;
try {
    for (const timezone of ["UTC", "Europe/Stockholm", "America/Los_Angeles", "Pacific/Auckland"]) {
        process.env.TZ = timezone;
        for (const [reference, updatedAt, bucket, label] of scenarios) {
            const referenceMs = Date.parse(reference);
            assert.equal(
                calendar.bucketForTimestamp(Date.parse(updatedAt), referenceMs),
                bucket,
                `${timezone}: ${updatedAt}`
            );
            assert.equal(calendar.relativeTimeFromIso(updatedAt, referenceMs), label, `${timezone}: ${updatedAt}`);
            assert.equal(github.relativeTimeFromIso(updatedAt, referenceMs), label);
        }
    }
} finally {
    if (previousTimezone === undefined) delete process.env.TZ;
    else process.env.TZ = previousTimezone;
}

for (const [reference, expectedYears] of [
    ["2026-01-01T12:00:00Z", 2],
    ["2026-10-22T12:00:00Z", 1]
]) {
    const referenceMs = Date.parse(reference);
    const timestamp = referenceMs - 500 * 86400000;
    assert.equal(
        calendar.relativeTimeFromIso(new Date(timestamp).toISOString(), referenceMs),
        `${expectedYears} year${expectedYears === 1 ? "" : "s"} ago`
    );
}
assert.equal(calendar.relativeTimeFromIso("", 0), "");
assert.equal(calendar.relativeTimeFromIso("invalid-date", 0), "");
assert.equal(calendar.bucketForTimestamp(NaN, 0), "older");
assert.equal(calendar.relativeTimeFromIso("2026-10-22T12:01:00Z", Date.parse("2026-10-22T12:00:00Z")), "just now");
console.log("UTC calendar age and grouping tests passed");
