import SwiftUI
import AppKit

/// Entry point. `--headless` runs every probe and prints the report to stdout —
/// used to verify the probe logic without a human clicking a button, and offered
/// to testers who would rather run a binary from Terminal than trust a GUI.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--headless") {
            var results = SystemProbe.run()
            results.append(contentsOf: MLXProbe.run())

            print("CAVOK COMPATIBILITY REPORT")
            print("generated \(ISO8601DateFormatter().string(from: Date()))")
            print("")
            for r in results {
                print("[\(r.status.rawValue)] \(r.name): \(r.detail)")
            }
            print("")
            let verdict: String
            if results.contains(where: { $0.status == .fail }) {
                verdict = "CAVOK would not run on this Mac"
            } else if results.contains(where: { $0.status == .warn }) {
                verdict = "CAVOK should run, with caveats noted above"
            } else {
                verdict = "CAVOK's engine runs on this Mac"
            }
            print("VERDICT: \(verdict)")
            exit(0)
        }
        CavokCompatApp.main()
    }
}

struct CavokCompatApp: App {
    var body: some Scene {
        WindowGroup("CAVOK Compatibility Check") {
            ContentView()
                .frame(minWidth: 620, idealWidth: 660, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class ProbeModel: ObservableObject {
    enum Phase { case idle, running, done }

    @Published var phase: Phase = .idle
    @Published var results: [ProbeResult] = []
    @Published var stage: String = ""
    @Published var copied = false

    /// System checks first so a crash in the GPU stage still leaves the tester
    /// with a partial report they can paste — a crash at a KNOWN step is a
    /// useful result, not a lost one.
    func run() {
        phase = .running
        results = []
        stage = "Reading system information…"

        Task {
            let system = await Task.detached(priority: .userInitiated) {
                SystemProbe.run()
            }.value
            self.results = system
            self.stage = "Running GPU work (this is the real test)…"

            // Let the window paint the system rows before the GPU stage starts,
            // so a hard trap in MLX is visibly attributable to this step.
            try? await Task.sleep(nanoseconds: 400_000_000)

            let mlx = await Task.detached(priority: .userInitiated) {
                MLXProbe.run()
            }.value
            self.results.append(contentsOf: mlx)
            self.stage = ""
            self.phase = .done
        }
    }

    var verdict: (String, Color)? {
        guard phase == .done else { return nil }
        if results.contains(where: { $0.status == .fail }) {
            return ("CAVOK would not run on this Mac", .red)
        }
        if results.contains(where: { $0.status == .warn }) {
            return ("CAVOK should run, with caveats noted below", .orange)
        }
        return ("CAVOK's engine runs on this Mac", .green)
    }

    /// Plain text, because testers paste this into a forum reply.
    func report() -> String {
        var lines: [String] = []
        lines.append("CAVOK COMPATIBILITY REPORT")
        lines.append("generated \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        for r in results {
            lines.append("[\(r.status.rawValue)] \(r.name): \(r.detail)")
        }
        if let verdict {
            lines.append("")
            lines.append("VERDICT: \(verdict.0)")
        }
        return lines.joined(separator: "\n")
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report(), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.copied = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ProbeModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.phase == .idle {
                        idleExplainer
                    } else {
                        ForEach(model.results) { result in
                            ResultRow(result: result)
                        }
                        if !model.stage.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(model.stage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CAVOK Compatibility Check")
                .font(.system(size: 20, weight: .semibold, design: .serif))
            Text("Does CAVOK's on-device study engine run on your Mac?")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleExplainer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What this does")
                .font(.system(size: 13, weight: .semibold))

            Text("CAVOK is a study app that runs a language model entirely on your "
                 + "own Mac. It currently requires macOS 26, and I'm trying to find "
                 + "out whether it can safely support older versions — but I only "
                 + "own one Mac to test on.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("This check runs real GPU work (the same maths CAVOK does to "
                 + "generate a word) and reports whether it succeeded. It takes "
                 + "about ten seconds.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)

            Label {
                Text("No network access. Nothing is sent anywhere. Nothing is "
                     + "written to disk. You read the result, and you choose "
                     + "whether to paste it back to me.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield")
            }
            .foregroundStyle(.secondary)

            Label {
                Text("No model is downloaded. This app is about 40 MB and does "
                     + "not fetch anything.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let verdict = model.verdict {
                Circle().fill(verdict.1).frame(width: 9, height: 9)
                Text(verdict.0)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if model.phase == .done {
                Button(model.copied ? "Copied" : "Copy report") {
                    model.copyReport()
                }
                .keyboardShortcut("c", modifiers: .command)
            }

            Button(model.phase == .done ? "Run again" : "Run check") {
                model.run()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.phase == .running)
        }
        .padding(16)
    }
}

struct ResultRow: View {
    let result: ProbeResult

    private var color: Color {
        switch result.status {
        case .pass: return .green
        case .fail: return .red
        case .warn: return .orange
        case .info: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .offset(y: -1)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 13, weight: .medium))
                Text(result.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
