import AppKit
import SwiftUI
import RestFlowCore
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    let preview: () -> Void
    private let accent = Color(red: 0.14, green: 0.57, blue: 0.42)
    private func t(_ zh: String, _ en: String) -> String { model.text(zh, en) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill").foregroundStyle(accent)
                Text("RestFlow").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Text(model.isPaused ? t("已暂停", "Paused") : model.phaseTitle)
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.timeText).font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
                Button(model.isPaused ? t("继续", "Resume") : t("暂停", "Pause")) { model.togglePause() }
                Button(t("重新开始", "Restart")) { model.restart() }
            }.padding(20)

            if let error = model.configurationError {
                Label(t("配置未应用：", "Configuration not applied: ") + error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 12)
                    .lineLimit(3)
            }

            TabView {
                generalTab.tabItem { Label(t("通用", "General"), systemImage: "gearshape") }
                planTab.tabItem { Label(t("计划", "Schedule"), systemImage: "timer") }
                appearanceTab.tabItem { Label(t("休息界面", "Appearance"), systemImage: "photo") }
                feedbackTab.tabItem { Label(t("通知与声音", "Sound & alerts"), systemImage: "bell") }
            }.padding(.horizontal, 16).padding(.bottom, 12)

            Divider()
            HStack {
                Spacer()
                Button(t("预览休息界面", "Preview break")) { preview() }
                    .buttonStyle(.bordered)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 620, height: 620)
        .tint(accent)
        .environment(\.locale, Locale(identifier: model.settings.language.rawValue))
        .onAppear { model.refreshNotificationStatus() }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox {
                    VStack(spacing: 10) {
                        Picker(t("界面语言", "Interface language"), selection: $model.settings.language) {
                            Text("简体中文").tag(AppLanguage.simplifiedChinese)
                            Text("English").tag(AppLanguage.english)
                        }
                        Toggle(t("在菜单栏显示剩余时间", "Show remaining time in the menu bar"), isOn: $model.settings.showMenuBarTime)
                        Toggle(t("开机启动", "Launch at login"), isOn: $model.settings.launchAtLogin)
                        if model.settings.launchAtLogin && model.loginItem.status == .requiresApproval {
                            Button(t("在系统设置中允许启动", "Allow in System Settings")) { SMAppService.openSystemSettingsLoginItems() }
                        }
                    }.padding(8)
                } label: { Label(t("界面", "Interface"), systemImage: "menubar.rectangle") }
                GroupBox {
                    VStack(spacing: 10) {
                        shortcutRow(t("暂停／继续计时", "Pause / resume"), keyPath: \.pauseShortcut)
                        shortcutRow(t("重新开始", "Restart"), keyPath: \.restartShortcut)
                        shortcutRow(t("现在休息", "Rest now"), keyPath: \.restNowShortcut)
                    }.padding(10)
                } label: { Text(t("快捷键", "Keyboard shortcuts")) }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.configuration.fileURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button(t("编辑配置", "Edit config")) { model.openConfiguration() }
                            Button(t("在访达中显示", "Show in Finder")) { model.revealConfiguration() }
                            Spacer()
                            Button(t("重新加载", "Reload")) { model.reloadConfiguration(force: true) }
                        }
                    }.padding(8)
                } label: { Label(t("配置文件", "Configuration file"), systemImage: "doc.text") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("RestFlow \(updates.currentVersion)")
                            Spacer()
                            Button(updates.status(in: model.settings.language)) {
                                if case .available = updates.state { updates.openRelease() }
                                else { updates.check() }
                            }.disabled(isCheckingUpdates)
                        }
                        Toggle(t("自动检查更新", "Check for updates automatically"), isOn: $model.settings.checkForUpdatesAutomatically)
                    }.padding(8)
                } label: { Text(t("版本", "Version")) }
            }.padding(8)
        }
    }

    private var planTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(spacing: 18) {
                    durationRow(t("专注", "Focus"), value: $model.settings.workMinutes, range: 1...240, step: 1, unit: t("分钟", "min"))
                    Divider()
                    durationRow(t("短休息", "Short break"), value: $model.settings.shortBreakSeconds, range: 5...1800, step: 5, unit: t("秒", "sec"))
                    Divider()
                    durationRow(t("长休息", "Long break"), value: $model.settings.longBreakMinutes, range: 1...120, step: 1, unit: t("分钟", "min"))
                    Divider()
                    Stepper(value: $model.settings.cycles, in: 1...20) {
                        HStack {
                            Text(t("长休息周期", "Long-break cycle"))
                            Spacer()
                            Text(t("每 \(model.settings.cycles) 段专注", "Every \(model.settings.cycles) sessions")).foregroundStyle(.secondary)
                        }
                    }
                }.padding(12)
            }
            note(t("修改从下个阶段生效；重新开始可立即应用。", "Changes apply to upcoming phases. Restart to apply now."))
            Spacer()
        }.padding(16)
    }

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        messagePicker(t("短休息", "Short break"), selection: $model.settings.shortMessageID)
                        messagePicker(t("长休息", "Long break"), selection: $model.settings.longMessageID)
                        HStack {
                            Spacer()
                            Button { addMessage() } label: { Label(t("添加文案", "Add message"), systemImage: "plus") }
                                .disabled(model.settings.messages.count >= 100)
                        }
                    }.padding(10)
                } label: { Text(t("文案", "Messages")) }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker(t("素材", "Visual"), selection: visualSelection) {
                                Text(t("无", "None")).tag(BuiltinVisual.noneID)
                                Text(t("随机", "Random")).tag(BuiltinVisual.randomID)
                                ForEach(BuiltinVisual.allCases, id: \.rawValue) { visual in
                                    Text(visual.title(in: model.settings.language)).tag(visual.rawValue)
                                }
                                if model.settings.mediaPath != nil {
                                    Text(t("自定义", "Custom")).tag("__custom__")
                                }
                            }
                            Button(t("导入…", "Import…")) { model.importMedia() }
                        }
                        if let path = model.settings.mediaPath {
                            Text(model.mediaURL?.lastPathComponent ?? path).font(.caption).lineLimit(1)
                            Text("PNG / JPEG / GIF / Lottie JSON").font(.caption).foregroundStyle(.secondary)
                        } else if model.settings.hasVisual {
                            BuiltinVisualView(visual: model.breakContent.visual, language: model.settings.language)
                                .modifier(VisualTreatment(transparency: model.settings.breakTransparency))
                                .frame(width: 180, height: 112).frame(maxWidth: .infinity)
                                .background(Color(red: 0.04, green: 0.13, blue: 0.10).opacity(1 - model.settings.breakTransparency), in: RoundedRectangle(cornerRadius: 10))
                        }
                        HStack(spacing: 10) {
                            Text(t("背景透明度", "Background transparency"))
                            Slider(value: $model.settings.breakTransparency, in: 0...1)
                                .accessibilityLabel(t("背景透明度", "Background transparency"))
                                .help(t("0% 完全遮住桌面，100% 显示桌面；背景与动画一起变淡", "0% covers the desktop, 100% reveals it; background and artwork fade together"))
                            Text("\(Int(model.settings.breakTransparency * 100))%")
                                .monospacedDigit().frame(width: 38, alignment: .trailing)
                        }
                        if let error = model.mediaError {
                            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                        }
                    }.padding(10)
                } label: { Text(t("图片与动画", "Images & animation")) }
            }.padding(12)
        }
    }

    private func shortcutRow(_ title: String, keyPath: WritableKeyPath<AppSettings, RestFlowCore.KeyboardShortcut?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(model: model, keyPath: keyPath).frame(width: 220, height: 26)
            Button { model.settings[keyPath: keyPath] = nil } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(t("清除快捷键", "Clear shortcut"))
                .disabled(model.settings[keyPath: keyPath] == nil)
        }
    }

    private var isCheckingUpdates: Bool {
        if case .checking = updates.state { return true }
        return false
    }

    private var visualSelection: Binding<String> {
        Binding(get: { model.settings.mediaPath == nil ? model.settings.visualID : "__custom__" },
                set: { if $0 != "__custom__" { model.selectVisual($0) } })
    }

    private var feedbackTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(t("工作结束前提醒我", "Remind me before a break"), isOn: $model.settings.prealertEnabled)
                        durationRow(t("提前时间", "Lead time"), value: $model.settings.warningSeconds, range: 3...120, step: 1, unit: t("秒", "sec"))
                            .disabled(!model.settings.prealertEnabled)
                        HStack {
                            Text(model.notificationStatus).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(t("允许通知…", "Allow notifications…")) { model.requestNotifications() }
                        }
                        note(t("系统专注模式可能隐藏通知；这不影响计时和休息界面。",
                               "System Focus may hide notifications. The timer and break display continue to work."))
                    }.padding(12)
                } label: { Label(t("休息预告", "Break prealert"), systemImage: "bell") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(t("播放提示音", "Play sounds"), isOn: $model.settings.soundEnabled)
                        Picker(t("系统提示音", "System sound"), selection: Binding(
                            get: { model.settings.soundPath == nil ? model.settings.soundName : "__custom__" },
                            set: { value in
                                guard value != "__custom__" else { return }
                                var settings = model.settings
                                settings.soundName = value
                                settings.soundPath = nil
                                model.settings = settings
                            })) {
                            Text(t("无", "None")).tag(AppSettings.noSoundID)
                            ForEach(["Glass", "Tink", "Ping", "Purr", "Pop", "Blow"], id: \.self) { Text($0).tag($0) }
                            if model.settings.soundPath != nil { Text(t("自定义", "Custom")).tag("__custom__") }
                        }.disabled(!model.settings.soundEnabled)
                        HStack {
                            Text(model.settings.soundPath ?? (model.settings.soundName == AppSettings.noSoundID ? t("无", "None") : t("使用系统提示音", "Using system sound")))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                            Spacer()
                            Button(t("导入声音…", "Import sound…")) { model.importSound() }
                            if model.settings.soundPath != nil {
                                Button(t("使用系统声音", "Use system sound")) { model.settings.soundPath = nil }
                            }
                        }
                        HStack {
                            Image(systemName: "speaker.fill")
                            Slider(value: $model.settings.volume, in: 0...1).accessibilityLabel(t("提示音音量", "Sound volume"))
                            Text("\(Int(model.settings.volume * 100))%").monospacedDigit().frame(width: 42, alignment: .trailing)
                            Button(t("试听", "Test sound")) { model.playSound() }.disabled(!model.settings.hasSound)
                        }.disabled(!model.settings.soundEnabled)
                        if let error = model.soundError {
                            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                        }
                    }.padding(12)
                } label: { Label(t("声音", "Sound"), systemImage: "speaker.wave.2") }
            }.padding(8)
        }
    }

    private func messagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text(t("无", "None")).tag(ReminderMessage.noneID)
            Text(t("随机", "Random")).tag(ReminderMessage.randomID)
            ForEach(model.settings.messages) { message in
                Text(message.displayText(in: model.settings.language).replacingOccurrences(of: "\n", with: " ")).lineLimit(1).tag(message.id)
            }
        }.pickerStyle(.menu)
    }

    private func addMessage() {
        let alert = NSAlert()
        alert.messageText = t("添加休息文案", "Add a reminder message")
        alert.informativeText = t("支持特殊字符、表情和换行，最多 2000 个字符。", "Use symbols, emoji and newlines. Maximum 2,000 characters.")
        alert.addButton(withTitle: t("添加", "Add"))
        alert.addButton(withTitle: t("取消", "Cancel"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 410, height: 110))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let editor = NSTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 14)
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = editor
        if alert.runModal() == .alertFirstButtonReturn, !model.addMessage(editor.string), model.configurationError == nil {
            let error = NSAlert()
            error.messageText = t("文案未添加", "Message not added")
            error.informativeText = t("请输入 1–2000 个字符。文案库最多 100 条。", "Enter 1–2,000 characters. The library holds up to 100 messages.")
            error.runModal()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func durationRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
