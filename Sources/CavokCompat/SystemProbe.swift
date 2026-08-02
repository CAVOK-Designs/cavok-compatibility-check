import Foundation
import Metal

/// One line of the report. `status` drives the colour dot; `detail` is the
/// value a tester will actually paste back to us.
struct ProbeResult: Identifiable, Sendable {
    enum Status: String, Sendable {
        case pass = "PASS"
        case fail = "FAIL"
        case info = "INFO"
        case warn = "WARN"
    }

    let id = UUID()
    let name: String
    let status: Status
    let detail: String
}

/// Everything we can learn about the machine WITHOUT running MLX. Cheap,
/// synchronous, and never fails — so a tester whose GPU work crashes still
/// sends back a report that tells us which machine crashed.
enum SystemProbe {

    static func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func sysctlInt(_ key: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// macOS version as the OS itself reports it. This is the field the whole
    /// exercise exists to collect.
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var osBuild: String {
        sysctlString("kern.osversion") ?? "unknown"
    }

    /// True when this process is running natively on Apple Silicon. Rosetta
    /// would report x86_64 here, which for CAVOK is a hard no — MLX needs Metal
    /// on Apple Silicon.
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return sysctlInt("sysctl.proc_translated") != 1
        #else
        return false
        #endif
    }

    static var chip: String {
        sysctlString("machdep.cpu.brand_string") ?? "unknown"
    }

    static var memoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }

    static var freeDiskGB: Double? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Double(capacity) / 1_073_741_824.0
    }

    /// Collects the no-GPU-work checks.
    static func run() -> [ProbeResult] {
        var out: [ProbeResult] = []

        // The floor is 15.0, not 14.0: the Textual markdown renderer that draws
        // every answer declares .macOS(.v15), and ALL eight of its released
        // versions do — there is no older tag to fall back to. Reaching 14 would
        // mean replacing the renderer, which changes how every answer looks.
        let v = ProcessInfo.processInfo.operatingSystemVersion
        out.append(ProbeResult(
            name: "macOS version",
            status: v.majorVersion >= 15 ? .pass : .warn,
            detail: "\(osVersion) (build \(osBuild))"
                + (v.majorVersion < 15
                   ? " — below the 15.0 floor, but the GPU results below are still useful"
                   : "")
        ))

        out.append(ProbeResult(
            name: "Apple Silicon",
            status: isAppleSilicon ? .pass : .fail,
            detail: isAppleSilicon ? chip : "\(chip) — Intel/Rosetta, CAVOK requires Apple Silicon"
        ))

        let ram = memoryGB
        out.append(ProbeResult(
            name: "Memory",
            status: ram >= 8 ? .pass : .warn,
            detail: String(format: "%.0f GB", ram)
                + (ram >= 16 ? "" : ram >= 8 ? " (8 GB is CAVOK's design target)" : " — below 8 GB")
        ))

        if let disk = freeDiskGB {
            // ~2.5 GB model + index headroom.
            out.append(ProbeResult(
                name: "Free disk",
                status: disk >= 6 ? .pass : .warn,
                detail: String(format: "%.0f GB free", disk)
                    + (disk >= 6 ? "" : " — the study model needs ~2.5 GB")
            ))
        }

        if let device = MTLCreateSystemDefaultDevice() {
            let workingSet = Double(device.recommendedMaxWorkingSetSize) / 1_073_741_824.0
            out.append(ProbeResult(
                name: "Metal GPU",
                status: .pass,
                detail: String(format: "%@ — %.1f GB working set", device.name, workingSet)
            ))
        } else {
            out.append(ProbeResult(
                name: "Metal GPU",
                status: .fail,
                detail: "no Metal device — CAVOK cannot run"
            ))
        }

        out.append(contentsOf: foundationModelsProbe())
        return out
    }

    /// The framework that currently pins CAVOK to macOS 26. Compiled against a
    /// 14.0 deployment target, so this MUST be availability-guarded — and that
    /// guard is exactly the change the real app would need.
    private static func foundationModelsProbe() -> [ProbeResult] {
        if #available(macOS 26.0, *) {
            return [ProbeResult(
                name: "Apple Foundation Models",
                status: .info,
                detail: "framework present (macOS 26+). CAVOK uses it only as a "
                    + "pre-download fallback; not required if MLX works."
            )]
        } else {
            return [ProbeResult(
                name: "Apple Foundation Models",
                status: .info,
                detail: "not available below macOS 26 — this is the case we are testing. "
                    + "CAVOK must reach the MLX path instead."
            )]
        }
    }
}
