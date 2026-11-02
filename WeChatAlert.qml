import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui

// Blink the ORIGINAL tray icon in place when a matched app receives a
// message — the Windows-taskbar-style cue that WeChat/QQ for Linux lack.
// No extra icon is added.
//
// Why: WeChat and QQ for Linux never signal tray attention. They never set
// StatusNotifierItem Status to NeedsAttention, never provide
// AttentionIcon*/OverlayIcon*, and emit no NewIcon/NewStatus when messages
// arrive (verified with dbus-monitor). On Windows the taskbar flash comes
// from the Win32 FlashWindowEx API, which the Linux ports simply do not
// implement, and the Omarchy tray widget renders icons statically.
//
// How: the omarchy tray's TrayItem delegates live in the same QML scene
// (plugin facades do not isolate the visual tree), so this widget walks the
// scene from its own position, finds the target app's TrayItem (delegates
// whose modelData is a SystemTrayItem: has activate/id/status), and directly:
//   1. runs a 1.0 <-> 0.15 Windows-taskbar-style blink on its opacity;
//   2. pins a red-dot badge to its top-right corner (visible between blink
//      phases).
// Clicking the tray icon opens the app as usual; when the app's window gains
// focus (tracked via the foreign-toplevel protocol, same as the omarchy
// ActiveWindow widget), the blink clears automatically.
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

  // Per-app runtime state, managed imperatively.
  property var apps: []

  // app_id of the currently focused toplevel (Wayland foreign-toplevel
  // protocol — same source the omarchy ActiveWindow widget uses)
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property string focusedClass: activeToplevel ? String(activeToplevel.appId || "") : ""

  // The widget itself renders nothing — it is purely the logic host that
  // attaches blink overlays onto the tray's own icons.
  visible: false
  implicitWidth: 0
  implicitHeight: root.barSize

  Component.onCompleted: {
    rebuildApps()
    scanTrayItems()
  }

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

  // Periodic sweep: re-attach when tray items appear or get destroyed (app
  // restart, tray rebuild).
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.scanTrayItems()
  }

  // ---------------------------------------------------------------
  // State
  // ---------------------------------------------------------------
  function rebuildApps() {
    detachAll()
    var next = []
    for (var i = 0; i < appNames.length; i++) {
      next.push({
        name: String(appNames[i]),
        key: String(appNames[i]).toLowerCase(),
        unread: false,
        item: null,
        anim: null,
        badge: null
      })
    }
    apps = next
  }

  function onNotify(appName) {
    var lower = String(appName || "").toLowerCase()
    for (var i = 0; i < apps.length; i++) {
      if (apps[i].key === lower) {
        markUnread(apps[i])
        return
      }
    }
  }

  function markUnread(app) {
    if (clearIfFocused(app)) return
    app.unread = true
    applyState(app)
  }

  function clearIfFocused(app) {
    if (focusedClass.length > 0 && focusedClass.toLowerCase().indexOf(app.key) !== -1) {
      clearApp(app)
      return true
    }
    return false
  }

  function clearApp(app) {
    app.unread = false
    applyState(app)
  }

  onFocusedClassChanged: onFocusChanged()
  function onFocusChanged() {
    if (focusedClass.length === 0) return
    var lower = focusedClass.toLowerCase()
    for (var i = 0; i < apps.length; i++)
      if (apps[i].unread && lower.indexOf(apps[i].key) !== -1) clearApp(apps[i])
  }

  // ---------------------------------------------------------------
  // Tray attachment: walk the shared QML scene to find the tray's
  // TrayItem delegates (items whose modelData is a SystemTrayItem).
  // ---------------------------------------------------------------
  function findTrayItem(app) {
    var override = trayIdOverrides[app.name]
    var collected = []
    collectTrayItems(sceneRoot(root), collected)
    var anonymous = null

    for (var i = 0; i < collected.length; i++) {
      var md = collected[i].modelData
      var id = String(md.id || "").toLowerCase()
      var title = String(md.title || "").toLowerCase()
      var tt = String(md.tooltipTitle || "").toLowerCase()
      var td = String(md.tooltipDescription || "").toLowerCase()

      if (override !== undefined && id === String(override).toLowerCase()) return collected[i]
      if (id === app.key || title === app.key || tt === app.key) return collected[i]
      if (id.indexOf(app.key) !== -1 || title.indexOf(app.key) !== -1
          || tt.indexOf(app.key) !== -1 || td.indexOf(app.key) !== -1) return collected[i]

      // Anonymous chromium icon heuristic: Id=chrome_status_icon_1 with all
      // metadata empty (QQ NT matches; chromium items carrying a tooltip are
      // excluded).
      if (anonymous === null && id === "chrome_status_icon_1"
          && title === "" && tt === "" && td === "") anonymous = collected[i]
    }
    return anonymous
  }

  function sceneRoot(item) {
    var p = item
    while (p && p.parent) p = p.parent
    return p
  }

  function collectTrayItems(node, out) {
    if (node === null || node === undefined) return
    var md = node.modelData
    if (md !== undefined && md !== null && typeof md === "object"
        && md.id !== undefined && md.status !== undefined && md.activate !== undefined)
      out.push(node)
    var kids = node.children
    for (var i = 0; i < kids.length; i++) collectTrayItems(kids[i], out)
  }

  function itemValid(item) {
    try { void item.parent; return true } catch (e) { return false }
  }

  function scanTrayItems() {
    for (var i = 0; i < apps.length; i++) {
      var app = apps[i]
      var stale = (app.item !== null && !itemValid(app.item))
      if (stale) detach(app)
      if (app.item === null) ensureAttached(app)
      applyState(app)
    }
  }

  function ensureAttached(app) {
    var item = findTrayItem(app)
    if (item === null) return
    app.item = item
    app.badge = badgeComp.createObject(item)
    app.anim = blinkComp.createObject(item)
    app.anim.targetItem = item
  }

  function detach(app) {
    if (app.anim) { app.anim.destroy(); app.anim = null }
    if (app.badge) { app.badge.destroy(); app.badge = null }
    if (app.item) {
      try { app.item.opacity = 1 } catch (e) {}
      app.item = null
    }
  }

  function detachAll() {
    for (var i = 0; i < apps.length; i++) detach(apps[i])
  }

  function applyState(app) {
    if (app.anim && itemValid(app.anim)) app.anim.running = app.unread
    if (app.badge && itemValid(app.badge)) app.badge.visible = app.unread
    if (app.item && itemValid(app.item) && !app.unread) {
      try { app.item.opacity = 1 } catch (e) {}
    }
  }

  // Windows-taskbar-style blink, applied to the tray's own TrayItem.
  Component {
    id: blinkComp
    SequentialAnimation {
      id: seq
      property Item targetItem: null
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation {
        target: seq.targetItem
        property: "opacity"
        to: 0.15
        duration: 420
        easing.type: Easing.InOutQuad
      }
      NumberAnimation {
        target: seq.targetItem
        property: "opacity"
        to: 1.0
        duration: 420
        easing.type: Easing.InOutQuad
      }
      PauseAnimation { duration: 300 }
    }
  }

  // Red-dot badge pinned to the tray icon's top-right corner, visible even
  // between blink phases.
  Component {
    id: badgeComp
    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(1)
      anchors.topMargin: Style.space(1)
      width: Style.space(7)
      height: Style.space(7)
      radius: width / 2
      color: "#e5484d"
      border.width: 1
      border.color: "#ffffff"
      z: 99
      visible: false
    }
  }
}
