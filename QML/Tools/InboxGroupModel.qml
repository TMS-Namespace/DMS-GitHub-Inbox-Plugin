// InboxGroupModel.qml - Filters and groups inbox messages by repository
//
// Owns the filtering (read / participation), grouping by repo, and
// expanded-state management that was previously mixed into PopoutPanel.
// PopoutPanel now binds to this model's outputs for a clean view/logic split.

import QtQuick
import ".."

QtObject {
    id: groupModel

    // -- Inputs ---------------------------------------------------------------
    property var messages: []
    property int groupItemLimit: 25
    property var expandedReposState: ({ [GitHubConstants.expandedStateDefaultKey]: true })

    // -- Filter state ---------------------------------------------------------
    property string readFilter: "both"                // yes | no | both
    property string participationFilter: "both"       // yes | no | both

    // -- Expanded state -------------------------------------------------------
    property var expandedRepos: ({})

    Component.onCompleted: {
        expandedRepos = normalizeExpandedState(expandedReposState)
    }

    onExpandedReposStateChanged: {
        expandedRepos = normalizeExpandedState(expandedReposState)
    }

    // -- Signals --------------------------------------------------------------
    signal persistExpandedRepos(var state)

    // =========================================================================
    //  COMPUTED OUTPUTS
    // =========================================================================

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
        return result
    }

    readonly property var groupedMessages: {
        var groupsByRepo = {}
        var repoOrder = []

        for (var index = 0; index < filteredMessages.length; index++) {
            var item = filteredMessages[index]
            var repo = item.repository || "Unknown repository"

            if (!groupsByRepo[repo]) {
                groupsByRepo[repo] = {
                    repository: repo,
                    unreadCount: 0,
                    repoOwnerLogin: "",
                    repoAvatarUrl: "",
                    items: []
                }
                repoOrder.push(repo)
            }

            if (!groupsByRepo[repo].repoAvatarUrl) {
                groupsByRepo[repo].repoOwnerLogin = item.repositoryOwnerLogin || ""
                groupsByRepo[repo].repoAvatarUrl = item.repositoryOwnerAvatarUrl || ""
            }

            if (groupsByRepo[repo].items.length >= groupItemLimit)
                continue

            groupsByRepo[repo].items.push(item)
            if (item.unread)
                groupsByRepo[repo].unreadCount++
        }

        var result = []
        for (var repoIndex = 0; repoIndex < repoOrder.length; repoIndex++)
            result.push(groupsByRepo[repoOrder[repoIndex]])
        return result
    }

    // =========================================================================
    //  EXPANDED-STATE MANAGEMENT
    // =========================================================================

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
        return expandedRepos[GitHubConstants.expandedStateDefaultKey] !== false
    }

    function isRepoExpanded(repoName) {
        if (expandedRepos.hasOwnProperty(repoName))
            return expandedRepos[repoName] !== false
        return defaultExpandedGroups()
    }

    function toggleRepo(repoName) {
        var nextState = normalizeExpandedState(expandedRepos)
        var defaultState = nextState[GitHubConstants.expandedStateDefaultKey] !== false
        var nextValue = !isRepoExpanded(repoName)

        if (nextValue === defaultState)
            delete nextState[repoName]
        else
            nextState[repoName] = nextValue

        expandedRepos = nextState
        _persistExpandedState(nextState)
    }

    function expandAllGroups() {
        var nextState = { [GitHubConstants.expandedStateDefaultKey]: true }
        expandedRepos = nextState
        _persistExpandedState(nextState)
    }

    function collapseAllGroups() {
        var nextState = { [GitHubConstants.expandedStateDefaultKey]: false }
        expandedRepos = nextState
        _persistExpandedState(nextState)
    }

    // -- Internal -------------------------------------------------------------

    function _persistExpandedState(state) {
        persistExpandedRepos(normalizeExpandedState(state))
    }
}
