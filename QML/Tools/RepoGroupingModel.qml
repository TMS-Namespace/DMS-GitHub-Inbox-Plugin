// RepoGroupingModel.qml - filters and groups inbox messages by repository.

import QtQuick
import ".."

QtObject {
    id: model

    property var messages: []
    property int groupItemLimit: 25
    property var expandedGroupsState: ({ [GitHubConstants.expandedStateDefaultKey]: true })
    property string readFilter: "both"                // yes | no | both
    property string participationFilter: "both"       // yes | no | both
    property var expandedGroups: ({})

    signal persistExpandedGroups(var state)

    Component.onCompleted: {
        expandedGroups = normalizeExpandedState(expandedGroupsState)
    }

    onExpandedGroupsStateChanged: {
        expandedGroups = normalizeExpandedState(expandedGroupsState)
    }

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

    readonly property var groups: _groupMessagesByRepo(filteredMessages)
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

    function _groupMessagesByRepo(items) {
        var groupsByRepo = {}
        var repoOrder = []

        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            var repo = item.repository || "Unknown repository"

            if (!groupsByRepo[repo]) {
                groupsByRepo[repo] = _createGroup(repo)
                repoOrder.push(repo)
            }

            if (groupsByRepo[repo].items.length >= groupItemLimit)
                continue

            if (!groupsByRepo[repo].repoAvatarUrl) {
                groupsByRepo[repo].repoOwnerLogin = item.repositoryOwnerLogin || ""
                groupsByRepo[repo].repoAvatarUrl = item.repositoryOwnerAvatarUrl || ""
            }

            groupsByRepo[repo].items.push(item)
            if (item.unread)
                groupsByRepo[repo].unreadCount++
        }

        var result = []
        for (var repoIndex = 0; repoIndex < repoOrder.length; repoIndex++)
            result.push(groupsByRepo[repoOrder[repoIndex]])
        return result
    }

    function _createGroup(repository) {
        return {
            repository: repository,
            unreadCount: 0,
            repoOwnerLogin: "",
            repoAvatarUrl: "",
            items: []
        }
    }
}
