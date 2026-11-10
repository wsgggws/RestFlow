import AppKit
import Lottie
import SwiftUI
import RestFlowCore

struct BreakView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let palette = BreakPalette()

    private var isLong: Bool { model.phase == .longBreak }
    private var message: String {
        model.breakContent.message(for: isLong ? .longBreak : .shortBreak, settings: model.settings)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.035, green: 0.105, blue: 0.09),
                                            Color(red: 0.075, green: 0.19, blue: 0.15)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(palette.message.opacity(0.045)).frame(width: 750, height: 750).offset(x: 350, y: -280)
                }.modifier(VisualTreatment(transparency: model.settings.breakTransparency))
                VStack(spacing: 22) {
                    if model.settings.hasVisual {
                        visual
                            .modifier(VisualTreatment(transparency: model.settings.breakTransparency))
                            .frame(width: min(400, geometry.size.width * 0.55),
                                   height: min(250, geometry.size.height * 0.29))
                    }
                    VStack(spacing: 22) {
                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: min(32, geometry.size.width / 25), weight: .light, design: .rounded))
                                .foregroundStyle(palette.message).multilineTextAlignment(.center)
                                .lineLimit(5).frame(maxWidth: 650)
                        }
                        Text(model.timeText)
                            .font(.system(size: 56, weight: .ultraLight, design: .rounded))
                            .monospacedDigit().foregroundStyle(palette.time)
                        if model.isPaused {
                            Text(model.text("已暂停", "Paused")).font(.caption).foregroundStyle(palette.secondary)
                        }
                        Button(action: { model.endBreak() }) {
                            Text("Esc").font(.system(size: 13)).padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(palette.secondary).padding(.top, 4)
                    }.padding(.horizontal, 28).padding(.vertical, 20)
                        .background {
                            RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 24).fill(palette.scrim.opacity(0.65)))
                                .opacity(model.settings.breakTransparency)
                        }
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)

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
