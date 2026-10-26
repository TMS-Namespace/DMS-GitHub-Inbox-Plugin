// SettingsPreferencesView.qml - grouped inbox behaviour and presentation preferences.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

Column {
    // Reload persisted controls even while their native sections are collapsed.
    function loadValue() {
        for (let container of [behaviourControls, viewControls])
            for (let child of container.children)
                if (child.loadValue)
                    child.loadValue();
    }

    spacing: Theme.spacingM
    width: parent.width

    DCollapsibleSection {
        objectName: "behaviourSettingsSection"
        title: "Behaviour"
        width: parent.width

        Column {
            id: behaviourControls

            Layout.fillWidth: true
            spacing: Theme.spacingM

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
                defaultValue: GitHubConstants.defaultEnableNotifications
                description: "Show a system notification when new inbox messages arrive"
                label: "Desktop Notifications"
                objectName: "enableNotificationsSetting"
                settingKey: "enableNotifications"
            }
        }
    }
    DCollapsibleSection {
        objectName: "viewSettingsSection"
        title: "View Settings"
        width: parent.width

        Column {
            id: viewControls

            Layout.fillWidth: true
            objectName: "viewSettingsControls"
            spacing: Theme.spacingM

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
        }
    }
}
