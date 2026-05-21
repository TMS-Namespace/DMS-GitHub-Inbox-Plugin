# GitHub Inbox Plugin for DMS

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) widget plugin that shows your GitHub notifications (aka inbox) in a popup and lets you mark them as read or done.

<div align="center">

| Group by repo | Group by date |
|:---:|:---:|
| <img src="Images/plugin_group_by_repo.png" width="400"/> | <img src="Images/plugin_group_by_date.png" width="400"/> |

</div>

## Features

- DankBar widget with unread count
- Popup inbox grouped by repository or date with expandable sections.
- Open thread source, repo page, or author's page directly in your browser
- Mark single thread, group of threads, or all threads, as read/done.
- Configurable refresh interval and fetch size.
- Configurable popup item limit and title line count.
- Show `DMS` notification on new incoming threads.
- Filter options:
  - Show already read/not read/all thread.
  - Show messages that you participated in/not participated/all.

<div align="center">

| Settings |
|:---:|
| <img src="Images/plugin_settings.png" width="400"/> |

</div>

## Authentication

This plugin uses a **GitHub classic personal access token**, it can be created on <https://github.com/settings/tokens>.

*Recommended token scope*:

- `notifications`
- If you need also full details for threads originated from private repositories, you need also to enable full `repo` permission for this token.

## Requirements

- `DMS` >= `1.2.0`
- `curl` in `$PATH` (usually pre-installed on most distros.)
- `secret-tool` in `$PATH` (usually pre-installed with `libsecret` on most distros)
- To present authors, `jq` command line tool is needed to parse `json`  (usually needs a manual install).
- Internet access to `api.github.com`

## Install

### Method 1

In DMS:

1. Open `Settings -> Plugins`
2. Click `Scan for Plugins`
3. Enable `GitHub Inbox`
4. Add widget to DankBar

### Method 2

Or clone repo, and run (will add `Symlink` to plugin folder):

```bash
chmod +x Support/setup-symlink.sh
Support/setup-symlink.sh
```

## Privacy & Security

- The token is securely stored via `Freedesktop Secret Service` API.
- The plugin sends web requests only to GitHub endpoints, so privacy is limited by what GitHub offers.

## Disclaimers

- The developer has no affiliation with data provider.
- This plugin was vibe-coded under my supervision as a software engineer.
