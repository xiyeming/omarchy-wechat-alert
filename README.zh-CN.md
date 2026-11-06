# WeChat/QQ Alert for Omarchy（微信/QQ 托盘原位闪烁提醒）

[English](README.md) | 简体中文

[Omarchy](https://omarchy.org) 顶栏插件：**收到微信 / QQ 消息时，直接在其托盘图标原位闪烁提醒**——补上 Linux 版微信、QQ 缺失的 Windows 任务栏闪烁提醒。顶栏不会多出任何图标；该应用自己的托盘图标以约 1.2 秒周期淡入淡出，右上角带红点角标，直到你打开该应用。若未来 shell 更新导致托盘组件不再可达，插件会自动降级为独立渲染提醒图标，而不是静默失效。

![闪烁亮/暗相位](docs/blink-bright.png)

## 为什么需要这个插件

Windows 上微信闪烁任务栏按钮靠的是 Win32 `FlashWindowEx` API。两个应用的 Linux 版都没有对应实现：它们从不把 StatusNotifierItem 的 `Status` 置为 `NeedsAttention`、不提供 `AttentionIcon`/`OverlayIcon`，来消息时托盘层零信号（已用 `dbus-monitor` 实测验证）。而 Omarchy 托盘只静态渲染图标——除了右上角弹出的通知 toast，屏幕上没有任何东西提醒你有新消息。

本插件补上这个缺口：监听会话总线上的通知调用，在 shell 的 QML 场景中找到该应用的托盘图标项，直接在其上叠加闪烁动画。

> **v1.3 变化：**v1.1 早已实现托盘图标原地闪烁（遍历 shell QML 场景树），某次 omarchy 更新后似乎失效（遍历结果为 0 项），v1.2 改为自行渲染独立提醒图标。经在当前 omarchy shell 上重新实测：托盘 delegate 仍全部暴露在插件可见的场景树中（遍历能找到每一个 TrayItem），因此 v1.3 恢复原地闪烁，同时保留 v1.2 的独立图标渲染作为兜底——仅当找不到托盘 delegate 时使用。

## 环境要求

- Omarchy（`omarchy-shell` 顶栏）
- 微信和/或 QQ 的 Linux 原生版
- `dbus-monitor`（dbus 自带，Omarchy 出厂即有）

## 安装

```bash
omarchy plugin add https://github.com/xiyeming/omarchy-wechat-alert.git --enable
```

手动安装：把本目录复制到 `~/.config/omarchy/plugins/xiyeming.wechat-alert/`，执行
`omarchy-shell shell rescanPlugins`，然后
`omarchy plugin enable xiyeming.wechat-alert --section right`。

主模式下插件在自己的槽位不渲染任何内容，因此在布局中的位置不影响效果。

## 行为

| 事件 | 行为 |
|---|---|
| 匹配应用收到通知 | 该应用自己的托盘图标原位闪烁（≈1.2 秒周期）+ 红点角标 |
| 该应用的窗口获得焦点 | 闪烁自动清除 |
| 点击托盘图标 | 与平时一致——激活应用；窗口聚焦后提醒清除 |
| 应用未运行 / 无托盘项 | 暂无可闪烁对象；托盘项出现后自动生效 |
| 找不到托盘 delegate（兜底模式） | 插件槽位显示该应用图标并闪烁，直到窗口聚焦 |

提醒按应用独立：QQ 来消息不会清除微信的待读提醒，反之亦然。

## 设置

在 `~/.config/omarchy/shell.json` 的布局项里覆盖匹配配置：

```json
{
  "id": "xiyeming.wechat-alert",
  "appNames": ["WeChat", "QQ"],
  "trayIds": { "QQ": "chrome_status_icon_1" }
}
```

- `appNames` — 同时匹配通知的 `app_name` 和托盘项元数据（不区分大小写）。
- `trayIds` — 可选，按应用强制指定托盘项 Id。

## 工作原理

- 一个旁听型 `dbus-monitor --session` 监视 `org.freedesktop.Notifications.Notify` 调用并匹配 `app_name` 参数。通知守护进程仍是唯一接收方——通知本身不受任何影响。
- **主模式：**插件遍历共享 QML 场景树，找到托盘的 TrayItem delegate（`modelData` 为 SystemTrayItem 的项），按 Id/Title/ToolTip 匹配目标应用，直接在该 delegate 上挂载 Windows 任务栏式透明度闪烁动画和红点角标。周期性巡检会在托盘重建或应用重启后自动重新挂载。
- **兜底模式：**若场景遍历找不到 delegate（例如未来 shell 变更隔离了插件树），插件改为从 `SystemTray.items.values` 解析该应用托盘项，在自己的槽位渲染其图标并叠加同样的闪烁与角标。
- 窗口焦点通过 foreign-toplevel 协议跟踪（与 omarchy ActiveWindow 组件同源）；聚焦该应用即清除其提醒。
- 每个顶栏实例一个监听进程；意外退出 2 秒后自动拉起。
- 注意 / 限制：
  - 勿扰（DND）模式**不会**抑制闪烁（监听的是 DND 过滤之前的原始总线调用）。
  - QQ 的托盘项是匿名 chromium 图标（`chrome_status_icon_1`，Title/ToolTip 全空，与其它 Electron 应用同模式）。对元数据匹配不到的应用，回退为"匿名 chromium 项"启发式；若在你的机器上猜错，用 `trayIds` 指定正确 Id。
  - 插件从不改动托盘结构——主模式只驱动 delegate 的 `opacity` 并临时挂载角标子节点。

## 卸载

```bash
omarchy plugin remove xiyeming.wechat-alert
```

## 许可证

[MIT](LICENSE)
