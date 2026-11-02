# WeChat/QQ Alert for Omarchy

English | [简体中文](README.zh-CN.md)

A bar widget for [Omarchy](https://omarchy.org)'s shell that **blinks an
alert icon** when a WeChat or QQ notification arrives — the
Windows-taskbar-style "new message" cue that WeChat and QQ for Linux are
missing. The alert shows the app's **own tray icon**, fetched from the
system tray service, and disappears once the message is seen.

![blink bright vs dim](docs/blink-bright.png)

When a message arrives, the widget's bar slot shows that app's tray icon
fading in and out (with a red-dot badge) until you open the app.

## Why this exists

On Windows, WeChat flashes its taskbar entry via the Win32 `FlashWindowEx`
API. The Linux ports have no equivalent: they never set the StatusNotifierItem
`Status` to `NeedsAttention`, never provide `AttentionIcon`/`OverlayIcon`, and
emit no tray signals at all when a message arrives (verified with
`dbus-monitor`). The Omarchy tray renders icons statically, so nothing on
screen ever draws attention to the new message beyond the toast.

This widget closes the gap by listening for notifications on the session bus,
then showing the app's own tray icon (resolved from the tray service) in
the widget's bar slot, next to the tray, with a Windows-taskbar-style
blink on top.

> **v1.2 change:** earlier versions blinked the tray widget's existing icon
> in place by walking the shell's QML scene. Newer omarchy shells no longer
> expose those tray delegates in the plugin's scene tree, so v1.2 renders
> its own icon instead. While alerting, the widget visibly occupies its bar
> slot — that extra icon next to the tray is this widget working as designed.

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
| matched notification arrives | the widget's bar slot shows that app's tray icon, blinking (≈1.2 s cycle) with a red-dot badge |
| the app's window gains focus | the alert clears automatically and the slot collapses |
| click on the alert icon | activates the app (same as clicking its tray icon); focus clears the alert |
| app not running / no tray item | nothing to show yet; the alert appears once the tray item exists |

Alerts are per-app: a QQ message does not clear a pending WeChat alert and
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
- The widget resolves the app's tray item from
  `SystemTray.items.values` (the StatusNotifierItem registry) and renders its
  `icon` (already an `image://` URL) in its own bar slot, with an opacity
  blink and a red-dot badge on top. Because it binds the tray model, the
  alert picks the icon up automatically after app restarts or tray rebuilds.
- One listener process per bar instance; it restarts automatically after 2 s
  if it ever dies.
- Notes / limitations:
  - Do Not Disturb does **not** suppress the blink (the watcher sees raw bus
    calls before DND filtering).
  - QQ's tray item is an anonymous chromium icon (`chrome_status_icon_1` with
    empty Title/ToolTip, a pattern shared by other Electron apps). The widget
    falls back to "the anonymous chromium item" for apps without metadata
    matches; if that guess is wrong on your setup, pin the right Id via
    `trayIds`.
  - The tray itself is never modified — the alert is a separate bar widget
    that only mirrors the app's icon.

## Uninstall

```bash
omarchy plugin remove xiyeming.wechat-alert
```

## License

[MIT](LICENSE)
