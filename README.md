# RestFlow

macOS 菜单栏休息工具。默认工作 **25 分钟**、短休息 **30 秒**、长休息 **5 分钟**；每 **2 段**工作后长休息。

- 暂停、继续、重新开始、现在休息；多屏同步休息，Esc 提前结束或关闭预览。
- 12 条文案、12 款矢量场景／动画，均支持随机；可添加文案、导入 PNG / JPEG / GIF / Lottie。
- 素材透明度滑块、中英文即时切换、可隐藏的菜单栏时间、通知及可调音量提示音。
- 开机启动、三个自定义全局快捷键；设置中检查 GitHub 新版本。

## 安装

[下载最新版本](https://github.com/wsgggws/RestFlow/releases/latest)，或通过 Homebrew：

```sh
brew tap wsgggws/restflow https://github.com/wsgggws/RestFlow.git
brew install --cask restflow
```

若 Homebrew 7 提示 `untrusted tap`，先执行 `brew trust --cask wsgggws/restflow/restflow`，再安装。

`wsgggws/restflow` 是 tap 名称，不能作为两段 Cask 安装名。首次 tap 后可使用上面的短命令；完整名称是 `wsgggws/restflow/restflow`。若希望首次安装省去显式仓库 URL，可另建标准命名的 `wsgggws/homebrew-restflow` 仓库来维护 Cask，但安装的完整名称仍为三段。

更新：`brew update && brew upgrade --cask wsgggws/restflow/restflow`。

预编译版本需要 **Apple Silicon、macOS 13+**，使用临时签名，**尚未 Apple 公证**。首次打开若被拦截，请核对下载来自本仓库后，按 macOS“系统设置 → 隐私与安全性”中的提示允许打开。Intel Mac 可从源码构建。

## 设置

从菜单栏打开设置。配置在 `~/.config/restflow/config.json`，文件修改约一秒生效；相对声音／素材路径以此目录为基准。

```json
{
  "shortMessageID": "__random__",
  "longMessageID": "__random__",
  "visualID": "__random__",
  "visualOpacity": 0.65
}
```

“现在休息”和预览共用入口，Esc 或点击底部 Esc 关闭；当前计时照常保持。快捷键在通用设置中录入，默认留空，冲突会提示更换。开机启动由 macOS 登录项目管理，必要时在系统设置批准。

同次休息的随机结果在各屏幕一致。时长修改从后续阶段生效，重新开始可立即应用。完整字段见 [配置说明](docs/CONFIGURATION.md) 和 [默认示例](Examples/config.json)。

## 从源码构建

需要 Apple Command Line Tools、Swift 5.9+；首次构建需联网获取固定版本的官方 Lottie。

```sh
git clone https://github.com/wsgggws/RestFlow.git
cd RestFlow
./scripts/test.sh
./scripts/build-app.sh
open dist/RestFlow.app
```

本地 Homebrew 构建安装使用 `./scripts/install-brew.sh`，详见 [Homebrew](Homebrew/README.md)。[开发约定](AGENTS.md) · [验证范围](docs/TESTING.md) · [发行流程](docs/RELEASING.md)。

所有功能免费，无广告、账户和分析追踪。仅版本检查访问 GitHub，可在设置中关闭。MIT 许可；第三方许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
