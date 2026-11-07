# 配置文件 / Configuration

设置保存在 `~/.config/restflow/config.json`。选择 JSON 是因为 Swift 原生支持、文案数组与 Unicode 无需自定义解析器。采用标准 UTF-8 JSON，字符串中的引号、反斜杠、换行分别写为 `\"`、`\\`、`\n`；直接输入中文和表情即可。JSON 不支持注释或末尾多余逗号。

首次运行 0.2.0 或后续版本时，若文件不存在，会迁移 0.1.0 的 UserDefaults 设置（含自定义文案和原素材引用）；已有配置文件始终优先。缺省字段使用默认值。错误字段名、错误类型、无效范围和未知语言都会被拒绝，界面显示错误。GUI 的修改自动原子保存，文件的外部修改约 1 秒后重载。修改时长不改变当前计时截止点，点击重新开始可立即应用新计划。

完整默认示例在 `Examples/config.json`。可先用设置页的“编辑配置”“在访达中显示”“重新加载”。错误配置不会被 GUI 覆盖；修复后自动恢复应用。若启动时文件已损坏，应用使用默认计划并暂停，不覆盖错误文件；运行中的错误则保留上次有效状态。

## 字段

| 字段 | 默认值 | 可选范围 / 意义 |
|---|---|---|
| `schemaVersion` | `1` | 当前只支持 `1` |
| `language` | `"zh-Hans"` | `"zh-Hans"` 或 `"en"`，立即切换界面及内置文案 |
| `checkForUpdatesAutomatically` | `true` | 启动／打开菜单时自动检查 GitHub 最新 Release，同一进程两次自动检查至少间隔 24 小时；关闭后仍可手动检查 |
| `visualGrayness` | `0` | `0...1`，素材灰度／淡化程度：0 为原色，1 更灰淡柔和；文字和计时不受影响，即时生效 |
| `showMenuBarTime` | `true` | 菜单栏是否显示时间；关闭后叶子图标与菜单保留 |
| `workMinutes` | `25` | `1...240`，分钟 |
| `shortBreakSeconds` | `30` | `5...1800`，秒 |
| `longBreakMinutes` | `5` | `1...120`，分钟 |
| `cycles` | `2` | `1...20`，多少段工作后安排长休息 |
| `prealertEnabled` | `true` | 开启工作结束前预告 |
| `warningSeconds` | `15` | `3...120`，提前秒数；若比工作时长长，在阶段开始后预告 |
| `soundEnabled` | `true` | 预告／开始／结束是否播放提示音 |
| `soundName` | `"Glass"` | macOS 系统声音名，例如 `Glass`、`Tink`、`Ping`、`Purr`、`Pop`、`Blow` |
| `soundPath` | `null` | 自定义本地声音文件，优先于 `soundName`；设置为 `null` 恢复系统声音 |
| `volume` | `0.5` | `0...1`，应用提示音音量，仍受系统音量影响 |
| `mediaPath` | `null` | 本地 PNG/JPEG/GIF/Lottie JSON；`null` 恢复默认视觉 |
| `visualID` | `"rings"` | 内置视觉 ID 或 `"__random__"`；`mediaPath` 有值时优先使用自定义素材 |
| `messages` | 12 条内置文案 | 共用文案库，1...100 条，ID 不重复；文本长度 1...2000 字符 |
| `shortMessageID` | `"eyes"` | 短休息使用的文案 ID，须存在于 `messages`；`__random__` 为随机 |
| `longMessageID` | `"stretch"` | 长休息使用的文案 ID，可与短休息相同；`__random__` 为随机 |

`messages` 项使用 `id`、`text`，可选 `englishText`。`text` 为原文；仅当明确设置了 `englishText` 时，英文界面显示该翻译。用户在 GUI 添加的文案不自动翻译，语言切换不改变原文。

```json
{
  "id": "my-reminder",
  "text": "喝水 💧 — \"慢一点\"\n伸展肩膀 ↗ ❤️"
}
```

用户文案按纯文本显示，不解析 Markdown；特殊符号、表情和换行可保留。新增文案后，在短／长休息的下拉框中选择；要批量编辑或删除，可直接修改 `messages`，同时确保两个选中 ID 仍然存在（或为 `__random__`）。保留 ID `__random__` 不能用于文案条目本身。

## 相对路径

所有相对路径相对于 **`~/.config/restflow/`**，与启动应用时的工作目录无关。也支持 `/` 开头的绝对路径和 `~/` 开头的用户目录路径；不支持远程 URL 或环境变量插值。

```json
{
  "mediaPath": "media/stretch.gif",
  "soundPath": "sounds/soft bell.wav"
}
```

上例对应 `~/.config/restflow/media/stretch.gif` 和 `~/.config/restflow/sounds/soft bell.wav`。路径可包含空格、中文与表情。直接配置是引用，不会复制或删除这些文件；GUI 导入则在配置目录下生成独立副本。Lottie 外部图片路径相对于 **该 Lottie JSON 所在目录**。

无效素材／声音会显示错误；无效素材显示默认视觉，无效声音保持静音。单个媒体／音频最大 20 MB；Lottie 外部图片最多 100 张、总大小最大 100 MB，只支持动画目录内部的相对图片引用。

## 调试预览与快捷键

菜单栏已移除预览项。设置页保留预览按钮；代码接口 `BreakWindowController.preview()` 保留。冷启动时也可使用：

```sh
open dist/RestFlow.app --args --preview --paused
```

参数只在新进程启动时读取。应用已运行时请用设置页预览。`--settings` 打开设置，`--paused` 以暂停状态启动。Esc 在预览窗口关闭预览，在真实休息窗口提前结束本次休息；这是应用内按键处理，不需要辅助功能权限，也不会在其他应用中监听 Esc。

## 通知与错误恢复

通知的授权状态由 macOS 管理，不能通过配置文件授予；在“通知与声音”中主动点击授权。除系统权限外，上表覆盖全部可持久化的应用设置。当前计时阶段、剩余时间、临时暂停和预览属于运行状态，不写入配置。

修复 JSON 时可使用 `python3 -m json.tool ~/.config/restflow/config.json` 检查语法。文件最大 1 MB。遇到同时编辑冲突，GUI 保留原设置，提示重新加载；先修好／重载文件，再修改 GUI，以免覆盖尚未应用的外部编辑。

## 内置文案与视觉（0.3.0）

默认计划为工作 25 分钟、短休息 30 秒、长休息 5 分钟、每 2 段工作后长休息。新配置包含 12 条文案，包含休息提醒及《道德经》《论语》《礼记》摘句，英文为释义。已有文件保持用户的计划与文案库；需要完整新默认值可参考 `Examples/config.json` 合并。

`shortMessageID`、`longMessageID` 与 `visualID` 均可设为 `"__random__"`。文案从当前共用库抽取，视觉从以下 12 款中抽取。每次休息／预览开始时选择一次，所有屏幕一致；暂停、倒计时刷新、切换语言不重新抽取。更换文案／视觉选择后立即更新。每次独立抽取可能与上次相同。

| visualID | 内置场景 |
|---|---|
| `rings` | 呼吸圆环 |
| `orbit` | 环绕星点 |
| `waves` | 轻柔海浪 |
| `rain` | 听雨时分 |
| `sunrise` | 日出微光 |
| `mountains` | 远山如黛 |
| `forest` | 林间片刻 |
| `lotus` | 莲瓣舒展 |
| `stars` | 静谧星空 |
| `clouds` | 云卷云舒 |
| `bamboo` | 竹影清风 |
| `fireflies` | 萤火微光 |

内置素材是应用绘制的矢量插画／动画，无需额外素材文件。系统“减少动态效果”开启时固定动画。设置中导入素材会切换至自定义；选择内置素材会清空 `mediaPath` 并清理此前 GUI 导入的托管媒体副本；直接配置的外部文件不删除。如需保留原素材用于再次导入，请保留源文件。

自动化界面调试可冷启动附加 `--ui-test --settings --paused`，仅本次运行显示 Dock 图标以供系统自动化识别；正常启动保持菜单栏模式。

## 版本与灰度（0.4.0）

菜单顶部显示当前版本，并提供检查更新或“可升级至 vX.Y.Z”入口，点击可升级项会打开固定仓库的 Release 页面。检查使用 `https://api.github.com/repos/wsgggws/RestFlow/releases/latest`；遇到公共 API 限流时，回退到 GitHub 官方 `releases/latest` 重定向，仅接受同仓库稳定版本的地址；无账户、无配置上传。检查失败不影响计时，不自动下载或安装。

设置 → 休息界面中的灰度滑块同时作用于内置视觉及自定义图片／GIF／Lottie。数值越高，颜色越灰、透明度越低、边缘越柔和。外部文件修改 `visualGrayness` 同样约一秒生效。

隐藏时间时图标区域为 18 点，图案为 14 点；显示时间时去掉额外前置空格。相邻应用和系统菜单栏的公共间距仍由 macOS 管理。调试宽度可冷启动附加 `--diagnostics`，终端输出当前图标区域宽度（pt）。
