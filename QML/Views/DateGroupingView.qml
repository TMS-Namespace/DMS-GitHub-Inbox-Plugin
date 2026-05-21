// DateGroupingView.qml - renders date-based inbox groups.

import QtQuick
import qs.Common
import ".."

Column {
    id: view

    property var groups: []
    property var groupingModel: null
    property var authorsByThread: ({})
    property bool showAuthorInfo: true
    property bool isBusy: false
    property int titleLines: 2

    signal markThreadRead(string threadId)
    signal markGroupRead(var items)
    signal markGroupDone(var items)
    signal markThreadUnread(string threadId)
    signal markThreadDone(string threadId)
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)
    signal closePopout()

    spacing: Theme.spacingS

    function isGroupExpanded(groupKey) {
        return groupingModel ? groupingModel.isGroupExpanded(groupKey) : true
    }

    function toggleGroup(groupKey) {
        if (groupingModel)
            groupingModel.toggleGroup(groupKey)
    }

    Repeater {
        model: view.groups

        delegate: DateGroupingGroupView {
            required property var modelData

            width: view.width
            groupData: modelData
            expanded: view.isGroupExpanded(modelData.key)
            authorsByThread: view.authorsByThread
            showAuthorInfo: view.showAuthorInfo
            isBusy: view.isBusy
            titleLines: view.titleLines
            onToggleExpanded: view.toggleGroup(modelData.key)
            onMarkGroupRead: function(items) { view.markGroupRead(items) }
            onMarkGroupDone: function(items) { view.markGroupDone(items) }
            onMarkThreadRead: function(threadId) { view.markThreadRead(threadId) }
            onMarkThreadUnread: function(threadId) { view.markThreadUnread(threadId) }
            onMarkThreadDone: function(threadId) { view.markThreadDone(threadId) }
            onRequestThreadAuthors: function(threadId, subjectApiUrl, subjectType) {
                view.requestThreadAuthors(threadId, subjectApiUrl, subjectType)
            }
            onClosePopout: view.closePopout()
        }
    }
}
