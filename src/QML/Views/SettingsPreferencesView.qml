// SettingsPreferencesView.qml - user-configurable inbox behavior controls.

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

Column {
    id: preferencesView

    // Ask each visible setting control to reload through the host settings contract.
    function loadValue() {
        for (let child of preferencesColumn.children)
            if (child.loadValue)
                child.loadValue();
    }

    spacing: Theme.spacingM
    width: parent.width

    Column {
        id: preferencesColumn

        spacing: Theme.spacingM
        width: parent.width

        SelectionSetting {
            defaultValue: GitHubConstants.defaultPollIntervalSetting
            description: "How often the widget checks GitHub inbox"
            label: "Refresh Interval"
            objectName: "pollIntervalSetting"
            options: [
                {
                    label: "1 minute",
                    value: "60"
                },
                {
                    label: "2 minutes",
                    value: "120"
                },
                {
                    label: "5 minutes",
                    value: "300"
                },
                {
                    label: "10 minutes",
                    value: "600"
                },
                {
                    label: "15 minutes",
                    value: "900"
                }
            ]
            settingKey: "pollInterval"
        }
        ToggleSetting {
            defaultValue: true
            description: "Load author avatars and profile names for each message"
            label: "Load Author Details"
            objectName: "loadAuthorInfoSetting"
            settingKey: "loadAuthorInfo"
        }
        StyledText {
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Bold
            text: "Note: This will considerably increase message loading time."
            width: parent.width
            wrapMode: Text.WordWrap
        }
        StyledText {
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Bold
            text: "To enable author details for private repositories, ensure that your token has full 'repo' permissions."
            width: parent.width
            wrapMode: Text.WordWrap
        }
        ToggleSetting {
            defaultValue: GitHubConstants.defaultEnableNotifications
            description: "Show a system notification when new inbox messages arrive"
            label: "Desktop Notifications"
            objectName: "enableNotificationsSetting"
            settingKey: "enableNotifications"
        }
        SliderSetting {
            defaultValue: GitHubConstants.defaultGroupItemLimit
            label: "Max Items Per Group"
            maximum: GitHubConstants.maxGroupItemLimit
            minimum: GitHubConstants.minGroupItemLimit
            objectName: "groupItemLimitSetting"
            settingKey: "groupItemLimit"
        }
        SliderSetting {
            defaultValue: GitHubConstants.defaultPopupHeightUnits
            label: "Popup Height"
            maximum: GitHubConstants.maxPopupHeightUnits
            minimum: GitHubConstants.minPopupHeightUnits
            objectName: "popupHeightSetting"
            settingKey: "popupHeight"
        }
        SelectionSetting {
            defaultValue: GitHubConstants.defaultTitleLines
            description: "How many lines each message title can use"
            label: "Max Rows for Title"
            objectName: "titleLinesSetting"
            options: [
                {
                    label: "1 line",
                    value: "1"
                },
                {
                    label: "2 lines",
                    value: "2"
                },
                {
                    label: "3 lines",
                    value: "3"
                },
                {
                    label: "4 lines",
                    value: "4"
                }
            ]
            settingKey: "titleLines"
        }
    }
}
