// RepoGroupingModel.qml - filters and groups inbox messages by repository.

import QtQuick
import ".."

QtObject {
    id: model

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
    readonly property var groups: _groupMessagesByRepo(filteredMessages)
    readonly property bool hasDisplayedMessages: filteredMessages.length > 0
    property var messages: []
    property string participationFilter: "both"       // yes | no | both
    property string readFilter: "both"                // yes | no | both

    signal persistExpandedGroups(var state)

    // Allocate independent arrays for each group so unrelated message groups cannot share state.
    function _createGroup(repository) {
        return {
            repository: repository,
            unreadCount: 0,
            repoOwnerLogin: "",
            repoAvatarUrl: "",
            items: [],
            allItems: []
        };
    }
    // Retain complete repository membership while limiting the rendered subset.
    function _groupMessagesByRepo(items) {
        let groupsByRepo = {};
        let repoOrder = [];

        for (let index = 0; index < items.length; index++) {
            let item = items[index];
            let repo = item.repository || "Unknown repository";

            if (!groupsByRepo[repo]) {
                groupsByRepo[repo] = _createGroup(repo);
                repoOrder.push(repo);
            }

            if (!groupsByRepo[repo].repoAvatarUrl) {
                groupsByRepo[repo].repoOwnerLogin = item.repositoryOwnerLogin || "";
                groupsByRepo[repo].repoAvatarUrl = item.repositoryOwnerAvatarUrl || "";
            }

            groupsByRepo[repo].allItems.push(item);
            if (item.unread)
                groupsByRepo[repo].unreadCount++;

            if (groupsByRepo[repo].items.length >= groupItemLimit)
                continue;
            groupsByRepo[repo].items.push(item);
        }

        let result = [];
        for (let repoIndex = 0; repoIndex < repoOrder.length; repoIndex++)
            result.push(groupsByRepo[repoOrder[repoIndex]]);
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
