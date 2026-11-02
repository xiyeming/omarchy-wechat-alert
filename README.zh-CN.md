# WeChat/QQ Alert for Omarchy（微信/QQ 顶栏闪烁提醒）

[English](README.md) | 简体中文

[Omarchy](https://omarchy.org) 顶栏插件：**收到微信 / QQ 消息时，在顶栏弹出该应用自己的托盘图标并闪烁提醒**——补上 Linux 版微信、QQ 缺失的 Windows 任务栏闪烁提醒。提醒图标取自系统托盘服务，消息处理完后自动消失。

![闪烁亮/暗相位](docs/blink-bright.png)

收到消息时，插件在顶栏自己的槽位显示该应用的托盘图标，以约 1.2 秒周期淡入淡出（右上角带红点角标），直到你打开该应用。

## 为什么需要这个插件

Windows 上微信闪烁任务栏按钮靠的是 Win32 `FlashWindowEx` API。两个应用的 Linux 版都没有对应实现：它们从不把 StatusNotifierItem 的 `Status` 置为 `NeedsAttention`、不提供 `AttentionIcon`/`OverlayIcon`，来消息时托盘层零信号（已用 `dbus-monitor` 实测验证）。而 Omarchy 托盘只静态渲染图标——除了右上角弹出的通知 toast，屏幕上没有任何东西提醒你有新消息。

本插件补上这个缺口：监听会话总线上的通知调用，然后在插件自己的顶栏槽位（紧挨托盘）显示该应用的托盘图标并叠加 Windows 任务栏式闪烁动画。

> **v1.2 变化：**早期版本通过遍历 shell 的 QML 场景树，直接原地闪烁托盘里已有的图标。新版 omarchy shell 不再把托盘图标项暴露在插件可见的场景树中（实测遍历结果为 0 项），所以 v1.2 改为自行渲染图标。提醒期间托盘旁边多出来的那个图标就是本插件在工作，属正常行为。

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

## 行为

| 事件 | 行为 |
|---|---|
| 匹配应用收到通知 | 插件槽位显示该应用的托盘图标，开始闪烁（≈1.2 秒周期）+ 红点角标 |
| 该应用的窗口获得焦点 | 提醒自动消失，槽位收起 |
| 点击提醒图标 | 激活该应用（等同点击其托盘图标）；窗口聚焦后提醒清除 |
| 应用未运行 / 无托盘项 | 暂无可显示内容；托盘项出现后自动生效 |

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
- 插件从 `SystemTray.items.values`（StatusNotifierItem 注册表）解析出该应用的托盘项，在其自有顶栏槽位渲染其 `icon`（已是现成的 `image://` URL），叠加透明度闪烁动画和红点角标。由于绑定了托盘模型，应用重启或托盘重建后图标会自动恢复。
- 每个顶栏实例一个监听进程；意外退出 2 秒后自动拉起。
- 注意 / 限制：
  - 勿扰（DND）模式**不会**抑制闪烁（监听的是 DND 过滤之前的原始总线调用）。
  - QQ 的托盘项是匿名 chromium 图标（`chrome_status_icon_1`，Title/ToolTip 全空，与其它 Electron 应用同模式）。对元数据匹配不到的应用，回退为"匿名 chromium 项"启发式；若在你的机器上猜错，用 `trayIds` 指定正确 Id。
  - 插件从不修改托盘本身——提醒只是独立渲染应用图标的顶栏组件。

## 卸载

```bash
omarchy plugin remove xiyeming.wechat-alert
```

## 许可证

[MIT](LICENSE)
