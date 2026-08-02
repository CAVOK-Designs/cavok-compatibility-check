import Foundation
import MLX
import MLXRandom

/// The checks that actually matter. Everything in SystemProbe could be answered
/// by asking a tester to read their About This Mac; only this file answers
/// "does CAVOK's inference engine run on your OS".
///
/// Deliberately runs REAL GPU work rather than just linking the framework:
/// mlx-swift compiles its own Metal kernels, and a kernel that fails to build
/// on an older OS would still link fine and only blow up at first dispatch.
enum MLXProbe {

    /// Roughly the shapes a Qwen3-4B decode step pushes through, small enough
    /// that an 8 GB machine is never at risk.
    private static let dim = 2048

    static func run() -> [ProbeResult] {
        var out: [ProbeResult] = []

        // ── 1. Metal backend reachable through MLX ────────────────────────────
        // GPU.deviceInfo() is the first call that touches mlx's Metal layer. If
        // the backend is broken on this OS, we want to fail HERE with a name,
        // not deep inside a matmul.
        let info = GPU.deviceInfo()
        out.append(ProbeResult(
            name: "MLX Metal backend",
            status: .pass,
            detail: "architecture \(info.architecture), "
                + String(format: "%.1f GB recommended working set",
                         Double(info.maxRecommendedWorkingSetSize) / 1_073_741_824.0)
        ))

        // ── 2. Float32 matmul on the GPU ──────────────────────────────────────
        let (floatOK, floatDetail) = timed {
            let a = MLXRandom.normal([dim, dim])
            let b = MLXRandom.normal([dim, dim])
            let c = matmul(a, b)
            eval(c)
            // Touch the result so the compiler cannot elide the work.
            return c.shape == [dim, dim]
        }
        out.append(ProbeResult(
            name: "MLX float32 matmul",
            status: floatOK ? .pass : .fail,
            detail: "\(dim)×\(dim) on GPU — \(floatDetail)"
        ))

        // ── 3. Quantized 4-bit matmul ─────────────────────────────────────────
        // This is THE test. CAVOK ships a 4-bit quantized Qwen3, so the quantized
        // kernels are the hot path at every generated token. They are also the
        // most specialised Metal code in MLX and the likeliest thing to differ
        // across OS versions.
        let (quantOK, quantDetail) = timed {
            let w = MLXRandom.normal([dim, dim])
            let (wq, scales, biases) = quantized(w, groupSize: 64, bits: 4)
            let x = MLXRandom.normal([1, dim])
            let y = quantizedMM(x, wq, scales: scales, biases: biases,
                                transpose: true, groupSize: 64, bits: 4)
            eval(y)
            return y.shape == [1, dim]
        }
        out.append(ProbeResult(
            name: "MLX 4-bit quantized matmul",
            status: quantOK ? .pass : .fail,
            detail: "the Qwen3-4B decode path — \(quantDetail)"
        ))

        // ── 4. Sustained allocation ───────────────────────────────────────────
        // CAVOK holds ~2.5 GB of weights resident. Allocating and evaluating in a
        // loop is a cheap proxy for "this machine will not thrash or get killed".
        let (allocOK, allocDetail) = timed {
            var kept: [MLXArray] = []
            for _ in 0..<8 {
                let chunk = MLXRandom.normal([1024, 1024])   // 4 MB each
                eval(chunk)
                kept.append(chunk)
            }
            return kept.count == 8
        }
        out.append(ProbeResult(
            name: "MLX sustained allocation",
            status: allocOK ? .pass : .warn,
            detail: "8 × 4 MB resident — \(allocDetail)"
        ))

        return out
    }

    /// Runs `body`, returning success plus a human-readable timing (or the
    /// error). Catches Objective-C exceptions is NOT possible here — an MLX
    /// kernel failure will trap — which is itself informative: a tester who
    /// reports "it quit at step 3" has told us what we need.
    private static func timed(_ body: () throws -> Bool) -> (Bool, String) {
        let start = Date()
        do {
            let ok = try body()
            let ms = Date().timeIntervalSince(start) * 1000
            return (ok, ok ? String(format: "%.0f ms", ms) : "returned unexpected shape")
        } catch {
            return (false, "error: \(error)")
        }
    }
}
