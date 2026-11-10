import AppKit
import SwiftUI
import RestFlowCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    let preview: () -> Void
    @StateObject private var noiseChoices = NoiseChoicesState()
    private let accent = Color(red: 0.14, green: 0.57, blue: 0.42)
    private func t(_ zh: String, _ en: String) -> String { model.text(zh, en) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill").foregroundStyle(accent)
                Text("坐忘录 · RestFlow").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Text(model.isPreview ? t("预览", "Preview") : (model.isAway ? t("已离开", "Away") : (model.isOutsideOperatingHours ? t("非运行时段", "Outside hours") : (model.isPaused ? t("已暂停", "Paused") : model.phaseTitle))))
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.timeText).font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
                Button(model.isPaused ? t("继续", "Resume") : t("暂停", "Pause")) { model.togglePause() }.disabled(!model.isPreview && (model.isOutsideOperatingHours || model.isAway))
                Button(t("重新开始", "Restart")) { model.restart() }
            }.padding(16)

            if let error = model.configurationError {
                Label(t("配置未应用：", "Configuration not applied: ") + error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 12)
                    .lineLimit(3)
            }

            TabView {
                planTab.tabItem { Label(t("计划", "Schedule"), systemImage: "timer") }
                appearanceTab.tabItem { Label(t("休息", "Break"), systemImage: "photo") }
                generalTab.tabItem { Label(t("通用", "General"), systemImage: "gearshape") }
                StatisticsView(model: model).tabItem { Label(t("统计", "Statistics"), systemImage: "chart.bar") }
            }.padding(.horizontal, 16).padding(.bottom, 12)

            Divider()
            HStack {
                Spacer()
                Button(t("预览", "Preview")) { preview() }
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
                    }.padding(8)
                } label: { Label(t("界面", "Interface"), systemImage: "menubar.rectangle") }
                GroupBox {
                    VStack(spacing: 10) {
                        shortcutRow(t("暂停／继续计时", "Pause / resume"), keyPath: \.pauseShortcut)
                        shortcutRow(t("重新开始", "Restart"), keyPath: \.restartShortcut)
                        shortcutRow(t("现在休息", "Rest now"), keyPath: \.restNowShortcut)
                        shortcutRow(t("开启／关闭白噪音", "Toggle white noise"), keyPath: \.focusNoiseShortcut)
                    }.padding(10)
                } label: { Text(t("快捷键", "Keyboard shortcuts")) }
                DisclosureGroup(t("高级：配置文件", "Advanced: configuration file")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.configuration.fileURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button(t("编辑配置", "Edit config")) { model.openConfiguration() }
                            Button(t("在访达中显示", "Show in Finder")) { model.revealConfiguration() }
                            Spacer()
                            Button(t("重新加载", "Reload")) { model.reloadConfiguration(force: true) }
                        }
                    }.padding(8)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(AppIdentity.displayName) \(updates.currentVersion)")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(spacing: 18) {
                        durationRow(t("专注", "Focus"), value: $model.settings.workMinutes, range: 1...240, step: 1, unit: t("分钟", "min"))
                        noiseControls
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
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(t("离开时自动暂停", "Pause when away"), isOn: $model.settings.idleDetectionEnabled)
                            .help(t("闲置 1 分钟暂停，满 5 分钟后重新专注；阅读或看视频时可关闭。", "Pause after 1 idle minute; start fresh after 5 minutes. Turn off while reading or watching videos."))
                        Toggle(t("允许延后 3 分钟", "Allow a 3-minute delay"), isOn: $model.settings.deferEnabled)
                    }.padding(10)
                }
                OperatingHoursView(schedule: $model.settings.operatingSchedule, language: model.settings.language)
                Spacer(minLength: 0)
            }.padding(16)
        }
    }


    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        messagePicker(t("短休息", "Short break"), selection: $model.settings.shortMessageID)
                        messagePicker(t("长休息", "Long break"), selection: $model.settings.longMessageID)
                        HStack {
                            if ReminderMessage.defaults.contains(where: { original in !model.settings.messages.contains { $0.id == original.id } }) {
                                Button(t("恢复内置文案", "Restore built-in messages")) { model.settings.restoreBuiltinMessages() }
                            }
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
                                ForEach(model.settings.availableVisuals, id: \.rawValue) { visual in
                                    Text(visual.title(in: model.settings.language)).tag(visual.rawValue)
                                }
                                if model.settings.mediaPath != nil {
                                    Text(t("自定义", "Custom")).tag("__custom__")
                                }
                            }
                            deleteButton(t("删除当前素材", "Delete selected visual"), disabled: model.settings.mediaPath == nil && BuiltinVisual(rawValue: model.settings.visualID) == nil) {
                                if confirmDeletion(t("删除当前素材？", "Delete selected visual?"), detail: model.settings.mediaPath != nil
                                    ? t("仅移除应用中的副本或引用，保留原始文件。", "Removes the app's copy or reference. The original file is kept.")
                                    : t("可通过“恢复内置动画”重新加入。", "You can add it back with Restore built-in animations.")) { model.deleteSelectedVisual() }
                            }
                            Button(t("导入…", "Import…")) { model.importMedia() }
                        }
                        if !model.settings.excludedVisualIDs.isEmpty {
                            Button(t("恢复内置动画", "Restore built-in animations")) { model.settings.excludedVisualIDs = [] }
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
                            Text("\(Int((model.settings.breakTransparency * 100).rounded()))%")
                                .monospacedDigit().frame(width: 38, alignment: .trailing)
                        }
                        if let error = model.mediaError {
                            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                        }
                    }.padding(10)
                } label: { Text(t("动画", "Animation")) }
                feedbackContent
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

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(t("启用白噪音", "Enable white noise"), isOn: Binding(
                get: { model.settings.focusNoiseEnabled }, set: { _ in model.toggleFocusNoise() }))
            HStack {
                DisclosureGroup(t("声音选择", "Noise selection"), isExpanded: $noiseChoices.expanded) { EmptyView() }
                Spacer()
                Toggle(t("随机", "Random"), isOn: Binding(
                    get: { model.settings.focusNoiseRandom },
                    set: { model.settings.selectRandomFocusNoise($0) })).fixedSize()
                Stepper(value: $model.settings.focusNoiseRandomCount, in: 1...FocusNoise.allCases.count) {
                    Text(t("混合 \(model.settings.focusNoiseRandomCount) 种", "Mix \(model.settings.focusNoiseRandomCount)"))
                        .monospacedDigit()
                }.fixedSize().disabled(!model.settings.focusNoiseRandom)
            }
            if noiseChoices.expanded {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
                        ForEach(FocusNoise.allCases, id: \.rawValue) { noise in
                            Toggle(noise.title(in: model.settings.language), isOn: Binding(
                                get: { model.settings.focusNoiseIDs.contains(noise.rawValue) }, set: { selected in
                                    var updated = model.settings
                                    updated.focusNoiseIDs.removeAll { $0 == noise.rawValue }
                                    if selected { updated.focusNoiseIDs.append(noise.rawValue) }
                                    updated.focusNoiseEnabled = !updated.focusNoiseIDs.isEmpty
                                    model.settings = updated
                                })).disabled(model.settings.focusNoiseRandom)
                        }
                    }
                }.padding(.top, 8)
            }
            HStack {
                Text(t("音量", "Volume"))
                Slider(value: $model.settings.focusNoiseVolume, in: 0...1)
                    .accessibilityLabel(t("白噪音音量", "White noise volume"))
                Text("\(Int((model.settings.focusNoiseVolume * 100).rounded()))%")
                    .monospacedDigit().frame(width: 38, alignment: .trailing)
            }
            if let error = model.focusNoiseError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var feedbackContent: some View {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(t("工作结束前提醒我", "Remind me before a break"), isOn: $model.settings.prealertEnabled)
                        if model.settings.prealertEnabled {
                            durationRow(t("提前时间", "Lead time"), value: $model.settings.warningSeconds, range: 3...120, step: 1, unit: t("秒", "sec"))
                            if model.notificationAuthorization != .authorized && model.notificationAuthorization != .provisional {
                                HStack {
                                    Text(model.notificationStatus).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(t("允许通知…", "Allow notifications…")) { model.requestNotifications() }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                } label: { Label(t("休息预告", "Break prealert"), systemImage: "bell") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(t("提示音", "Alert sound"), selection: Binding(
                            get: { !model.settings.soundEnabled ? AppSettings.noSoundID : (model.settings.soundPath == nil ? model.settings.soundName : "__custom__") },
                            set: { model.selectSound($0) })) {
                            Text(t("无", "None")).tag(AppSettings.noSoundID)
                            Text(t("随机", "Random")).tag(AppSettings.randomSoundID)
                            ForEach(model.settings.availableSounds, id: \.rawValue) { tone in
                                Text(tone.title(in: model.settings.language)).tag(tone.rawValue)
                            }
                            if model.settings.soundPath != nil { Text(t("自定义", "Custom")).tag("__custom__") }
                        }
                        HStack {
                            if !model.settings.excludedSoundIDs.isEmpty {
                                Button(t("恢复内置提示音", "Restore built-in sounds")) { model.settings.excludedSoundIDs = [] }
                            }
                            if let path = model.settings.soundPath {
                                Text(model.soundURL?.lastPathComponent ?? path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            deleteButton(t("移除当前提示音", "Hide selected sound"), disabled: !model.settings.soundEnabled || (model.settings.soundPath == nil && AlertTone(rawValue: model.settings.soundName) == nil)) {
                                model.hideSelectedSound()
                            }
                            Button(t("导入声音…", "Import sound…")) { model.importSound() }
                            if model.settings.soundPath != nil {
                                Button(t("使用内置声音", "Use built-in sound")) { model.settings.soundPath = nil }
                            }
                        }
                        HStack {
                            Image(systemName: "speaker.fill")
                            Slider(value: $model.settings.volume, in: 0...1).accessibilityLabel(t("提示音音量", "Sound volume"))
                            Text("\(Int(model.settings.volume * 100))%").monospacedDigit().frame(width: 42, alignment: .trailing)
                            Button(t("试听", "Test sound")) { model.playSound() }.disabled(!model.settings.hasSound)
                        }.disabled(!model.settings.hasSound && model.settings.volume > 0)
                        if let error = model.soundError {
                            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                        }
                    }.padding(12)
                } label: { Label(t("声音", "Sound"), systemImage: "speaker.wave.2") }
            }
    }

    private func deleteButton(_ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "trash") }
            .buttonStyle(.borderless).help(label).accessibilityLabel(label).disabled(disabled)
    }

    private func confirmDeletion(_ title: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: t("删除", "Delete"))
        alert.addButton(withTitle: t("取消", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func messagePicker(_ title: String, selection: Binding<String>) -> some View {
        HStack {
            Picker(title, selection: selection) {
                Text(t("无", "None")).tag(ReminderMessage.noneID)
                Text(t("随机", "Random")).tag(ReminderMessage.randomID)
                ForEach(model.settings.messageChoices(selectedID: selection.wrappedValue)) { message in
                    Text(message.displayText(in: model.settings.language).replacingOccurrences(of: "\n", with: " ")).lineLimit(1).tag(message.id)
                }
            }.pickerStyle(.menu)
            deleteButton(t("删除当前文案", "Delete selected message"), disabled: !model.settings.messages.contains { $0.id == selection.wrappedValue }) {
                let id = selection.wrappedValue
                if confirmDeletion(t("删除当前文案？", "Delete selected message?"), detail: String((model.settings.messages.first { $0.id == id }?.displayText(in: model.settings.language) ?? "").prefix(160))) {
                    model.deleteMessage(id)
                }
            }
        }
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
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result = model.addMessage(editor.string)
        if result == .duplicate || result == .invalid {
            let notice = NSAlert()
            notice.messageText = result == .duplicate ? t("文案已存在", "Message already exists") : t("文案未添加", "Message not added")
            notice.informativeText = result == .duplicate
                ? t("请从下拉框选择已有文案。", "Choose the existing message from the list.")
                : t("请输入 1–2000 个字符。文案库最多 100 条。", "Enter 1–2,000 characters. The library holds up to 100 messages.")
            notice.runModal()
        }
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

private final class NoiseChoicesState: ObservableObject { @Published var expanded = false }
