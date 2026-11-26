import RestFlowCore

func cleaningChecks() -> [(String, () -> Void)] {
    [
        ("cleaning requires one continuous three-second Esc hold followed by release", {
            var gesture = CleaningExitGesture()
            gesture.key(53, down: true, at: 10)
            gesture.advance(at: 12.99)
            expectFalse(gesture.waitingForRelease)
            gesture.advance(at: 13)
            expectEqual(gesture.progress, 1)
            expectEqual(gesture.waitingForRelease, true)
            expectFalse(gesture.shouldExit)
            gesture.key(53, down: false, at: 13.1)
            expectEqual(gesture.shouldExit, true)
        }),
        ("short Esc presses and autorepeat never accumulate hold time", {
            var gesture = CleaningExitGesture()
            for time in 0..<10 {
                gesture.key(53, down: true, at: Double(time))
                gesture.key(53, down: false, at: Double(time) + 0.2)
            }
            expectEqual(gesture.progress, 0)
            expectFalse(gesture.shouldExit)
            gesture.key(53, down: true, at: 10)
            gesture.key(53, down: true, at: 11)
            gesture.key(53, down: true, at: 12)
            gesture.advance(at: 13)
            expectEqual(gesture.waitingForRelease, true)
        }),
        ("other keys and modifiers reset the cleaning exit gesture", {
            var gesture = CleaningExitGesture()
            gesture.key(53, down: true, at: 0)
            gesture.key(0, down: true, at: 2)
            gesture.advance(at: 10)
            expectFalse(gesture.waitingForRelease)
            gesture.key(0, down: false, at: 10)
            gesture.setModifiers(1, at: 12)
            gesture.advance(at: 20)
            expectEqual(gesture.progress, 0)
            gesture.setModifiers(0, at: 20)
            gesture.advance(at: 23)
            expectEqual(gesture.waitingForRelease, true)
        }),
        ("cleaning exit waits for every held key, modifier and mouse button", {
            var gesture = CleaningExitGesture()
            gesture.key(53, down: true, at: 0)
            gesture.advance(at: 3)
            gesture.key(1, down: true, at: 3.01)
            gesture.button(0, down: true, at: 3.02)
            gesture.setModifiers(1, at: 3.03)
            gesture.key(53, down: false, at: 3.1)
            gesture.key(1, down: false, at: 3.2)
            gesture.button(0, down: false, at: 3.3)
            expectFalse(gesture.shouldExit)
            gesture.setModifiers(0, at: 3.4)
            expectEqual(gesture.shouldExit, true)
        }),
        ("physical state reconciliation handles held keys and lost releases", {
            var gesture = CleaningExitGesture()
            gesture.reconcile(keys: [0, 53], buttons: [1], modifiers: 0, at: 0)
            gesture.advance(at: 20)
            expectEqual(gesture.progress, 0)
            gesture.reconcile(keys: [53], buttons: [], modifiers: 0, at: 20)
            gesture.advance(at: 23)
            gesture.reconcile(keys: [], buttons: [], modifiers: 0, at: 24)
            expectEqual(gesture.shouldExit, true)
        })
    ]
}
