import Foundation
import Darwin
import Dispatch

/// The app's physical memory footprint (the number Activity Monitor shows as "Memory").
public enum Memory {
    public static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// Hands freed heap memory back to macOS. The allocator otherwise keeps it for reuse,
    /// so a big capture or edit would leave the footprint high for hours. Runs shortly after
    /// the work so autoreleased objects are gone first.
    public static func trimSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    /// Releases a window's contents when it closes and forgets the controller's reference,
    /// so closed windows don't keep their drawing buffers.
    public static func releaseOnClose(_ window: NSObject, _ onClose: @escaping () -> Void) {
        final class Token { var value: NSObjectProtocol? }
        let token = Token()
        token.value = NotificationCenter.default.addObserver(forName: Notification.Name("NSWindowWillCloseNotification"),
                                                             object: window, queue: .main) { _ in
            if let observer = token.value { NotificationCenter.default.removeObserver(observer) }
            onClose()
            trimSoon()
        }
    }
}
