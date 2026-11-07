import AppKit
import Carbon

/// Active only while a break is visible; restores the app's prior presentation on every exit.
@MainActor
final class BreakInputGuard {
    private var previousOptions: NSApplication.PresentationOptions?
    private var monitor: Any?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var escape: (() -> Void)?
    private let signature: OSType = 0x52464252 // RFBR

    func start(escape: @escaping () -> Void) -> Bool {
        guard previousOptions == nil else { return hotKey != nil }
        self.escape = escape
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let guarder = Unmanaged<BreakInputGuard>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard id.signature == guarder.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                guarder.escape?()
                return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if installed == noErr {
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: signature, id: 1),
                                GetEventDispatcherTarget(), 0, &hotKey)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown && event.keyCode == UInt16(kVK_Escape) && !event.isARepeat { self?.escape?() }
            }
            return nil
        }
        previousOptions = NSApp.presentationOptions
        var options = NSApp.presentationOptions
        options.subtract([.autoHideDock, .autoHideMenuBar])
        options.formUnion([.hideDock, .hideMenuBar, .disableProcessSwitching])
        NSApp.presentationOptions = options
        return hotKey != nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let previousOptions { NSApp.presentationOptions = previousOptions }
        previousOptions = nil
        escape = nil
    }
}
