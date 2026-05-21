// DateGroupingGroup.qml - contract for one date grouping in the popout.

import QtQuick

QtObject {
    id: model

    property string key: ""
    property string label: ""
    property int unreadCount: 0
    property var items: []
    property var allItems: []

    function readFromObject(value) {
        var source = value || ({})
        key = String(source.key || "")
        label = String(source.label || "")
        unreadCount = parseInt(source.unreadCount || 0)
        if (isNaN(unreadCount))
            unreadCount = 0
        items = source.items || []
        allItems = source.allItems || items
    }

    function toObject() {
        return {
            key: key,
            label: label,
            unreadCount: unreadCount,
            items: items || [],
            allItems: allItems || []
        }
    }
}
