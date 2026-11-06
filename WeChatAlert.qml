import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui

// Blink the ORIGINAL tray icon in place when a matched app receives a
// message — the Windows-taskbar-style cue that WeChat/QQ for Linux lack.
//
// Why: WeChat and QQ for Linux never signal tray attention. They never set
// StatusNotifierItem Status to NeedsAttention, never provide
// AttentionIcon*/OverlayIcon*, and emit no NewIcon/NewStatus when messages
// arrive (verified with dbus-monitor). On Windows the taskbar flash comes
// from the Win32 FlashWindowEx API, which the Linux ports simply do not
// implement, and the Omarchy tray widget renders icons statically.
//
// How: the omarchy tray's TrayItem delegates live in the same QML scene as
// this widget, so it walks the scene, finds the target app's TrayItem
// (delegates whose modelData is a SystemTrayItem: has activate/id/status),
// and directly:
//   1. runs a 1.0 <-> 0.15 Windows-taskbar-style blink on its opacity;
//   2. pins a red-dot badge to its top-right corner (visible between blink
//      phases).
// Clicking the tray icon opens the app as usual; when the app's window gains
// focus (tracked via the foreign-toplevel protocol, same as the omarchy
// ActiveWindow widget), the blink clears automatically.
//
// History: v1.1 introduced this scene-walk approach. v1.2 replaced it with
// a self-rendered standalone alert icon because "newer omarchy shells no
// longer expose those delegates in the same tree (scene walk finds 0 items)".
// Re-verified on the current omarchy shell: the walk finds every TrayItem
// delegate (12 items incl. wechat and chrome_status_icon_1), so v1.3
// restores in-place blinking and keeps the v1.2 self-rendered icon purely
// as a FALLBACK — used only when no TrayItem delegate is found, so a future
// shell change degrades visibly instead of silently doing nothing.
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

  // Per-app runtime state, managed imperatively:
  //   unread — message arrived, window not focused since
  //   item   — the tray's TrayItem delegate (null when scene walk found none)
  //   meta   — the SystemTrayItem (fallback icon source when item is null)
  //   anim   — blink animation attached to item
  //   badge  — red dot attached to item
  property var apps: []

  // Fallback (v1.2) mode: first unread app with no reachable TrayItem
  // delegate but a live SystemTrayItem — its icon is rendered in this
  // widget's own bar slot instead.
  property var fallbackApp: null

  // app_id of the currently focused toplevel (Wayland foreign-toplevel
  // protocol — same source the omarchy ActiveWindow widget uses)
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property string focusedClass: activeToplevel ? String(activeToplevel.appId || "") : ""

  // In primary mode the widget renders nothing (width 0). In fallback mode
  // it shows the alerting app's own tray icon, blinking, with a red dot.
  visible: fallbackApp !== null
  implicitWidth: visible ? root.barSize : 0
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
  // restart, tray rebuild, delegate recreation).
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
        meta: null,
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
  // Matching delegate selection: among ALL scene matches, prefer the LAST
  // effectively-visible one. Rationale: scene DFS order puts the drawer's
  // TrayItems before the pinned row, and clipped/invisible delegates (an
  // unpinned app's drawer slot, a closed popup's rows) must never host the
  // alert — blinking those shows nothing. The pinned row's visible icon is
  // always reached last for pinned apps.
  function findTrayItem(app) {
    var override = trayIdOverrides[app.name]
    var collected = []
    collectTrayItems(sceneRoot(root), collected)
    var anonymous = null

    for (var i = collected.length - 1; i >= 0; i--) {
      var md = collected[i].modelData
      var id = String(md.id || "").toLowerCase()
      var title = String(md.title || "").toLowerCase()
      var tt = String(md.tooltipTitle || "").toLowerCase()
      var td = String(md.tooltipDescription || "").toLowerCase()

      var isAnon = (id === "chrome_status_icon_1" && title === "" && tt === "" && td === "")
      var keyMatch = (id === app.key || title === app.key || tt === app.key
          || id.indexOf(app.key) !== -1 || title.indexOf(app.key) !== -1
          || tt.indexOf(app.key) !== -1 || td.indexOf(app.key) !== -1)
      if (!keyMatch && !isAnon) continue
      if (override !== undefined && id !== String(override).toLowerCase() && !keyMatch) continue
      if (!effectivelyVisible(collected[i])) continue
      if (isAnon && anonymous === null) anonymous = collected[i]
      else if (keyMatch) return collected[i]
    }
    return anonymous
  }

  // A delegate is no use if it or any ancestor is invisible or squeezed away
  // by a zero-size clip (closed drawer, dismissed popup).
  function effectivelyVisible(item) {
    var p = item
    while (p) {
      if (p.visible === false) return false
      if (p.clip === true && (p.width < 4 || p.height < 4)) return false
      p = p.parent
    }
    return true
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

  // ---------------------------------------------------------------
  // Fallback icon source: the SystemTray service model (no scene needed).
  // ---------------------------------------------------------------
  function findTrayMeta(app) {
    var override = trayIdOverrides[app.name]
    var items = SystemTray.items.values
    var anonymous = null

    for (var i = 0; i < items.length; i++) {
      var md = items[i]
      var id = String(md.id || "").toLowerCase()
      var title = String(md.title || "").toLowerCase()
      var tt = String(md.tooltipTitle || "").toLowerCase()
      var td = String(md.tooltipDescription || "").toLowerCase()

      if (override !== undefined && id === String(override).toLowerCase()) return md
      if (id === app.key || title === app.key || tt === app.key) return md
      if (id.indexOf(app.key) !== -1 || title.indexOf(app.key) !== -1
          || tt.indexOf(app.key) !== -1 || td.indexOf(app.key) !== -1) return md

      if (anonymous === null && id === "chrome_status_icon_1"
          && title === "" && tt === "" && td === "") anonymous = md
    }
    return anonymous
  }

  function itemValid(item) {
    try { return item !== null && item !== undefined && item.toString() !== "null" } catch (e) { return false }
  }
  function scanTrayItems() {
    var fallback = null
    for (var i = 0; i < apps.length; i++) {
      var app = apps[i]
      var stale = (app.item !== null && !itemValid(app.item))
      if (stale) detach(app)
      if (app.item === null) ensureAttached(app)
      // Keep the SystemTrayItem around: primary mode ignores it, fallback
      // mode renders its icon when no delegate is reachable.
      app.meta = findTrayMeta(app)
      if (app.unread && app.item === null && app.meta !== null && fallback === null)
        fallback = app
      applyState(app)
    }
    root.fallbackApp = fallback
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
    // Each cleanup step is exception-safe: the delegate may already be
    // destroyed (Repeater rebuilds when ANY tray item comes or goes), and
    // its children (anim, badge) die with it. An exception here must not
    // abort the state reset, or the app can never re-attach.
    try { if (app.anim) app.anim.destroy() } catch (e) {}
    try { if (app.badge) app.badge.destroy() } catch (e) {}
    try { if (app.item) app.item.opacity = 1 } catch (e) {}
    app.anim = null
    app.badge = null
    app.item = null
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

  // ---------------------------------------------------------------
  // Fallback visuals (only when the scene walk found no delegate):
  // the app's own tray icon rendered here, blinking, with a red dot.
  // ---------------------------------------------------------------
  Image {
    id: fallbackIcon
    anchors.centerIn: parent
    width: Style.space(12)
    height: Style.space(12)
    fillMode: Image.PreserveAspectFit
    // Decode at physical pixels so PNG icons stay crisp on HiDPI displays.
    sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    source: root.fallbackApp && root.fallbackApp.meta
      ? String(root.fallbackApp.meta.icon || "") : ""
  }

  SequentialAnimation {
    loops: Animation.Infinite
    alwaysRunToEnd: true
    running: root.visible
    NumberAnimation {
      target: fallbackIcon
      property: "opacity"
      to: 0.15
      duration: 420
      easing.type: Easing.InOutQuad
    }
    NumberAnimation {
      target: fallbackIcon
      property: "opacity"
      to: 1.0
      duration: 420
      easing.type: Easing.InOutQuad
    }
    PauseAnimation { duration: 300 }
  }

  Rectangle {
    anchors.horizontalCenter: fallbackIcon.right
    anchors.verticalCenter: fallbackIcon.top
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
      if (root.fallbackApp && root.fallbackApp.meta) root.fallbackApp.meta.activate()
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
