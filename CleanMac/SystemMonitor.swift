import Foundation
import Combine
import Darwin
import IOKit
import IOKit.ps

nonisolated struct NetworkCounters: Equatable {
    var received: UInt64
    var sent: UInt64
    static func rate(current: UInt64, previous: UInt64, elapsed: Double) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    @Published var cpu: [Double] = []
    @Published var memory: [Double] = []
    @Published var download: [Double] = []
    @Published var upload: [Double] = []
    @Published var memoryUsed: UInt64 = 0
    @Published var compressed: UInt64 = 0
    @Published var swap: UInt64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var battery: Double?
    @Published var power = "读取中"
    @Published var temperatures: [TemperatureReading] = []
    @Published var temperature: Double?
    @Published var gpu: Double?
    @Published var thermal = "读取中"
    @Published var uptime: TimeInterval = 0
    @Published var load: [Double] = []
    @Published var networkInterfaces = "未连接"
    @Published var sampleDate: Date?
    @Published var cpuAvailable = false
    @Published var memoryAvailable = false
    @Published var networkAvailable = false
    @Published var diskAvailable = false
    private var ticks: [UInt64] = []
    private var lastNetwork: [String: NetworkCounters] = [:]
    private var lastTime: TimeInterval?
    private var timer: AnyCancellable?
    private var sampleNumber = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.sample() }
    }
    func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        sampleCPU(); sampleMemory(); sampleNetwork(now: now)
        uptime = now
        var averages = [Double](repeating: 0, count: 3)
        if getloadavg(&averages, 3) == 3 { load = averages }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "正常"
        case .fair: thermal = "温热"
        case .serious: thermal = "较高 · 系统降频"
        case .critical: thermal = "过热 · 系统保护"
        @unknown default: thermal = "未知"
        }
        // Slower sensors and filesystem metadata need not be queried every second.
        if sampleNumber % 5 == 0 {
            if let values = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
                diskTotal = (values[.systemSize] as? NSNumber)?.int64Value ?? 0
                diskFree = (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                diskAvailable = diskTotal > 0
            } else { diskAvailable = false }
            sampleBattery(); sampleSensors()
        }
        sampleNumber += 1
        sampleDate = Date()
    }
    private func append(_ value: Double, to history: inout [Double]) { history.append(value); history = Array(history.suffix(60)) }
    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        guard result == KERN_SUCCESS else { cpuAvailable = false; return }
        let current = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
        if ticks.count == 4 {
            let delta = zip(current, ticks).map { ($0 &- $1) & 0xffffffff }
            let total = delta.reduce(0, +)
            append(total == 0 ? 0 : 100 * Double(total - delta[2]) / Double(total), to: &cpu)
            cpuAvailable = true
        }
        ticks = current
    }
    private func sampleMemory() {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        if result == KERN_SUCCESS {
            // App memory includes inactive anonymous pages, excluding purgeable pages.
            let appPages = UInt64(vm.internal_page_count) > UInt64(vm.purgeable_count) ? UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count) : 0
            compressed = UInt64(vm.compressor_page_count) * UInt64(vm_kernel_page_size)
            memoryUsed = min(memoryTotal, (appPages + UInt64(vm.wire_count)) * UInt64(vm_kernel_page_size) + compressed)
            append(100 * Double(memoryUsed) / Double(max(1, memoryTotal)), to: &memory)
            memoryAvailable = true
        } else { memoryAvailable = false }
        var usage = xsw_usage(); var length = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &length, nil, 0) == 0 { swap = usage.xsu_used }
    }
    private func sampleNetwork(now: TimeInterval) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { networkAvailable = false; lastTime = nil; return }
        defer { freeifaddrs(list) }
        var counters: [String: NetworkCounters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            let interface = p.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
               interface.ifa_flags & UInt32(IFF_UP) != 0, interface.ifa_flags & UInt32(IFF_RUNNING) != 0, interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let data = interface.ifa_data {
                let name = String(cString: interface.ifa_name)
                // Physical Ethernet/Wi-Fi interfaces only; VPN/bridge virtual counters would double count.
                if name.hasPrefix("en") {
                    let value = data.assumingMemoryBound(to: if_data.self).pointee
                    counters[name] = NetworkCounters(received: UInt64(value.ifi_ibytes), sent: UInt64(value.ifi_obytes))
                }
            }
            cursor = interface.ifa_next
        }
        if let before = lastTime, now - before < 5 {
            var down = 0.0; var up = 0.0
            for (name, current) in counters {
                guard let previous = lastNetwork[name] else { continue }
                down += NetworkCounters.rate(current: current.received, previous: previous.received, elapsed: now - before)
                up += NetworkCounters.rate(current: current.sent, previous: previous.sent, elapsed: now - before)
            }
            append(down, to: &download); append(up, to: &upload)
            networkAvailable = true
        } else { networkAvailable = false }
        networkInterfaces = counters.isEmpty ? "未连接" : counters.keys.sorted().joined(separator: "、")
        lastNetwork = counters; lastTime = now
    }
    private func sampleBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { battery = nil; power = "无法读取电源"; return }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            battery = min(100, max(0, 100 * Double(current) / Double(maximum)))
            power = info[kIOPSIsChargingKey] as? Bool == true ? "正在充电" : (info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue ? "电源适配器" : "电池供电")
            return
        }
        battery = nil; power = "无内置电池 / 外接电源"
    }
    private func sampleSensors() {
        temperatures = TemperatureSensors.shared.read()
        temperature = temperatures.first?.celsius
        gpu = nil
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHWSensor"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var values: [Double] = []
            while true {
                let service = IOIteratorNext(iterator); if service == 0 { break }
                defer { IOObjectRelease(service) }
                let type = IORegistryEntryCreateCFProperty(service, "type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                if type == "temperature", let value = IORegistryEntryCreateCFProperty(service, "current-value" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                    let degrees = value.doubleValue / 65536
                    if degrees > 0 && degrees < 130 { values.append(degrees) }
                }
            }
            if temperature == nil {
                temperature = values.max()
                temperatures = values.enumerated().map { TemperatureReading(name: "IOHWSensor \($0.offset + 1)", celsius: $0.element) }
            }
        }
        var accelerators: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS {
            defer { IOObjectRelease(accelerators) }
            while true {
                let service = IOIteratorNext(accelerators); if service == 0 { break }
                defer { IOObjectRelease(service) }
                if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                   let value = stats["Device Utilization %"] as? NSNumber, (0...100).contains(value.doubleValue) { gpu = max(gpu ?? 0, value.doubleValue) }
            }
        }
    }
}
