// DateGroupingModel.qml - filters and groups inbox messages by date bucket.

import QtQuick
import ".."

QtObject {
    id: model

    readonly property var dateGroups: [
        {
            key: "today",
            label: "Today"
        },
        {
            key: "yesterday",
            label: "Yesterday"
        },
        {
            key: "two_days_ago",
            label: "Two days ago"
        },
        {
            key: "this_week",
            label: "This week"
        },
        {
            key: "previous_week",
            label: "Previous week"
        },
        {
            key: "two_weeks_ago",
            label: "Two weeks ago"
        },
        {
            key: "this_month",
            label: "This month"
        },
        {
            key: "previous_month",
            label: "Previous month"
        },
        {
            key: "this_year",
            label: "This Year"
        },
        {
            key: "previous_year",
            label: "Previous Year"
        },
        {
            key: "older",
            label: "Older"
        }
    ]
    property var expandedGroups: ({})
    property var expandedGroupsState: ({
            [GitHubConstants.expandedStateDefaultKey]: true
        })
    readonly property var filteredMessages: {
        let result = [];
        for (let index = 0; index < messages.length; index++) {
            let item = messages[index];
            let participated = !!item.participated;

            if (readFilter === "yes" && item.unread)
                continue;
            if (readFilter === "no" && !item.unread)
                continue;
            if (participationFilter === "yes" && !participated)
                continue;
            if (participationFilter === "no" && participated)
                continue;
            result.push(item);
        }
        return _sortMessagesByDateDescending(result);
    }
    property int groupItemLimit: GitHubConstants.defaultGroupItemLimit
    readonly property var groups: _groupMessagesByDate(filteredMessages)
    readonly property bool hasDisplayedMessages: filteredMessages.length > 0
    property var messages: []
    property string participationFilter: "both"       // yes | no | both
    property string readFilter: "both"                // yes | no | both

    signal persistExpandedGroups(var state)

    // Allocate independent arrays for each group so unrelated message groups cannot share state.
    function _createGroup(key, label) {
        return {
            key: key,
            label: label,
            unreadCount: 0,
            items: [],
            allItems: []
        };
    }
    // Choose the largest differing UTC calendar unit before finer-grained date buckets.
    function _dateBucketValue(item, referenceMs) {
        let timestamp = item.updatedAtMs || Date.parse(item.updatedAt || "");
        if (!timestamp)
            return "older";

        let currentTimestamp = Number(referenceMs);
        if (!isFinite(currentTimestamp) || currentTimestamp <= 0)
            currentTimestamp = Date.now();

        let updated = new Date(timestamp);
        let now = new Date(currentTimestamp);
        let calendarYearsAgo = now.getUTCFullYear() - updated.getUTCFullYear();
        if (calendarYearsAgo > 0)
            return calendarYearsAgo === 1 ? "previous_year" : "older";
        if (calendarYearsAgo < 0)
            return "this_year";

        let calendarMonthsAgo = now.getUTCMonth() - updated.getUTCMonth();
        if (calendarMonthsAgo > 0)
            return calendarMonthsAgo === 1 ? "previous_month" : "this_year";
        if (calendarMonthsAgo < 0)
            return "this_month";

        let mondayOffset = (now.getUTCDay() + 6) % 7;
        let weekStart = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - mondayOffset);
        let updatedMondayOffset = (updated.getUTCDay() + 6) % 7;
        let updatedWeekStart = Date.UTC(updated.getUTCFullYear(), updated.getUTCMonth(), updated.getUTCDate() - updatedMondayOffset);
        let calendarWeeksAgo = Math.round((weekStart - updatedWeekStart) / (7 * 24 * 60 * 60 * 1000));
        if (calendarWeeksAgo === 1)
            return "previous_week";
        if (calendarWeeksAgo === 2)
            return "two_weeks_ago";
        if (calendarWeeksAgo > 2)
            return "this_month";

        let calendarDayDiff = _utcDayNumber(now) - _utcDayNumber(updated);
        if (calendarDayDiff === 0)
            return "today";
        if (calendarDayDiff === 1)
            return "yesterday";
        if (calendarDayDiff === 2)
            return "two_days_ago";

        return "this_week";
    }
    // Limit visible rows without losing the full set used by group actions.
    function _groupMessagesByDate(items) {
        let groupsByKey = {};
        for (let groupIndex = 0; groupIndex < dateGroups.length; groupIndex++) {
            let dateGroup = dateGroups[groupIndex];
            groupsByKey[dateGroup.key] = _createGroup(dateGroup.key, dateGroup.label);
        }

        for (let messageIndex = 0; messageIndex < items.length; messageIndex++) {
            let message = items[messageIndex];
            let key = _dateBucketValue(message);
            let group = groupsByKey[key] || groupsByKey.older;

            group.allItems.push(message);
            if (message.unread)
                group.unreadCount++;

            if (group.items.length < groupItemLimit)
                group.items.push(message);
        }

        let result = [];
        for (let resultIndex = 0; resultIndex < dateGroups.length; resultIndex++) {
            let resultGroup = groupsByKey[dateGroups[resultIndex].key];
            if (resultGroup.allItems.length > 0)
                result.push(resultGroup);
        }
        return result;
    }
    // Sort a copy by UTC activity timestamp instead of mutating caller-owned arrays.
    function _sortMessagesByDateDescending(items) {
        let copy = items.slice();
        copy.sort(function (left, right) {
            let timeA = left.updatedAtMs || Date.parse(left.updatedAt || "") || 0;
            let timeB = right.updatedAtMs || Date.parse(right.updatedAt || "") || 0;
            return timeB - timeA;
        });
        return copy;
    }
    // Represent UTC calendar dates consistently across timezone and daylight-saving boundaries.
    function _utcDayNumber(value) {
        return Math.floor(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate()) / (24 * 60 * 60 * 1000));
    }
    // Persist one coherent collapsed state for all current groups.
    function collapseAllGroups() {
        let nextState = {
            [GitHubConstants.expandedStateDefaultKey]: false
        };
        expandedGroups = nextState;
        persistExpandedGroups(nextState);
    }
    // Apply the default expansion policy only where no explicit choice exists.
    function defaultExpandedGroups() {
        return expandedGroups[GitHubConstants.expandedStateDefaultKey] !== false;
    }
    // Persist one coherent expanded state for all current groups.
    function expandAllGroups() {
        let nextState = {
            [GitHubConstants.expandedStateDefaultKey]: true
        };
        expandedGroups = nextState;
        persistExpandedGroups(nextState);
    }
    // Honor an explicit group choice before falling back to the default.
    function isGroupExpanded(groupKey) {
        if (expandedGroups.hasOwnProperty(groupKey))
            return expandedGroups[groupKey] !== false;
        return defaultExpandedGroups();
    }
    // Preserve explicit collapsed groups alongside the default expansion policy.
    function normalizeExpandedState(state) {
        let next = {};
        let source = state || {};
        for (let key in source)
            next[key] = source[key];
        if (next[GitHubConstants.expandedStateDefaultKey] === undefined)
            next[GitHubConstants.expandedStateDefaultKey] = true;
        return next;
    }
    // Replace expansion state so bindings and persistence observe the user's choice.
    function toggleGroup(groupKey) {
        let nextState = normalizeExpandedState(expandedGroups);
        let defaultState = nextState[GitHubConstants.expandedStateDefaultKey] !== false;
        let nextValue = !isGroupExpanded(groupKey);

        if (nextValue === defaultState)
            delete nextState[groupKey];
        else
            nextState[groupKey] = nextValue;

        expandedGroups = nextState;
        persistExpandedGroups(normalizeExpandedState(nextState));
    }

    Component.onCompleted: {
        expandedGroups = normalizeExpandedState(expandedGroupsState);
    }
    onExpandedGroupsStateChanged: {
        expandedGroups = normalizeExpandedState(expandedGroupsState);
    }
}
