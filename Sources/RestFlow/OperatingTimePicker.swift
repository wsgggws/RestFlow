import AppKit
import SwiftUI

/// A native segmented time editor that finishes its own edit when the pointer leaves.
struct OperatingTimePicker: View {
    @Binding var selection: Date
    let title: String
    @StateObject private var pointer = TimePickerPointer()

    var body: some View {
        NativeTimePicker(selection: $selection, title: title, pointer: pointer)
            .onHover { pointer.insideChanged($0) }
    }
}

private final class TimePickerPointer: ObservableObject {
    weak var picker: PointerTimePicker?
    func insideChanged(_ inside: Bool) {
        if !inside { picker?.finishPointerEditing() }
    }
}

private struct NativeTimePicker: NSViewRepresentable {
    @Binding var selection: Date
    let title: String
    let pointer: TimePickerPointer

    func makeNSView(context: Context) -> PointerTimePicker {
        let picker = PointerTimePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        picker.isBezeled = true
        picker.drawsBackground = true
        picker.isContinuous = true
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        pointer.picker = picker
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return picker
    }

    func updateNSView(_ picker: PointerTimePicker, context: Context) {
        context.coordinator.selection = $selection
        if picker.dateValue != selection { picker.dateValue = selection }
        picker.setAccessibilityLabel(title)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    final class Coordinator: NSObject {
        var selection: Binding<Date>
        init(selection: Binding<Date>) { self.selection = selection }
        @objc func changed(_ sender: NSDatePicker) { selection.wrappedValue = sender.dateValue }
    }
}

final class PointerTimePicker: NSDatePicker {
    private var pointerMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
        guard window != nil else { return }
        // Local pointer events also finish edits on blank-area clicks and scrolling,
        // including when AppKit coalesces the hover exit during a focus transition.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self, let window = self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if event.window !== window || !self.bounds.contains(point) { self.finishPointerEditing() }
            return event
        }
    }

    deinit { if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) } }

    func finishPointerEditing() {
        guard let window else { return }
        let responder = window.firstResponder
        let ownsEditor = (responder as? NSTextView)?.delegate as? NSDatePicker === self
        if responder === self || ownsEditor { window.makeFirstResponder(nil) }
    }
}
