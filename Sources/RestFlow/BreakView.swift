import AppKit
import Lottie
import SwiftUI
import RestFlowCore

struct BreakView: View {
    @ObservedObject var model: AppModel
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let mint = Color(red: 0.63, green: 0.89, blue: 0.76)

    private var isLong: Bool { model.phase == .longBreak }
    private var message: String {
        let text = model.breakContent.message(for: isLong ? .longBreak : .shortBreak, settings: model.settings)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.text("放松肩膀，慢慢呼吸。", "Relax your shoulders. Take a slow breath.") : text
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.035, green: 0.105, blue: 0.09),
                                            Color(red: 0.075, green: 0.19, blue: 0.15)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(mint.opacity(0.045)).frame(width: 750, height: 750).offset(x: 350, y: -280)
                }.modifier(VisualTreatment(transparency: model.settings.breakTransparency))
                VStack(spacing: 22) {
                    visual
                        .modifier(VisualTreatment(transparency: model.settings.breakTransparency))
                        .frame(width: min(400, geometry.size.width * 0.55),
                               height: min(250, geometry.size.height * 0.29))
                    Text(message)
                        .font(.system(size: min(32, geometry.size.width / 25), weight: .light, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                        .lineLimit(5).frame(maxWidth: 650)
                    Text(model.timeText)
                        .font(.system(size: 56, weight: .ultraLight, design: .rounded))
                        .monospacedDigit().foregroundStyle(mint)
                    if model.isPaused {
                        Text(model.text("已暂停", "Paused")).font(.caption).foregroundStyle(mint)
                    }
                    HStack(spacing: 14) {
                        if !compact {
                            breakButton(model.isPaused ? model.text("继续", "Resume") : model.text("暂停", "Pause"),
                                        symbol: model.isPaused ? "play.fill" : "pause.fill") { model.togglePause() }
                        }
                        Button(action: { model.endBreak() }) {
                            Text("Esc").font(.system(size: 13)).padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.85))
                    }.padding(.top, 4)
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shadow(color: .black.opacity(model.settings.breakTransparency * 0.9), radius: 3, x: 0, y: 1)

                if !compact { VStack {
                    Spacer()
                    HStack {
                        Text("RESTFLOW").tracking(4)
                        Spacer()
                        Button(model.text("重新开始", "Restart")) { model.restart() }.buttonStyle(.plain)
                        Text("·")
                        Button(model.text("退出", "Quit")) { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    .padding(24)
                } }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var visual: some View {
        if let url = model.mediaURL, model.mediaIsValid, FileManager.default.fileExists(atPath: url.path) {
            ImportedMediaView(url: url, isPaused: model.isPaused, reduceMotion: reduceMotion)
                .id(url).clipShape(RoundedRectangle(cornerRadius: 22))
        } else {
            BuiltinVisualView(visual: model.breakContent.visual, isPaused: model.isPaused, language: model.settings.language)
        }
    }

    private func breakButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.13)))
        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.85))
    }
}

private struct ImportedMediaView: NSViewRepresentable {
    let url: URL
    let isPaused: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> NSView {
        if url.pathExtension.lowercased() == "json", let animation = LottieAnimation.filepath(url.path) {
            let view = LottieAnimationView(animation: animation)
            view.imageProvider = FilepathImageProvider(filepath: url.deletingLastPathComponent().path)
            view.loopMode = .loop
            view.backgroundBehavior = .pauseAndRestore
            view.contentMode = .scaleAspectFit
            return view
        }
        let view = NSImageView()
        view.image = NSImage(contentsOf: url)
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let animation = nsView as? LottieAnimationView {
            if isPaused || reduceMotion { animation.pause() }
            else if !animation.isAnimationPlaying { animation.play() }
        } else if let image = nsView as? NSImageView {
            image.animates = !isPaused && !reduceMotion
        }
    }
}
