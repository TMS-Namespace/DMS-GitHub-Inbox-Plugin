// DateGroupingModel.qml - filters and groups inbox messages by date bucket.

import QtQuick
import ".."

QtObject {
    id: model

    property var messages: []
    property int groupItemLimit: 25
    property string readFilter: "both"                // yes | no | both
    property string participationFilter: "both"       // yes | no | both
    property var expandedGroupsState: ({ [GitHubConstants.expandedStateDefaultKey]: true })
    property var expandedGroups: ({})

    signal persistExpandedGroups(var state)

    Component.onCompleted: {
        expandedGroups = normalizeExpandedState(expandedGroupsState)
    }

    onExpandedGroupsStateChanged: {
        expandedGroups = normalizeExpandedState(expandedGroupsState)
    }

    readonly property var dateGroups: [
        { key: "today", label: "Today" },
        { key: "yesterday", label: "Yesterday" },
        { key: "two_days_ago", label: "Two days ago" },
        { key: "this_week", label: "This week" },
        { key: "previous_week", label: "Previous week" },
        { key: "this_month", label: "This month" },
        { key: "previous_month", label: "Previous month" },
        { key: "this_year", label: "This Year" },
        { key: "previous_year", label: "Previous Year" },
        { key: "older", label: "Older" }
    ]

    readonly property var filteredMessages: {
        var result = []
        for (var index = 0; index < messages.length; index++) {
            var item = messages[index]
            var participated = !!item.participated

            if (readFilter === "yes" && item.unread) continue
            if (readFilter === "no" && !item.unread) continue

            if (participationFilter === "yes" && !participated) continue
            if (participationFilter === "no" && participated) continue

            result.push(item)
        }
        return _sortMessagesByDateDescending(result)
    }

    readonly property var groups: {
        var result = []

        for (var groupIndex = 0; groupIndex < dateGroups.length; groupIndex++) {
            var dateGroup = dateGroups[groupIndex]
            var group = _createGroup(dateGroup.key, dateGroup.label)

            for (var messageIndex = 0; messageIndex < filteredMessages.length; messageIndex++) {
                var message = filteredMessages[messageIndex]
                if (_dateBucketValue(message) !== dateGroup.key)
                    continue
                if (group.items.length >= groupItemLimit)
                    continue

                group.items.push(message)
                if (message.unread)
                    group.unreadCount++
            }

            if (group.items.length > 0)
                result.push(group)
        }

        return result
    }

    readonly property bool hasDisplayedMessages: filteredMessages.length > 0

    function normalizeExpandedState(state) {
        var next = {}
        var source = state || {}
        for (var key in source)
            next[key] = source[key]
        if (next[GitHubConstants.expandedStateDefaultKey] === undefined)
            next[GitHubConstants.expandedStateDefaultKey] = true
        return next
    }

    function defaultExpandedGroups() {
        return expandedGroups[GitHubConstants.expandedStateDefaultKey] !== false
    }

    function isGroupExpanded(groupKey) {
        if (expandedGroups.hasOwnProperty(groupKey))
            return expandedGroups[groupKey] !== false
        return defaultExpandedGroups()
    }

    function toggleGroup(groupKey) {
        var nextState = normalizeExpandedState(expandedGroups)
        var defaultState = nextState[GitHubConstants.expandedStateDefaultKey] !== false
        var nextValue = !isGroupExpanded(groupKey)

        if (nextValue === defaultState)
            delete nextState[groupKey]
        else
            nextState[groupKey] = nextValue

        expandedGroups = nextState
        persistExpandedGroups(normalizeExpandedState(nextState))
    }

    function expandAllGroups() {
        var nextState = { [GitHubConstants.expandedStateDefaultKey]: true }
        expandedGroups = nextState
        persistExpandedGroups(nextState)
    }

    function collapseAllGroups() {
        var nextState = { [GitHubConstants.expandedStateDefaultKey]: false }
        expandedGroups = nextState
        persistExpandedGroups(nextState)
    }

    function _sortMessagesByDateDescending(items) {
        var copy = items.slice()
        copy.sort(function(a, b) {
            var timeA = Date.parse(a.updatedAt || "") || 0
            var timeB = Date.parse(b.updatedAt || "") || 0
            return timeB - timeA
        })
        return copy
    }

    function _dateBucketValue(item) {
        var timestamp = Date.parse(item.updatedAt || "")
        if (!timestamp)
            return "older"

        var updated = new Date(timestamp)
        var now = new Date()
        var dayMs = 24 * 60 * 60 * 1000

        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        var updatedDayStart = new Date(updated.getFullYear(), updated.getMonth(), updated.getDate()).getTime()

        if (updatedDayStart === todayStart)
            return "today"
        if (updatedDayStart === todayStart - dayMs)
            return "yesterday"
        if (updatedDayStart === todayStart - 2 * dayMs)
            return "two_days_ago"

        var mondayOffset = (now.getDay() + 6) % 7
        var weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - mondayOffset).getTime()
        if (timestamp >= weekStart)
            return "this_week"

        var previousWeekStart = weekStart - 7 * dayMs
        if (timestamp >= previousWeekStart)
            return "previous_week"

        var monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime()
        if (timestamp >= monthStart)
            return "this_month"

        var previousMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1).getTime()
        if (timestamp >= previousMonthStart)
            return "previous_month"

        var yearStart = new Date(now.getFullYear(), 0, 1).getTime()
        if (timestamp >= yearStart)
            return "this_year"

        var previousYearStart = new Date(now.getFullYear() - 1, 0, 1).getTime()
        if (timestamp >= previousYearStart)
            return "previous_year"

        return "older"
    }

    function _createGroup(key, label) {
        return {
            key: key,
            label: label,
            unreadCount: 0,
            items: []
        }
    }
}
