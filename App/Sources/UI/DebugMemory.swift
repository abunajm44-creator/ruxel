import Foundation
import MachO

// DebugMemory — current process memory footprint for the debug overlay.
// What: reads task VM info and returns resident megabytes.
// Inputs-outputs: no inputs; Double megabytes out.
// Threading: pure function; safe from any thread.
// VERIFY: task_info / TASK_VM_INFO / task_vm_info_data_t field names on iOS 16.
enum DebugMemory {
    static func currentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}
