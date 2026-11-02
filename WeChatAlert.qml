import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui

// Blinking bar alert for incoming WeChat messages.
//
// Why: WeChat for Linux never flashes anything. It never sets
// StatusNotifierItem Status to NeedsAttention, never provides
// AttentionIcon*/OverlayIcon*, and emits no NewIcon/NewStatus when a message
// arrives (verified with dbus-monitor). On Windows the taskbar flash comes
// from the Win32 FlashWindowEx API, which the Linux port simply does not
// have an equivalent for, and the Omarchy tray widget renders icons
// statically. So this widget listens on the session bus for
// org.freedesktop.Notifications Notify calls instead, matches the app_name
// sent by WeChat ("WeChat"), and blinks a WeChat icon in the bar.
//
// Behavior:
//   - WeChat notification arrives -> unread = true, icon blinks (~1.2s cycle)
//     with a red dot badge
//   - Left click -> calls Activate on WeChat's tray item (same as clicking
//     the tray icon) and stops the blink
//   - WeChat main window gains focus -> blink clears automatically
//   - WeChat not running (no tray item) -> nerd-font glyph fallback; click
//     launches WeChat
BarWidget {
  id: root
  moduleName: "xiyeming.wechat-alert"

  // Notification app_name to match; override via the widget's shell.json
  // layout entry if your WeChat build sends something else.
  readonly property string matchApp: root.setting("appName", "WeChat")
  readonly property string matchAppLower: matchApp.toLowerCase()

  property bool unread: false

  // WeChat's tray item (quickshell resolves its pixmap-only icon into an
  // image:// URL, same icon the tray shows)
  readonly property var trayItem: {
    var values = SystemTray.items.values
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].id || "").toLowerCase() === "wechat") return values[i]
    }
    return null
  }

  // Class of the currently focused window: a focused WeChat window counts as
  // "seen", clearing the blink.
  readonly property string focusedClass: {
    var t = Hyprland.activeToplevel
    if (!t) return ""
    var o = t.lastIpcObject || {}
    return String(o.class || o.initialClass || "")
  }

  onFocusedClassChanged: clearIfWechatFocused()
  Component.onCompleted: clearIfWechatFocused()

  function clearIfWechatFocused() {
    if (focusedClass.toLowerCase() === "wechat") root.unread = false
  }

  visible: unread
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  // Passive listener for Notify calls on the session bus. The notification
  // daemon is still the sole consumer; dbus-monitor only eavesdrops and the
  // notifications themselves are unaffected.
  Process {
    id: notifyWatcher
    command: [
      "dbus-monitor", "--session",
      "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"
    ]
    running: true
    property bool expectingAppName: false
    stdout: SplitParser {
      // Notify(app_name, replaces_id, app_icon, summary, body, actions,
      //        hints, expire_timeout) — the first string argument is app_name.
      onRead: function(line) {
        var s = String(line || "")
        if (s.indexOf("member=Notify") !== -1) {
          notifyWatcher.expectingAppName = true
          return
        }
        if (!notifyWatcher.expectingAppName) return
        var m = s.match(/^\s*string\s+"((?:[^"\\]|\\.)*)"\s*$/)
        if (m === null) return
        notifyWatcher.expectingAppName = false
        if (m[1].toLowerCase() === root.matchAppLower) root.markUnread()
      }
    }
    onExited: restartTimer.restart()
  }

  // If dbus-monitor dies unexpectedly, bring it back after 2s (no tight loop).
  Timer {
    id: restartTimer
    interval: 2000
    onTriggered: notifyWatcher.running = true
  }

  function markUnread() {
    if (focusedClass.toLowerCase() === "wechat") return
    root.unread = true
  }

  BarIconButton {
    id: button
    anchors.centerIn: parent
    bar: root.bar
    tooltipText: "WeChat: new message — click to open"

    iconComponent: Component {
      Item {
        id: content
        anchors.fill: parent

        // Main icon: reuse WeChat's tray icon when it is running.
        Image {
          id: wechatIcon
          anchors.centerIn: parent
          width: Style.space(15)
          height: Style.space(15)
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          visible: root.trayItem !== null && String(root.trayItem.icon || "") !== ""
          source: root.trayItem ? root.trayItem.icon : ""
        }

        // Glyph fallback while WeChat is not running (fa-weixin).
        OpticalGlyph {
          anchors.fill: parent
          visible: !wechatIcon.visible
          text: "\uf1d7"
          fontSize: Style.bar.iconFont
          color: root.bar ? root.bar.foreground : Commons.Color.foreground
        }

        // Red dot badge, visible even between blink phases.
        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: Style.space(2)
          anchors.topMargin: Style.space(2)
          width: Style.space(6)
          height: Style.space(6)
          radius: width / 2
          color: root.bar ? root.bar.urgent : "#e5484d"
          border.width: 1
          border.color: root.bar ? root.bar.background : "transparent"
        }

        // Windows-taskbar-style blink.
        SequentialAnimation {
          running: root.unread
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation {
            target: content
            property: "opacity"
            to: 0.15
            duration: 420
            easing.type: Easing.InOutQuad
          }
          NumberAnimation {
            target: content
            property: "opacity"
            to: 1.0
            duration: 420
            easing.type: Easing.InOutQuad
          }
          PauseAnimation { duration: 300 }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton !== Qt.LeftButton) return
      root.unread = false
      if (root.trayItem) {
        root.trayItem.activate()
      } else if (root.bar) {
        root.bar.run("wechat")
      }
    }
  }
}
