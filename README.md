# WeChat Alert for Omarchy

A bar widget for [Omarchy](https://omarchy.org)'s shell that **blinks when a
WeChat notification arrives** — the Windows-style "new message" cue that
WeChat for Linux is missing.

![blink bright vs dim](docs/blink-bright.png)

When a message arrives, a WeChat icon (with a red dot badge) fades in and out
next to your tray until you open WeChat.

## Why this exists

On Windows, WeChat flashes its taskbar entry via the Win32 `FlashWindowEx`
API. The Linux port has no equivalent: it never sets the StatusNotifierItem
`Status` to `NeedsAttention`, never provides `AttentionIcon`/`OverlayIcon`,
and emits no tray signals at all when a message arrives (verified with
`dbus-monitor`). The Omarchy tray renders icons statically, so nothing on
screen ever draws attention to the new message beyond the toast.

This widget closes the gap by listening for WeChat's notifications on the
session bus instead, and blinking in the bar.

## Requirements

- Omarchy with `omarchy-shell` (the Quickshell bar)
- WeChat for Linux (`/opt/wechat`) — the native client
- `dbus-monitor` (ships with `dbus`, already on every Omarchy install)

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-wechat-alert.git --enable
```

The widget lands in the right bar section (next to the tray) and appears
whenever a WeChat notification is pending.

Manual install: copy this folder to
`~/.config/omarchy/plugins/xiyeming.wechat-alert/`, run
`omarchy-shell shell rescanPlugins`, then
`omarchy plugin enable xiyeming.wechat-alert --section right`.

## Usage

| Event | Behavior |
|---|---|
| WeChat notification arrives | icon starts blinking (≈1.2 s cycle) with a red dot badge |
| Left click on the icon | opens WeChat (tray `Activate`), blink stops |
| WeChat main window gains focus | blink clears automatically |
| WeChat not running | nerd-font WeChat glyph is shown instead; click launches WeChat |

The icon reuses WeChat's actual tray icon, so it matches the real app.

## Settings

Override the matched notification `app_name` in `~/.config/omarchy/shell.json`
(useful if a WeChat build changes its sender name, or to match another app):

```json
{
  "id": "xiyeming.wechat-alert",
  "appName": "WeChat"
}
```

## How it works

- A passive `dbus-monitor --session` listener watches
  `org.freedesktop.Notifications.Notify` calls and matches the `app_name`
  argument. The notification daemon remains the sole consumer — notifications
  themselves are untouched.
- One listener process per monitor; it restarts automatically after 2 s if it
  ever dies.
- Notes / limitations:
  - Do Not Disturb does **not** suppress the blink (the watcher sees raw bus
    calls before DND filtering).
  - The tray-icon path depends on WeChat running (for the icon); the glyph
    fallback covers the rest.

## Uninstall

```bash
omarchy plugin remove xiyeming.wechat-alert
```

## License

[MIT](LICENSE)
