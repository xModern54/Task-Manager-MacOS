import Darwin
import Foundation

struct SysctlCPUInfoProvider: SystemCPUInfoProviding {
    func processorName() -> String? {
        stringValue(for: "machdep.cpu.brand_string")
            ?? appleSiliconFallback()
    }

    private func stringValue(for key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func appleSiliconFallback() -> String? {
        var isArm64 = 0
        var size = MemoryLayout<Int>.size
        let result = sysctlbyname("hw.optional.arm64", &isArm64, &size, nil, 0)
        guard result == 0, isArm64 == 1 else { return nil }

        return "Apple Silicon"
    }
}
