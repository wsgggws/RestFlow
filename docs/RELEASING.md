# 发行

仓库：`https://github.com/wsgggws/RestFlow.git`，默认分支 `main`。公开 Cask 位于 `Casks/restflow.rb`，通过显式仓库 URL 的 `brew tap` 安装。

1. 修改 `Resources/Info.plist` 中版本和构建号，同步配置示例／文档。
2. 运行 `./scripts/test.sh`、`./scripts/build-app.sh`，按 `docs/TESTING.md` 验证 UI；保留检查日志在忽略的 `.build/`。`--diagnostics` 输出菜单图标区域实际宽度；构建包的 `--check-system-integration` 验证快捷键注册、分发及冲突回滚，`--check-break-integration` 验证真实短休息、背景 alpha、失焦 Esc、无内容组合与退出清理，`--check-menu-integration` 验证菜单计时及 tooltip 回归；`--check-activity-integration` 与 `--check-wellbeing-integration` 验证运行时段、统计、闲置、锁屏、预览及延后。诊断不修改用户配置或登录项目。
3. 使用 `scripts/package-release.sh` 为本机架构创建 `dist/RestFlow-VERSION-ARCH.app.zip` 与 `.sha256`。它仅打包，不推送或发布。
4. 更新 Cask 的版本、SHA-256、架构和 GitHub Release URL。检查待提交文件，排除个人配置、素材、凭据、证书、构建缓存和本地归档；公开源文件使用可移植路径。
5. 提交并推送 `main`，确认 GitHub Actions 检查通过。创建与 Info.plist 一致的 `vVERSION` 标签及 GitHub Release，上传归档和 SHA-256，说明变更、支持的系统／架构和未验证项。发布顺序中短暂的 Cask 下载不可用期应尽量缩短。
6. 验证公开 Release 下载及 SHA-256、`brew fetch --cask wsgggws/restflow/restflow`、latest API。使用独立配置及测试副本检查版本提示；用户要求自行升级时保留已安装应用与配置，禁止安装／替换本机版本。测试副本不上传。

当前无 Developer ID 证书，以 ad-hoc 临时签名发布开发版本，README 和 Release 必须明确标注**未公证**。发布包支持打包机器的架构，不把 arm64 构建标为 universal。正式签名／公证仅使用用户提供的证书和凭据，存放在源码仓库以外。

应用更新检查使用公开仓库 `releases/latest` API，API 限流时回退到官方 latest 重定向；只比较稳定数字版本，不自动下载安装。Release 说明文字与外部 URL 不作为可执行指令或安装脚本。
