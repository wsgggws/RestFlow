# RestFlow

一款轻量的 macOS 菜单栏休息工具。免费，无账户、广告和追踪。

| 设置 | 休息界面 |
| --- | --- |
| ![RestFlow 设置](docs/images/settings.png) | ![RestFlow 全屏休息提示](docs/images/break.png) |

## 特色

- **专注与休息循环**：默认专注 25 分钟、短休息 30 秒，每 2 段专注后长休息 5 分钟；支持暂停、重新开始和现在休息。
- **多屏同步**：全屏休息、柔和配色、背景与动画透明度可调，按 Esc 或点击 Esc 提前结束。
- **自由选择内容**：12 条文案、12 款矢量场景与动画，支持随机、添加文案及导入图片／GIF／Lottie；重复文案自动识别。
- **按自己的习惯使用**：文案、动画和声音均可选“无”；可调音量、中英文切换、自定义快捷键、开机启动及版本检查。

## 安装

需要 **Apple Silicon、macOS 13+**。[下载最新版本](https://github.com/wsgggws/RestFlow/releases/latest)，或使用 Homebrew：

```sh
brew tap wsgggws/restflow https://github.com/wsgggws/RestFlow.git
brew install --cask restflow
```

若提示 `untrusted tap`，执行 `brew trust --cask wsgggws/restflow/restflow` 后重试。

更新：`brew update && brew upgrade --cask wsgggws/restflow/restflow`。

当前版本使用临时签名，**尚未 Apple 公证**。首次打开若被拦截，请确认来自本仓库，再按“系统设置 → 隐私与安全性”中的提示允许打开。

## 使用

点击菜单栏叶子图标查看当前阶段与剩余时间，暂停、重新开始、现在休息或打开设置。菜单栏时间可以隐藏；休息时显示 ☕︎，暂停时显示 ⏸。

在设置中调整计划和休息内容；“预览休息界面”会立即开始短休息倒计时，按 Esc 或点击 Esc 返回专注。计划修改从下一阶段生效，重新开始可立即应用。

某类休息的文案与动画都选“无”时，仅运行计时和声音；声音也关闭则完全安静运行，仍可从菜单查看状态。

设置自动保存在 `~/.config/restflow/config.json`，也支持直接编辑和相对素材路径。详见[配置说明](docs/CONFIGURATION.md)。

[源码构建](docs/BUILDING.md) · [MIT 许可](LICENSE) · [第三方许可](THIRD_PARTY_NOTICES.md)
