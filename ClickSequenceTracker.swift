import Foundation
import CoreGraphics

/// Tracks consecutive clicks so synthesized events carry the click count that
/// AppKit controls use for double-click and triple-click behavior.
struct ClickSequenceTracker {
    let interval: TimeInterval
    let movementThreshold: CGFloat

    private var lastClickTime: TimeInterval?
    private var lastClickLocation: CGPoint?
    private var lastClickWasRight = false
    private var clickCount: Int64 = 0

    init(interval: TimeInterval, movementThreshold: CGFloat) {
        self.interval = interval
        self.movementThreshold = movementThreshold
    }

    mutating func registerClick(
        at location: CGPoint,
        isRightClick: Bool,
        time: TimeInterval
    ) -> Int64 {
        let continuesSequence: Bool

        if let lastClickTime, let lastClickLocation {
            let elapsed = time - lastClickTime
            let distance = hypot(
                location.x - lastClickLocation.x,
                location.y - lastClickLocation.y
            )
            continuesSequence = elapsed >= 0
                && elapsed <= interval
                && distance <= movementThreshold
                && isRightClick == lastClickWasRight
        } else {
            continuesSequence = false
        }

        clickCount = continuesSequence ? min(clickCount + 1, 3) : 1
        lastClickTime = time
        lastClickLocation = location
        lastClickWasRight = isRightClick
        return clickCount
    }
}
