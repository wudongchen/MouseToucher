import AppKit
import IOKit

private func drainHIDIterator(_ iterator: io_iterator_t) {
    while true {
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return }
        IOObjectRelease(service)
    }
}

private func hidDeviceSetChanged(
    refCon: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    drainHIDIterator(iterator)
    guard let refCon else { return }
    let monitor = Unmanaged<DeviceReconnectMonitor>.fromOpaque(refCon).takeUnretainedValue()
    monitor.scheduleReconnect()
}

/// Re-registers the private multitouch device after a Bluetooth HID device
/// reconnects or macOS wakes. MultitouchSupport device handles do not remain
/// usable across either transition.
final class DeviceReconnectMonitor: NSObject {
    private let onReconnectNeeded: () -> Void
    private let reconnectDelay: TimeInterval
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pendingReconnect: DispatchWorkItem?
    private var notificationPort: IONotificationPortRef?
    private var runLoopSource: CFRunLoopSource?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0

    init(reconnectDelay: TimeInterval = 1.5, onReconnectNeeded: @escaping () -> Void) {
        self.reconnectDelay = reconnectDelay
        self.onReconnectNeeded = onReconnectNeeded
        super.init()
    }

    func start() {
        guard workspaceObservers.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        let wakeNotifications: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]

        workspaceObservers = wakeNotifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleReconnect()
            }
        }

        guard let port = IONotificationPortCreate(kIOMasterPortDefault) else { return }
        notificationPort = port

        if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        let refCon = Unmanaged.passUnretained(self).toOpaque()
        registerHIDNotification(
            port: port,
            name: kIOFirstMatchNotification,
            iterator: &matchedIterator,
            refCon: refCon
        )
        registerHIDNotification(
            port: port,
            name: kIOTerminatedNotification,
            iterator: &terminatedIterator,
            refCon: refCon
        )
    }

    func stop() {
        pendingReconnect?.cancel()
        pendingReconnect = nil

        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
            matchedIterator = 0
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
            terminatedIterator = 0
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }

    fileprivate func scheduleReconnect() {
        // HID services appear before MultitouchSupport publishes its replacement
        // device. Coalesce wake/HID events and wait briefly before rescanning.
        pendingReconnect?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onReconnectNeeded()
        }
        pendingReconnect = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay, execute: workItem)
    }

    private func registerHIDNotification(
        port: IONotificationPortRef,
        name: UnsafePointer<CChar>,
        iterator: UnsafeMutablePointer<io_iterator_t>,
        refCon: UnsafeMutableRawPointer
    ) {
        guard let matching = IOServiceMatching("IOHIDDevice") else { return }
        let result = IOServiceAddMatchingNotification(
            port,
            name,
            matching,
            hidDeviceSetChanged,
            refCon,
            iterator
        )
        if result == KERN_SUCCESS {
            drainHIDIterator(iterator.pointee)
        }
    }

    deinit {
        stop()
    }
}
