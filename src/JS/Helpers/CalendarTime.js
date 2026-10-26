// CalendarTime.js - shared UTC calendar boundaries for notification buckets and age labels.
// Calendar units take priority over elapsed duration; weeks start on Monday.

.pragma library

// Represent a UTC calendar date independently of the local timezone and daylight saving.
function utcDayNumber(value) {
    return Math.floor(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate()) / 86400000);
}

// Compare the same calendar units for grouping and labels, retaining seconds for today's messages.
function difference(timestamp, referenceMs) {
    var currentTimestamp = referenceMs === undefined ? Date.now() : Number(referenceMs);
    if (!Number.isFinite(timestamp) || !Number.isFinite(currentTimestamp)) return null;
    var updated = new Date(timestamp);
    var now = new Date(currentTimestamp);
    if (!Number.isFinite(updated.getTime()) || !Number.isFinite(now.getTime())) return null;
    var currentDay = utcDayNumber(now);
    var updatedDay = utcDayNumber(updated);
    var currentWeek = currentDay - ((now.getUTCDay() + 6) % 7);
    var updatedWeek = updatedDay - ((updated.getUTCDay() + 6) % 7);
    return {
        years: now.getUTCFullYear() - updated.getUTCFullYear(),
        months: now.getUTCMonth() - updated.getUTCMonth(),
        weeks: Math.round((currentWeek - updatedWeek) / 7),
        days: currentDay - updatedDay,
        seconds: Math.max(0, Math.floor((currentTimestamp - timestamp) / 1000))
    };
}

// Preserve the grouping policy by selecting the largest differing calendar unit first.
function bucketForTimestamp(timestamp, referenceMs) {
    var age = difference(timestamp, referenceMs);
    if (!age) return "older";
    if (age.years > 0) return age.years === 1 ? "previous_year" : "older";
    if (age.years < 0) return "this_year";
    if (age.months > 0) return age.months === 1 ? "previous_month" : "this_year";
    if (age.months < 0) return "this_month";
    if (age.weeks === 1) return "previous_week";
    if (age.weeks === 2) return "two_weeks_ago";
    if (age.weeks > 2) return "this_month";
    if (age.days === 0) return "today";
    if (age.days === 1) return "yesterday";
    if (age.days === 2) return "two_days_ago";
    return "this_week";
}

// Format a calendar-unit count without approximating months or years as durations.
function unitLabel(count, unit) {
    return count + " " + unit + (count === 1 ? "" : "s") + " ago";
}

// Use the grouping calendar boundaries before formatting sub-day elapsed time.
function relativeTimeFromIso(isoDate, referenceMs) {
    if (!isoDate) return "";
    var timestamp = Date.parse(isoDate);
    var currentTimestamp = referenceMs === undefined ? Date.now() : Number(referenceMs);
    var age = difference(timestamp, currentTimestamp);
    if (!age) return "";
    if (timestamp > currentTimestamp) return "just now";
    if (age.years > 0) return unitLabel(age.years, "year");
    if (age.months > 0) return unitLabel(age.months, "month");
    if (age.weeks > 0) return unitLabel(age.weeks, "week");
    if (age.days > 0) return unitLabel(age.days, "day");
    if (age.seconds < 10) return "just now";
    if (age.seconds < 60) return age.seconds + " sec ago";
    var minutes = Math.floor(age.seconds / 60);
    if (minutes < 60) return minutes + " min ago";
    return Math.floor(minutes / 60) + " hr ago";
}
