# GitHub Inbox Plugin for DMS

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) widget plugin that shows your GitHub notifications in a popup and lets you mark them as read.

## Features

- DankBar widget with unread count
- Popup inbox grouped by repository with expandable sections
- Notification type icons (PR, issue, release, discussion, etc.)
- Open notifications directly in your browser
- Mark single thread as read
- Mark all notifications as read
- Configurable refresh interval and fetch size
- Configurable popup item limit and title line count (height auto-adjusted)
- Filter options:
  - include read notifications
  - participating threads only

## Authentication

This plugin uses a **GitHub classic personal access token** from plugin settings.

Recommended token scope:

- `notifications`

Create token: <https://github.com/settings/tokens>

## Requirements

- `DMS` >= `1.2.0`
- `curl` in `$PATH`
- Internet access to `api.github.com`

## Install (Symlink)

```bash
chmod +x Support/setup-symlink.sh
Support/setup-symlink.sh
```

Then in DMS:

1. Open `Settings -> Plugins`
2. Click `Scan for Plugins`
3. Enable `GitHub Inbox`
4. Add widget to DankBar
5. Restart or reload plugins

## Notes

- Token is stored in DMS plugin settings.
- The plugin requests only GitHub notification endpoints.
