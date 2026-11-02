import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui

// Blink an alert icon in the bar when a matched app receives a message —
// the Windows-taskbar-style cue that WeChat/QQ for Linux lack.
//
// Why: WeChat and QQ for Linux never signal tray attention. They never set
// StatusNotifierItem Status to NeedsAttention, never provide
// AttentionIcon*/OverlayIcon*, and emit no NewIcon/NewStatus when messages
// arrive (verified with dbus-monitor). On Windows the taskbar flash comes
// from the Win32 FlashWindowEx API, which the Linux ports simply do not
// implement.
//
// How: a passive dbus-monitor eavesdrops on Notify calls on the session bus
// (the notification daemon is still the sole consumer; notifications
// themselves are unaffected). When a Notify arrives from a matched app, the
// widget renders that app's OWN tray icon (from SystemTray.items) in its
// bar slot, runs a 1.0 <-> 0.15 Windows-taskbar-style blink on it, and pins
// a red-dot badge to its top-right corner. Clicking the icon activates the
// app; when the app's window gains focus (tracked via the foreign-toplevel
// protocol, same as the omarchy ActiveWindow widget), the alert clears.
//
// The earlier version (v1.1.0) blinked the tray widget's existing icon by
// walking the shared QML scene; newer omarchy shells no longer expose those
// delegates in the same tree (scene walk finds 0 items), so v1.2 renders
// its own icon instead — self-contained, no scene coupling.
//
// App matching (override via the widget's shell.json layout entry):
//   appNames: ["WeChat", "QQ"]  — matches both the notification app_name and
//                                 the tray item metadata (case-insensitive)
//   trayIds:  { "QQ": "..." }   — optional, force a tray item Id per app
// QQ's tray item is an anonymous chromium icon (Id=chrome_status_icon_1 with
// empty Title/ToolTip, colliding with other chromium apps). When no metadata
// match is found, the widget falls back to the "anonymous chromium icon"
// heuristic: the chrome_status_icon_1 item whose metadata is entirely empty.
BarWidget {
  id: root
  moduleName: "xiyeming.wechat-alert"

  readonly property var appNames: {
    var v = root.setting("appNames", ["WeChat", "QQ"])
    return (v instanceof Array && v.length > 0) ? v : ["WeChat", "QQ"]
  }
  readonly property var trayIdOverrides: {
    var v = root.setting("trayIds", {})
    return (v !== null && typeof v === "object" && !(v instanceof Array)) ? v : {}
  }

  // Per-app unread state, managed imperatively. Object field mutations do
  // not notify QML bindings, so bump stateVersion to re-evaluate them.
  property var unread: ({})
  property int stateVersion: 0

  // app_id of the currently focused toplevel (Wayland foreign-toplevel
  // protocol — same source the omarchy ActiveWindow widget uses)
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property string focusedClass: activeToplevel ? String(activeToplevel.appId || "") : ""

  // The first app that is unread and has a live tray item — the alerting app.
  // Reads SystemTray.items (notifying) and stateVersion, so this re-evaluates
  // when items come and go or unread state changes.
  readonly property var alertApp: {
    void root.stateVersion
    void SystemTray.items
    for (var i = 0; i < appNames.length; i++) {
      var key = String(appNames[i]).toLowerCase()
      if (root.unread[key]) {
        var item = findTrayItem(key, String(appNames[i]))
        if (item !== null) return { name: String(appNames[i]), key: key, item: item }
      }
    }
    return null
  }

  visible: alertApp !== null
  implicitWidth: visible ? root.barSize : 0
  implicitHeight: root.barSize

  Component.onCompleted: stateVersion++

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
        root.onNotify(m[1])
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

  onFocusedClassChanged: onFocusChanged()
  function onFocusChanged() {
    if (focusedClass.length === 0) return
    var lower = focusedClass.toLowerCase()
    var changed = false
    for (var i = 0; i < appNames.length; i++) {
      var key = String(appNames[i]).toLowerCase()
      if (root.unread[key] && lower.indexOf(key) !== -1) {
        root.unread[key] = false
        changed = true
      }
    }
    if (changed) stateVersion++
  }

  function onNotify(appName) {
    var lower = String(appName || "").toLowerCase()
    for (var i = 0; i < appNames.length; i++) {
      var key = String(appNames[i]).toLowerCase()
      if (key === lower) {
        // If the app's window already has focus, treat as read immediately.
        if (focusedClass.length > 0 && focusedClass.toLowerCase().indexOf(key) !== -1) return
        root.unread[key] = true
        stateVersion++
        return
      }
    }
  }

  // ---------------------------------------------------------------
  // Tray item lookup against the SystemTray service (not the scene).
  // ---------------------------------------------------------------
  function findTrayItem(key, name) {
    var override = trayIdOverrides[name]
    var items = SystemTray.items.values
    var anonymous = null

    for (var i = 0; i < items.length; i++) {
      var md = items[i]
      var id = String(md.id || "").toLowerCase()
      var title = String(md.title || "").toLowerCase()
      var tt = String(md.tooltipTitle || "").toLowerCase()
      var td = String(md.tooltipDescription || "").toLowerCase()

      if (override !== undefined && id === String(override).toLowerCase()) return md
      if (id === key || title === key || tt === key) return md
      if (id.indexOf(key) !== -1 || title.indexOf(key) !== -1
          || tt.indexOf(key) !== -1 || td.indexOf(key) !== -1) return md

      // Anonymous chromium icon heuristic: Id=chrome_status_icon_1 with all
      // metadata empty (QQ NT matches; chromium items carrying a tooltip are
      // excluded).
      if (anonymous === null && id === "chrome_status_icon_1"
          && title === "" && tt === "" && td === "") anonymous = md
    }
    return anonymous
  }

  // ---------------------------------------------------------------
  // Visuals: the app's own tray icon, blinking, with a red-dot badge.
  // ---------------------------------------------------------------
  Image {
    id: iconImage
    anchors.centerIn: parent
    width: Style.space(12)
    height: Style.space(12)
    fillMode: Image.PreserveAspectFit
    // Decode at physical pixels so PNG icons stay crisp on HiDPI displays.
    sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    source: root.alertApp ? String(root.alertApp.item.icon || "") : ""
  }

  // Windows-taskbar-style blink while alerting.
  SequentialAnimation {
    loops: Animation.Infinite
    alwaysRunToEnd: true
    running: root.visible
    NumberAnimation {
      target: iconImage
      property: "opacity"
      to: 0.15
      duration: 420
      easing.type: Easing.InOutQuad
    }
    NumberAnimation {
      target: iconImage
      property: "opacity"
      to: 1.0
      duration: 420
      easing.type: Easing.InOutQuad
    }
    PauseAnimation { duration: 300 }
  }

  // Red-dot badge pinned to the icon's top-right corner, visible even
  // between blink phases.
  Rectangle {
    anchors.horizontalCenter: iconImage.right
    anchors.verticalCenter: iconImage.top
    width: Style.space(7)
    height: Style.space(7)
    radius: width / 2
    color: "#e5484d"
    border.width: 1
    border.color: "#ffffff"
    visible: root.visible
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.alertApp) root.alertApp.item.activate()
    }
  }
}
