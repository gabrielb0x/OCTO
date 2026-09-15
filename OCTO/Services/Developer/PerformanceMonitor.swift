import Darwin
import Foundation
import Observation

/// Frame rate, memory footprint and CPU use of the app, sampled every second for the developer overlay.
@MainActor
@Observable
final class PerformanceMonitor {
    private(set) var framesPerSecond = 0
    private(set) var memoryFootprint: UInt64 = 0
    private(set) var cpuUsage: Double = 0

    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var elapsed: TimeInterval = 0

    func start() {
        guard ticker == nil else { return }
        frames = 0
        elapsed = 0
        let ticker = FrameTicker { [weak self] delta in
            guard let self else { return false }
            self.tick(delta)
            return true
        }
        self.ticker = ticker
        ticker.start()
    }

    func stop() {
        ticker?.stop()
        ticker = nil
    }

    private func tick(_ delta: TimeInterval) {
        frames += 1
        elapsed += delta
        guard elapsed >= 1 else { return }
        framesPerSecond = Int((Double(frames) / elapsed).rounded())
        frames = 0
        elapsed = 0
        memoryFootprint = Self.currentMemoryFootprint() ?? memoryFootprint
        cpuUsage = Self.currentCPUUsage() ?? cpuUsage
    }

    /// The memory iOS counts against the app, as shown in Xcode's memory gauge.
    nonisolated static func currentMemoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// CPU use of all the app's threads, where 100 is one full core.
    nonisolated static func currentCPUUsage() -> Double? {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threadList else { return nil }
        defer {
            let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), size)
        }
        var total = 0.0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), rebound, &count)
                }
            }
            guard result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 else { continue }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
        }
        return total
    }
}
