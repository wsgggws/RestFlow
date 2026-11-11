import AppKit
import SwiftUI
import RestFlowCore

@MainActor
enum SettingsIntegrationChecks {
    static func run() -> Int {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        var settings = OperatingSchedule()
        let host = NSHostingView(rootView: OperatingHoursView(schedule: Binding(get: { settings }, set: { settings = $0 }), language: .simplifiedChinese))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let pickers = descendants(host).compactMap { $0 as? NSDatePicker }
        check(pickers.count == 4, "actual operating-hours view contains four native time editors")
        for picker in pickers {
            let name = picker.accessibilityLabel() ?? "time"
            window.makeFirstResponder(picker)
            check(window.firstResponder === picker, "time editor accepts explicit keyboard focus: \(name)")
            let inside = picker.convert(NSPoint(x: picker.bounds.midX, y: picker.bounds.midY), to: nil)
            if let event = NSEvent.mouseEvent(with: .mouseMoved, location: inside, modifierFlags: [], timestamp: 0,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                NSApplication.shared.sendEvent(event)
            }
            check(window.firstResponder === picker, "pointer inside preserves time editing: \(name)")
            if let event = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: -20, y: -20), modifierFlags: [], timestamp: 1,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0) {
                NSApplication.shared.sendEvent(event)
            }
            check(window.firstResponder !== picker, "pointer exit ends selected time component: \(name)")
        }
        let unrelated = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        host.addSubview(unrelated)
        window.makeFirstResponder(unrelated)
        let previous = window.firstResponder
        if let picker = pickers.first {
            (picker as? PointerTimePicker)?.finishPointerEditing()
        }
        check(window.firstResponder === previous, "time pointer exit never steals another control's keyboard focus")
        return failures == 0 ? 0 : 1
    }
}
