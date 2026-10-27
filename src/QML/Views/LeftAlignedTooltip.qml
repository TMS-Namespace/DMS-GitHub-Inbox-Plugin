// LeftAlignedTooltip.qml - native Dux tooltip with left-aligned content until Dux exposes alignment.

pragma ComponentBehavior: Bound

import QtQuick
import qs.DCommon.Widgets

DTooltipHost {
    id: host

    // Dux v2 hardcodes centering; retain its rendering, hover delay, positioning and lifecycle.
    function alignText() {
        let content = findTextContent(host);
        if (content)
            content.horizontalAlignment = Text.AlignLeft;
    }

    // Locate the native popup's public contentItem without depending on private IDs or child indexes.
    function findTextContent(item) {
        if (item.contentItem && item.contentItem.horizontalAlignment !== undefined)
            return item.contentItem;
        for (let child of [...(item.children || []), ...(item.resources || [])]) {
            let content = findTextContent(child);
            if (content)
                return content;
        }
        return null;
    }

    Component.onCompleted: Qt.callLater(alignText)
    onShownChanged: {
        if (shown)
            alignText();
    }
}
