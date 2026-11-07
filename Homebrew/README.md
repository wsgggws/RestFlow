# Homebrew

公开安装：

```sh
brew tap wsgggws/restflow https://github.com/wsgggws/RestFlow.git
brew install --cask wsgggws/restflow/restflow
```

若 Homebrew 7 提示 `untrusted tap`，先执行 `brew trust --cask wsgggws/restflow/restflow`，再安装。

本仓库同时充当 tap，`Casks/restflow.rb` 引用版本化 GitHub Release 和 SHA-256。预编译版本支持 Apple Silicon / macOS 13+，尚未 Apple 公证，首次打开遵循 macOS 的允许打开提示。

```sh
brew update
brew upgrade --cask wsgggws/restflow/restflow
brew uninstall --cask wsgggws/restflow/restflow
```

卸载保留 `~/.config/restflow/`。如已安装旧的本地 Cask，先退出应用并执行 `brew uninstall --cask restflow/local/restflow`，再安装公开 Cask，配置仍然保留。

开发者本机构建安装：在源码根目录执行 `./scripts/install-brew.sh`。脚本构建本机架构、生成 `restflow/local` 本地 Cask 并安装；再次执行可重新安装。它会校验安装副本与刚构建的文件一致，只清除该副本的下载隔离标记，保持系统 Gatekeeper 设置不变。此逻辑只用于本机构建，不属于公开 Cask。
