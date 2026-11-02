# WeChat/QQ Alert for Omarchy

English | [简体中文](README.zh-CN.md)

A bar widget for [Omarchy](https://omarchy.org)'s shell that **blinks the
app's own tray icon in place** when a WeChat or QQ notification arrives —
the Windows-taskbar-style "new message" cue that WeChat and QQ for Linux are
missing. No extra icon is added.

![blink bright vs dim](docs/blink-bright.png)

When a message arrives, the app's tray icon fades in and out (with a red-dot
badge) until you open the app.

## Why this exists

On Windows, WeChat flashes its taskbar entry via the Win32 `FlashWindowEx`
API. The Linux ports have no equivalent: they never set the StatusNotifierItem
`Status` to `NeedsAttention`, never provide `AttentionIcon`/`OverlayIcon`, and
emit no tray signals at all when a message arrives (verified with
`dbus-monitor`). The Omarchy tray renders icons statically, so nothing on
screen ever draws attention to the new message beyond the toast.

This widget closes the gap by listening for notifications on the session bus,
then blinking the **original tray icon in place** — the tray's own item is
found inside the shared QML scene and animated directly, so no second icon is
created.

## Requirements

- Omarchy with `omarchy-shell` (the Quickshell bar)
- WeChat and/or QQ for Linux
- `dbus-monitor` (ships with `dbus`, already on every Omarchy install)

## Install

```bash
omarchy plugin add https://github.com/xiyeming/omarchy-wechat-alert.git --enable
```

Manual install: copy this folder to
`~/.config/omarchy/plugins/xiyeming.wechat-alert/`, run
`omarchy-shell shell rescanPlugins`, then
`omarchy plugin enable xiyeming.wechat-alert --section right`.

## Usage

| Event | Behavior |
|---|---|
| matched notification arrives | that app's tray icon blinks (≈1.2 s cycle) with a red-dot badge |
| the app's window gains focus | its blink clears automatically |
| click on the tray icon | opens the app (normal tray behavior); focus clears the blink |
| app not running | nothing to blink yet; starts once the tray icon appears |

Blinks are per-app: a QQ message does not clear a pending WeChat blink and
vice versa.

## Settings

Override the matched apps in `~/.config/omarchy/shell.json`:

```json
{
  "id": "xiyeming.wechat-alert",
  "appNames": ["WeChat", "QQ"],
  "trayIds": { "QQ": "chrome_status_icon_1" }
}
```

- `appNames` — matched against both the notification `app_name` and tray item
  metadata (case-insensitive).
- `trayIds` — optional per-app tray item Id override.

## How it works

- A passive `dbus-monitor --session` listener watches
  `org.freedesktop.Notifications.Notify` calls and matches the `app_name`
  argument. The notification daemon remains the sole consumer — notifications
  themselves are untouched.
- The widget walks the shell's QML scene to find the tray widget's
  `TrayItem` delegate for each app, runs a Windows-taskbar-style opacity
  blink on it, and pins a red-dot badge as its child.
- One listener process per monitor; it restarts automatically after 2 s if it
  ever dies. A 2 s sweep re-attaches icons after app restarts or tray
  rebuilds.
- Notes / limitations:
  - Do Not Disturb does **not** suppress the blink (the watcher sees raw bus
    calls before DND filtering).
  - QQ's tray item is an anonymous chromium icon (`chrome_status_icon_1` with
    empty Title/ToolTip, a pattern shared by other Electron apps). The widget
    falls back to "the anonymous chromium item" for apps without metadata
    matches; if that guess is wrong on your setup, pin the right Id via
    `trayIds`.
  - Tray icons blink but tray items themselves are untouched otherwise — the
    plugin animates `opacity` and restores it on clear.

## Uninstall

```bash
omarchy plugin remove xiyeming.wechat-alert
```

## License

[MIT](LICENSE)
