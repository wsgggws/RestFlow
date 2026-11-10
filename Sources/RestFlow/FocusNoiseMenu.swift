import AppKit
import RestFlowCore

/// Native submenu tracking handles hover/exit; controls handle clicks without ending tracking.
/// Keep the same items and views alive while preferences change so a multi-select never collapses.
@MainActor
final class FocusNoiseMenu {
    let menu = NSMenu()
    private let model: AppModel
    private let didSelect: () -> Void

    init(model: AppModel, didSelect: @escaping () -> Void) {
        self.model = model; self.didSelect = didSelect
        menu.autoenablesItems = false
        for id in [AppSettings.randomSoundID] + FocusNoise.allCases.map(\.rawValue) {
            if menu.items.count == 1 { menu.addItem(.separator()) }
            // The control alone owns activation. A menu-item action would also dispatch on mouse-up,
            // toggling twice and ending native tracking after an otherwise successful checkbox click.
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.representedObject = id
            let row = NoiseMenuRow { [weak self] in self?.select(id) }
            item.view = row
            menu.addItem(item)
        }
        refresh()
    }

    func refresh() {
        for item in menu.items {
            guard let id = item.representedObject as? String, let row = item.view as? NoiseMenuRow else { continue }
            let random = id == AppSettings.randomSoundID
            item.title = random ? model.text("随机", "Random") : (FocusNoise(rawValue: id)?.title(in: model.settings.language) ?? id)
            item.state = (random ? model.settings.focusNoiseRandom : model.settings.focusNoiseIDs.contains(id)) ? .on : .off
            row.button.title = item.title; row.button.state = item.state
        }
    }

    private func select(_ id: String) {
        if id == AppSettings.randomSoundID { model.rerollFocusNoise() }
        else if let noise = FocusNoise(rawValue: id) { model.toggleFocusNoiseSelection(noise) }
        refresh()
        didSelect()
    }
}

@MainActor
final class NoiseMenuRow: NSView {
    let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let select: () -> Void

    init(select: @escaping () -> Void) {
        self.select = select
        super.init(frame: NSRect(x: 0, y: 0, width: 204, height: 27))
        autoresizingMask = [.width]
        button.frame = NSRect(x: 13, y: 2, width: 180, height: 23)
        button.autoresizingMask = [.width]
        button.font = .menuFont(ofSize: 0)
        button.target = self; button.action = #selector(choose)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func choose() { select() }
}
