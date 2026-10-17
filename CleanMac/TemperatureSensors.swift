import Foundation
import Darwin

nonisolated struct TemperatureReading: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let celsius: Double
}

// Apple Silicon publishes temperature HID events rather than legacy IOHWSensor values.
// Resolve these non-public symbols at runtime so unsupported OS releases fail gracefully.
@MainActor
final class TemperatureSensors {
    static let shared = TemperatureSensors()
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias Match = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias Property = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias Event = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias Value = @convention(c) (CFTypeRef, Int32) -> Double
    private let handle: UnsafeMutableRawPointer?
    private let client: CFTypeRef?
    private let services: Services?
    private let property: Property?
    private let event: Event?
    private let value: Value?

    private init() {
        let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
        handle = library
        func resolve<T>(_ name: String, as type: T.Type) -> T? {
            guard let library, let address = dlsym(library, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        let create = resolve("IOHIDEventSystemClientCreate", as: Create.self)
        let match = resolve("IOHIDEventSystemClientSetMatching", as: Match.self)
        services = resolve("IOHIDEventSystemClientCopyServices", as: Services.self)
        property = resolve("IOHIDServiceClientCopyProperty", as: Property.self)
        event = resolve("IOHIDServiceClientCopyEvent", as: Event.self)
        value = resolve("IOHIDEventGetFloatValue", as: Value.self)
        if let match, let created = create?(kCFAllocatorDefault)?.takeRetainedValue() {
            client = created
            match(created, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        } else { client = nil }
    }
    func read() -> [TemperatureReading] {
        guard let client, let services, let property, let event, let value,
              let list = services(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        var readings: [TemperatureReading] = []
        for service in list {
            guard let name = property(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let sample = event(service, 15, 0, 0)?.takeRetainedValue() else { continue }
            readings.append(TemperatureReading(name: name, celsius: value(sample, 15 << 16)))
        }
        return Self.normalized(readings)
    }
    nonisolated static func normalized(_ values: [TemperatureReading]) -> [TemperatureReading] {
        // Some drivers expose a sensor more than once. Keep its highest valid sample.
        var sensors: [String: Double] = [:]
        for value in values where value.celsius.isFinite && value.celsius > 0 && value.celsius < 150 {
            sensors[value.name] = max(sensors[value.name] ?? value.celsius, value.celsius)
        }
        return sensors.map { TemperatureReading(name: $0.key, celsius: $0.value) }.sorted {
            $0.celsius == $1.celsius ? $0.name < $1.name : $0.celsius > $1.celsius
        }
    }
}
