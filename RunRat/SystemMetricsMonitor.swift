import Foundation
import Darwin.Mach
import IOKit
import IOKit.ps
import CoreWLAN

struct CPUStats {
    let totalPercent: Double?
    let userPercent: Double?
    let systemPercent: Double?
    let idlePercent: Double?
    let logicalCoreCount: Int
}

struct GPUStats {
    let maximumPercent: Double?
}

struct MemoryStats {
    let usedBytes: UInt64?
    let totalBytes: UInt64
    let wiredBytes: UInt64?
    let compressedBytes: UInt64?
    let appMemoryBytes: UInt64?
    let cachedBytes: UInt64?
    let swapUsedBytes: UInt64?
    let pressurePercent: Double?
}

struct StorageStats {
    let usedBytes: UInt64?
    let totalBytes: UInt64?
    let availableBytes: UInt64?
}

struct BatteryStats {
    let percentage: Double?
    let isCharging: Bool?
    let cycleCount: Int?
    let maximumCapacityPercent: Double?
}

struct NetworkStats {
    let displayName: String?
    let localAddress: String?
    let uploadBytesPerSecond: UInt64?
    let downloadBytesPerSecond: UInt64?
}

struct SystemSnapshot {
    let cpu: CPUStats
    let gpu: GPUStats
    let memory: MemoryStats
    let storage: StorageStats
    let battery: BatteryStats
    let network: NetworkStats
    let timestamp: Date
}

final class SystemMetricsMonitor {
    var onUpdate: ((SystemSnapshot) -> Void)?

    private let sampleQueue = DispatchQueue(label: "com.runrat.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0
    private var previousNetworkSample: [String: (received: UInt64, sent: UInt64)] = [:]
    private var previousNetworkDate: Date?

    deinit {
        stop()
    }

    func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.sample()
        }

        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil

        if let previousCPUInfo {
            let size = vm_size_t(previousCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCPUInfo), size)
            self.previousCPUInfo = nil
            previousCPUInfoCount = 0
        }
    }

    private func sample() {
        let snapshot = SystemSnapshot(
            cpu: sampleCPUStats(),
            gpu: sampleGPUStats(),
            memory: sampleMemoryStats(),
            storage: sampleStorageStats(),
            battery: sampleBatteryStats(),
            network: sampleNetworkStats(),
            timestamp: Date()
        )

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snapshot)
        }
    }

    private func sampleCPUStats() -> CPUStats {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return CPUStats(
                totalPercent: nil,
                userPercent: nil,
                systemPercent: nil,
                idlePercent: nil,
                logicalCoreCount: ProcessInfo.processInfo.activeProcessorCount
            )
        }

        defer {
            if let previousCPUInfo {
                let size = vm_size_t(previousCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCPUInfo), size)
            }

            previousCPUInfo = cpuInfo
            previousCPUInfoCount = cpuInfoCount
        }

        guard let previousCPUInfo else {
            return CPUStats(
                totalPercent: nil,
                userPercent: nil,
                systemPercent: nil,
                idlePercent: nil,
                logicalCoreCount: Int(cpuCount)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var userTicks: UInt64 = 0
        var systemTicks: UInt64 = 0
        var idleTicks: UInt64 = 0
        var niceTicks: UInt64 = 0

        for cpu in 0 ..< Int(cpuCount) {
            let offset = cpu * stride

            userTicks += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)] - previousCPUInfo[offset + Int(CPU_STATE_USER)])
            systemTicks += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)] - previousCPUInfo[offset + Int(CPU_STATE_SYSTEM)])
            idleTicks += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)] - previousCPUInfo[offset + Int(CPU_STATE_IDLE)])
            niceTicks += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)] - previousCPUInfo[offset + Int(CPU_STATE_NICE)])
        }

        let totalTicks = userTicks + systemTicks + idleTicks + niceTicks
        guard totalTicks > 0 else {
            return CPUStats(
                totalPercent: nil,
                userPercent: nil,
                systemPercent: nil,
                idlePercent: nil,
                logicalCoreCount: Int(cpuCount)
            )
        }

        let userPercent = (Double(userTicks + niceTicks) / Double(totalTicks)) * 100
        let systemPercent = (Double(systemTicks) / Double(totalTicks)) * 100
        let idlePercent = (Double(idleTicks) / Double(totalTicks)) * 100

        return CPUStats(
            totalPercent: min(max(userPercent + systemPercent, 0), 100),
            userPercent: min(max(userPercent, 0), 100),
            systemPercent: min(max(systemPercent, 0), 100),
            idlePercent: min(max(idlePercent, 0), 100),
            logicalCoreCount: Int(cpuCount)
        )
    }

    private func sampleMemoryStats() -> MemoryStats {
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        var usedBytes: UInt64?
        var wiredBytes: UInt64?
        var compressedBytes: UInt64?
        var appMemoryBytes: UInt64?
        var cachedBytes: UInt64?
        var swapUsedBytes: UInt64?
        var pressurePercent: Double?

        if result == KERN_SUCCESS {
            let pageSizeBytes = UInt64(pageSize)
            let freeBytes = UInt64(vmStats.free_count) * pageSizeBytes
            let activeAndInactiveBytes = UInt64(vmStats.active_count + vmStats.inactive_count) * pageSizeBytes
            let wired = UInt64(vmStats.wire_count) * pageSizeBytes
            let compressed = UInt64(vmStats.compressor_page_count) * pageSizeBytes
            let cached = UInt64(vmStats.external_page_count) * pageSizeBytes
            let usedEstimate = totalBytes > (freeBytes + cached) ? totalBytes - freeBytes - cached : 0
            let appEstimate = activeAndInactiveBytes > cached ? activeAndInactiveBytes - cached : 0

            usedBytes = usedEstimate
            wiredBytes = wired
            compressedBytes = compressed
            appMemoryBytes = appEstimate
            cachedBytes = cached
            swapUsedBytes = UInt64(vmStats.swapped_count) * pageSizeBytes

            let pressureBase = Double(wired + compressed)
            pressurePercent = totalBytes > 0 ? min(max((pressureBase / Double(totalBytes)) * 100, 0), 100) : nil
        }

        return MemoryStats(
            usedBytes: usedBytes,
            totalBytes: totalBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            appMemoryBytes: appMemoryBytes,
            cachedBytes: cachedBytes,
            swapUsedBytes: swapUsedBytes,
            pressurePercent: pressurePercent
        )
    }

    private func sampleGPUStats() -> GPUStats {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else {
            return GPUStats(maximumPercent: nil)
        }

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return GPUStats(maximumPercent: nil)
        }

        defer { IOObjectRelease(iterator) }

        var maximumPercent: Double?

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var unmanagedProperties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any],
                  let performance = properties["PerformanceStatistics"] as? [String: Any]
            else {
                continue
            }

            let candidateKeys = [
                "Device Utilization %",
                "GPU Core Utilization",
                "GPU Busy",
            ]

            for key in candidateKeys {
                guard let rawValue = performance[key] else { continue }

                let value: Double?
                if let number = rawValue as? NSNumber {
                    value = number.doubleValue
                } else if let string = rawValue as? String {
                    value = Double(string)
                } else {
                    value = nil
                }

                guard let value else { continue }

                let normalised: Double
                if value > 1000 {
                    normalised = value / 100.0
                } else {
                    normalised = value
                }

                maximumPercent = max(maximumPercent ?? 0, min(max(normalised, 0), 100))
            }
        }

        return GPUStats(maximumPercent: maximumPercent)
    }

    private func sampleStorageStats() -> StorageStats {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let totalBytes = (attributes[.systemSize] as? NSNumber)?.uint64Value
            let freeBytes = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value
            let usedBytes: UInt64? = {
                guard let totalBytes, let freeBytes, totalBytes >= freeBytes else { return nil }
                return totalBytes - freeBytes
            }()

            return StorageStats(usedBytes: usedBytes, totalBytes: totalBytes, availableBytes: freeBytes)
        } catch {
            return StorageStats(usedBytes: nil, totalBytes: nil, availableBytes: nil)
        }
    }

    private func sampleBatteryStats() -> BatteryStats {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
            return BatteryStats(percentage: nil, isCharging: nil, cycleCount: nil, maximumCapacityPercent: nil)
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Double
        let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Double
        let percentage: Double? = {
            guard let currentCapacity, let maxCapacity, maxCapacity > 0 else { return nil }
            return (currentCapacity / maxCapacity) * 100
        }()

        let powerSourceState = description[kIOPSPowerSourceStateKey as String] as? String
        let isCharging = powerSourceState.map { $0 == kIOPSACPowerValue }
        let cycleCount = value(in: description, keys: ["Cycle Count", "CycleCount"]) as? Int
        let designCapacity = value(in: description, keys: ["DesignCapacity", "Design Capacity"]) as? Double
        let maximumCapacityPercent: Double? = {
            guard let maxCapacity, let designCapacity, designCapacity > 0 else { return nil }
            return (maxCapacity / designCapacity) * 100
        }()

        return BatteryStats(
            percentage: percentage,
            isCharging: isCharging,
            cycleCount: cycleCount,
            maximumCapacityPercent: maximumCapacityPercent
        )
    }

    private func sampleNetworkStats() -> NetworkStats {
        let now = Date()
        let counters = readNetworkInterfaceCounters()
        let interfaceName = preferredInterfaceName()

        defer {
            previousNetworkSample = counters
            previousNetworkDate = now
        }

        guard let previousDate = previousNetworkDate else {
            return NetworkStats(displayName: displayName(for: interfaceName), localAddress: localAddress(for: interfaceName), uploadBytesPerSecond: nil, downloadBytesPerSecond: nil)
        }

        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0 else {
            return NetworkStats(displayName: displayName(for: interfaceName), localAddress: localAddress(for: interfaceName), uploadBytesPerSecond: nil, downloadBytesPerSecond: nil)
        }

        let preferredCounters = interfaceName.flatMap { counters[$0] } ?? counters.first?.value
        let previousCounters = interfaceName.flatMap { previousNetworkSample[$0] } ?? previousNetworkSample.first?.value

        guard let preferredCounters, let previousCounters else {
            return NetworkStats(displayName: displayName(for: interfaceName), localAddress: localAddress(for: interfaceName), uploadBytesPerSecond: nil, downloadBytesPerSecond: nil)
        }

        let receivedDelta = preferredCounters.received >= previousCounters.received
            ? preferredCounters.received - previousCounters.received
            : 0
        let sentDelta = preferredCounters.sent >= previousCounters.sent
            ? preferredCounters.sent - previousCounters.sent
            : 0

        return NetworkStats(
            displayName: displayName(for: interfaceName),
            localAddress: localAddress(for: interfaceName),
            uploadBytesPerSecond: UInt64(Double(sentDelta) / elapsed),
            downloadBytesPerSecond: UInt64(Double(receivedDelta) / elapsed)
        )
    }

    private func preferredInterfaceName() -> String? {
        if let interfaceName = CWWiFiClient.shared().interface()?.interfaceName {
            return interfaceName
        }

        return previousNetworkSample.keys.sorted().first
    }

    private func readNetworkInterfaceCounters() -> [String: (received: UInt64, sent: UInt64)] {
        var counters: [String: (received: UInt64, sent: UInt64)] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return counters
        }

        defer {
            freeifaddrs(pointer)
        }

        var current = first
        while true {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let name = String(cString: interface.ifa_name)

            if (flags & IFF_UP) != 0,
               (flags & IFF_LOOPBACK) == 0,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                counters[name] = (received: UInt64(data.ifi_ibytes), sent: UInt64(data.ifi_obytes))
            }

            guard let next = interface.ifa_next else { break }
            current = next
        }

        return counters
    }

    private func displayName(for interfaceName: String?) -> String? {
        guard let interfaceName else { return nil }

        if let wifiInterface = CWWiFiClient.shared().interface(),
           wifiInterface.interfaceName == interfaceName {
            return "Wi-Fi"
        }

        switch interfaceName {
        case "en0", "en1":
            return "Network"
        default:
            return interfaceName.uppercased()
        }
    }

    private func localAddress(for interfaceName: String?) -> String? {
        guard let interfaceName else { return nil }

        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return nil
        }

        defer {
            freeifaddrs(pointer)
        }

        var current = first
        while true {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)

            if name == interfaceName,
               let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                if result == 0 {
                    return String(cString: hostBuffer)
                }
            }

            guard let next = interface.ifa_next else { break }
            current = next
        }

        return nil
    }

    private func value(in description: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = description[key] {
                return value
            }
        }

        return nil
    }
}
