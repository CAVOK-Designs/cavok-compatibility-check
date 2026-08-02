# CAVOK Compatibility Check

**A ten-second check that tells you whether CAVOK's on-device study engine can
run on your Mac.**

[**⬇ Download the latest release**](../../releases/latest) · 5 MB · macOS 14+ (runs to report) ·
Apple Silicon · signed and notarized by Apple

---

## Why this exists

[CAVOK](https://cavokdesigns.com) is a Mac study app that runs a language model
entirely on your own machine — no account, no API key, nothing sent to a server.
It reads your textbooks and answers questions from them.

It currently requires macOS 26. I want to lower that to **macOS 15**, so people
who simply haven't updated aren't locked out. (macOS 14 was the original target,
but the Textual markdown renderer that draws every answer declares `.macOS(.v15)`
— and so do all eight of its released versions, so 15 is the real floor without
replacing it.)

But I own one Mac and it runs macOS 26, so I cannot verify the part that actually
matters: whether the GPU maths runs on older systems. That's what this app checks,
and why I'm asking for help.

## Using it

1. Download and unzip. Drag the app anywhere you like.
2. Double-click it, then click **Run check**.
3. Click **Copy report**, and paste it back to me if you're willing.

If you'd rather not send the report, that's completely fine — look at it yourself
and delete the app.

Prefer the terminal? Same report, no GUI:

```sh
"CAVOK Compatibility Check.app/Contents/MacOS/CavokCompat" --headless
```

**Most useful right now:** **macOS 15 (Sequoia)** on Apple Silicon (M1–M4) —
that's the version I plan to support. macOS 14 (Sonoma) reports are still welcome;
they tell me whether going further back would be worth the work. Intel Macs will
correctly report that they can't run it — I already know that.

If the app *quits* partway through, that's a useful result too. Please tell me
which step it reached — system details are deliberately shown before the GPU work
starts, so a crash still identifies the machine and the failing step.

## What it does not do

- **No network access.** It cannot send me anything; there is no code to do it.
- **Nothing written to disk.** No preferences, no logs, no caches.
- **Nothing downloaded.** No model, no updates, no installer.
- No login, no analytics, no identifiers.

Don't take my word for it. The app ships with **no entitlements at all**, so
there is no network permission to find:

```sh
codesign -d --entitlements - "CAVOK Compatibility Check.app"
```

That prints an empty entitlement set. The source is in this repo, and it is small
enough to read in one sitting — `SystemProbe.swift` and `MLXProbe.swift` are the
whole story.

## What it measures

Cheap rows that never fail: macOS version and build · Apple Silicon vs Rosetta ·
RAM · free disk · Metal device · whether `FoundationModels` exists.

Then the rows that matter:

| Check | Why |
|---|---|
| MLX Metal backend | first call touching MLX's Metal layer — fails here with a name, not deep inside a kernel |
| float32 matmul, 2048² | general GPU compute path |
| **4-bit quantized matmul** | **the real Qwen3-4B decode path** — most specialised kernels, likeliest to differ across OS versions |
| sustained allocation | proxy for "won't thrash on 8 GB" |

That third one is the point. It isn't a synthetic benchmark — it's the same
operation the app performs for every word it generates. If it works on your Mac,
CAVOK will work on your Mac.

---

# Building it yourself

## What building this already established

Two things were proven locally, before any tester ran anything:

1. **mlx-swift builds cleanly at a 14.0 deployment target** — the resulting binary
   reports `minos 14.0`. That was the largest unknown.
2. **All 9 MLX Metal shaders compile at `-mmacosx-version-min=14.0`** (warnings only).

What remains unknown is *runtime* behaviour on real macOS 14/15 hardware.

## Commands

```sh
./Ship-Compat.sh --dry-run   # build + bundle, ad-hoc signed, no notarization
./Ship-Compat.sh             # build → sign → notarize → staple → zip
```

Notarization uses the same Developer ID certificate and `CAVOK` notary keychain
profile as `~/Desktop/Bloom/Ship.sh`.

## The Metal shader step

`swift build` does **not** compile `.metal` files — only Xcode does. A plain SPM
build of mlx-swift links fine and then dies at the first GPU dispatch with
`Failed to load the default metallib`. `Ship-Compat.sh` compiles the shader
library by hand and stages it at
`Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib`.

Two traps worth not relearning:

- **`-mmacosx-version-min=14.0` is load-bearing.** Copying the metallib out of the
  shipping `CAVOK.app` is easier, but that one is built for macOS 26. If it then
  failed to load on macOS 14, this app would have manufactured a false negative and
  wrongly concluded MLX can't run there — the exact opposite of its purpose.
- **The shader glob must be recursive.** `steel_attention.metal` lives in
  `steel/attn/kernels/`, and a flat `*.metal` glob silently drops it, producing a
  metallib that loads but is missing the attention kernels. The script asserts the
  compiled count matches the source count.

## Deliberate non-dependencies

- **Does not link BloomRAG.** That target imports `FoundationModels`, which is
  macOS 26-only and would drag the pin straight back in. This links `mlx-swift`
  directly.
- **No entitlements file.** Testers are strangers doing a favour; the ask should
  be as small as possible, and the claim should be checkable.
