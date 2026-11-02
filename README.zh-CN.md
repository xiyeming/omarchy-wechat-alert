# WeChat/QQ Alert for Omarchy（微信/QQ 顶栏闪烁提醒）

[English](README.md) | 简体中文

[Omarchy](https://omarchy.org) 顶栏插件：**收到微信 / QQ 消息时，直接原地闪烁应用自己的托盘图标**——补上 Linux 版微信、QQ 缺失的 Windows 任务栏闪烁提醒。不会另起新图标。

![闪烁亮/暗相位](docs/blink-bright.png)

收到消息时，应用托盘图标以约 1.2 秒周期淡入淡出（右上角带红点角标），直到你打开该应用。

## 为什么需要这个插件

Windows 上微信闪烁任务栏按钮靠的是 Win32 `FlashWindowEx` API。两个应用的 Linux 版都没有对应实现：它们从不把 StatusNotifierItem 的 `Status` 置为 `NeedsAttention`、不提供 `AttentionIcon`/`OverlayIcon`，来消息时托盘层零信号（已用 `dbus-monitor` 实测验证）。而 Omarchy 托盘只静态渲染图标——除了右上角弹出的通知 toast，屏幕上没有任何东西提醒你有新消息。

本插件补上这个缺口：监听会话总线上的通知调用，然后**原地闪烁托盘里的原图标**——插件在 shell 共享的 QML 场景里找到托盘自身的图标项并直接驱动其动画，不创建任何第二个图标。

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
| 匹配应用收到通知 | 该应用的托盘图标开始闪烁（≈1.2 秒周期）+ 红点角标 |
| 该应用的窗口获得焦点 | 闪烁自动停止 |
| 点击托盘图标 | 正常打开应用；窗口聚焦后闪烁清除 |
| 应用未运行 | 无图标可闪；托盘项出现后自动开始 |

闪烁按应用独立：QQ 来消息不会清除微信的待读闪烁，反之亦然。

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
- 插件遍历 shell 的 QML 场景树，找到托盘组件中该应用的 `TrayItem` 委托，在其上运行 Windows 任务栏式透明度闪烁，并把红点角标作为其子项叠加。
- 每个显示器一个监听进程；意外退出 2 秒后自动拉起。另有 2 秒巡检，在应用重启或托盘重建后重新挂接。
- 注意 / 限制：
  - 勿扰（DND）模式**不会**抑制闪烁（监听的是 DND 过滤之前的原始总线调用）。
  - QQ 的托盘项是匿名 chromium 图标（`chrome_status_icon_1`，Title/ToolTip 全空，与其它 Electron 应用同模式）。对元数据匹配不到的应用，回退为"匿名 chromium 项"启发式；若在你的机器上猜错，用 `trayIds` 指定正确 Id。
  - 插件只动托盘图标的 `opacity`，清除时恢复为 1，不修改托盘项其它任何内容。

## 卸载

```bash
omarchy plugin remove xiyeming.wechat-alert
```

## 许可证

[MIT](LICENSE)
