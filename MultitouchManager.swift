import Foundation
import CoreGraphics
import AppKit

// Swift wrapper for Multitouch framework
class MultitouchManager {
    private var devices: [MTDeviceRef] = []
    private var retainedDeviceList: NSArray?
    private var tapDetector = TapDetector(tapTimeThreshold: 0.25, tapMovementThreshold: 5.0)
    private var isEnabled = true
    private var activeTouch: Int32 = -1
    private var touchStartX: Float = 0.0
    private var touchStartY: Float = 0.0
    private var isSuppressingUntilRelease = false
    private var surfaceMovementThreshold: Float = 0.04  // About 2 mm on a Magic Mouse

    /// Taps with a normalized x above this are right clicks. Configurable from the menu bar.
    var rightClickThreshold: Float = Preferences.rightClickThreshold {
        didSet {
            rightClickThreshold = Preferences.clamp(rightClickThreshold)
        }
    }

    fileprivate static var sharedInstance: MultitouchManager?

    var onClickSynthesized: ((CGPoint, Bool) -> Void)?
    var onConnectionStatusChanged: ((Bool) -> Void)?

    init() {
        MultitouchManager.sharedInstance = self
    }

    @discardableResult
    func start() -> Bool {
        guard let deviceList = MTDeviceCreateList() else {
            onConnectionStatusChanged?(false)
            return false
        }

        let deviceArray = deviceList.takeRetainedValue() as NSArray
        retainedDeviceList = deviceArray
        let count = CFArrayGetCount(deviceArray)

        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(deviceArray, i), to: MTDeviceRef.self)

            // Both Magic Mouse and an external Magic Trackpad report as external.
            // Their sensor aspect ratios differ: a mouse is portrait-shaped and a
            // trackpad is landscape-shaped. Filter by both properties so an
            // external trackpad does not generate duplicate synthetic clicks.
            var sensorWidth: Int32 = 0
            var sensorHeight: Int32 = 0
            let readDimensions = MTDeviceGetSensorSurfaceDimensions(device, &sensorWidth, &sensorHeight)
            let isMagicMouse = !MTDeviceIsBuiltIn(device)
                && readDimensions == 0
                && sensorHeight > sensorWidth

            if isMagicMouse {
                devices.append(device)
                MTRegisterContactFrameCallback(device, touchCallback)
                MTDeviceStart(device, 0)
            }
        }

        let isConnected = !devices.isEmpty
        onConnectionStatusChanged?(isConnected)
        return isConnected
    }

    @discardableResult
    func restart() -> Bool {
        stop()
        return start()
    }

    func stop() {
        for device in devices {
            MTUnregisterContactFrameCallback(device, touchCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
        retainedDeviceList = nil
        resetGestureState()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func processTouches(_ touches: UnsafeMutablePointer<MTTouch>, numTouches: Int, timestamp: Double) {
        guard isEnabled else { return }

        // The callback comes from a private framework; don't trust a negative count.
        guard numTouches >= 0 else { return }

        if numTouches == 0 {
            defer {
                activeTouch = -1
                touchStartX = 0.0
                touchStartY = 0.0
                isSuppressingUntilRelease = false
            }

            // Once a gesture has moved enough to be a swipe/scroll, never start
            // a fresh tap from a later frame of that same gesture. Wait until
            // every finger has left the surface first.
            if isSuppressingUntilRelease {
                tapDetector.reset()
                return
            }

            if activeTouch != -1 {
                // Get cursor position directly from CGEvent (already in correct coordinate space)
                let cgLocation = CGEvent(source: nil)?.location ?? CGPoint.zero

                if let tapLocation = tapDetector.touchEnded(at: cgLocation) {
                    let isRightClick = touchStartX > rightClickThreshold
                    onClickSynthesized?(tapLocation, isRightClick)
                }
            }
            return
        }

        guard !isSuppressingUntilRelease else { return }

        if numTouches == 1 {
            let touch = touches[0]
            // Get cursor position directly from CGEvent (already in correct coordinate space)
            let cgLocation = CGEvent(source: nil)?.location ?? CGPoint.zero

            if activeTouch == -1 {
                // Only a real contact frame may begin a tap. An out-of-range
                // frame (state 7) can arrive just before release and must not
                // create a new tap candidate.
                if touch.state == 3 || touch.state == 4 {
                    // New touch started - record starting position on surface
                    activeTouch = touch.identifier
                    touchStartX = touch.normalized.position.x
                    touchStartY = touch.normalized.position.y
                    tapDetector.touchBegan(at: cgLocation)
                }
            } else if activeTouch == touch.identifier {
                if touch.state == 3 || touch.state == 4 {
                    // Same touch continuing - check if finger moved too much on surface (scrolling)
                    let deltaX = abs(touch.normalized.position.x - touchStartX)
                    let deltaY = abs(touch.normalized.position.y - touchStartY)
                    let surfaceMovement = max(deltaX, deltaY)

                    if surfaceMovement > surfaceMovementThreshold {
                        // Finger moved too much on surface - likely scrolling, cancel tap
                        suppressCurrentGestureUntilRelease()
                    } else {
                        // Check cursor movement too
                        let moved = tapDetector.touchMoved(to: cgLocation)
                        if moved {
                            suppressCurrentGestureUntilRelease()
                        }
                    }
                }
            }
        } else if numTouches > 1 {
            suppressCurrentGestureUntilRelease()
        }
    }

    private func suppressCurrentGestureUntilRelease() {
        tapDetector.reset()
        activeTouch = -1
        touchStartX = 0.0
        touchStartY = 0.0
        isSuppressingUntilRelease = true
    }

    private func resetGestureState() {
        tapDetector.reset()
        activeTouch = -1
        touchStartX = 0.0
        touchStartY = 0.0
        isSuppressingUntilRelease = false
    }

    deinit {
        stop()
    }
}

private func touchCallback(device: Int32, touches: UnsafeMutablePointer<MTTouch>?, numTouches: Int32, timestamp: Double, frame: Int32) -> Int32 {
    if let manager = MultitouchManager.sharedInstance, let touches = touches {
        manager.processTouches(touches, numTouches: Int(numTouches), timestamp: timestamp)
    }
    return 0
}
