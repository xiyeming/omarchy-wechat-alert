# WeChat/QQ Alert for Omarchy

English | [简体中文](README.zh-CN.md)

A bar widget for [Omarchy](https://omarchy.org)'s shell that **blinks the
original WeChat/QQ tray icon in place** when a notification arrives — the
Windows-taskbar-style "new message" cue that WeChat and QQ for Linux are
missing. No extra icon is added to the bar; the app's own tray icon fades
in and out with a red-dot badge until the message is seen. If the tray
delegates ever become unreachable (a future shell change), the widget
degrades to showing a standalone alert icon instead of silently doing
nothing.

![blink bright vs dim](docs/blink-bright.png)

## Why this exists

On Windows, WeChat flashes its taskbar entry via the Win32 `FlashWindowEx`
API. The Linux ports have no equivalent: they never set the StatusNotifierItem
`Status` to `NeedsAttention`, never provide `AttentionIcon`/`OverlayIcon`, and
emit no tray signals at all when a message arrives (verified with
`dbus-monitor`). The Omarchy tray renders icons statically, so nothing on
screen ever draws attention to the new message beyond the toast.

This widget closes the gap by listening for notifications on the session bus,
finding the app's TrayItem delegate in the shell's QML scene, and running the
blink directly on it.

> **v1.3 change:** v1.1 already blinked the tray icon in place by walking
> the shell's QML scene. After an omarchy update appeared to break that
> (scene walk found 0 items), v1.2 replaced it with a self-rendered
> standalone alert icon. Re-verified on the current omarchy shell: the tray
> delegates are back in the plugin's scene tree (walk finds every TrayItem),
> so v1.3 restores in-place blinking and keeps the v1.2 self-rendered icon
> purely as a fallback when no delegate is found.

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

The widget renders nothing in its own slot in primary mode, so its position
in the layout does not matter.

## Usage

| Event | Behavior |
|---|---|
| matched notification arrives | the app's own tray icon blinks in place (≈1.2 s cycle) with a red-dot badge |
| the app's window gains focus | the blink clears automatically |
| click on the tray icon | as usual — activates the app; focus clears the alert |
| app not running / no tray item | nothing to blink yet; alerting starts once the tray item exists |
| no tray delegate reachable (fallback) | the widget's own slot shows the app's icon, blinking, until focused |

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
- **Primary mode:** the widget walks the shared QML scene, finds the tray's
  TrayItem delegates (items whose `modelData` is a SystemTrayItem), matches
  the target app by Id/Title/ToolTip, and attaches a Windows-taskbar-style
  opacity blink plus a red-dot badge directly to that delegate. A periodic
  sweep re-attaches after tray rebuilds or app restarts.
- **Fallback mode:** if the scene walk finds no delegate (e.g. a future
  shell change isolates the plugin tree), the widget renders the app's own
  tray icon (resolved from `SystemTray.items.values`) in its bar slot with
  the same blink and badge.
- Window focus is tracked via the foreign-toplevel protocol (the same source
  the omarchy ActiveWindow widget uses); focusing the app clears its alert.
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
  - The tray itself is never modified structurally — primary mode only
    drives the delegate's `opacity` and pins a temporary badge child.

## Uninstall

```bash
omarchy plugin remove xiyeming.wechat-alert
```

## License

[MIT](LICENSE)
