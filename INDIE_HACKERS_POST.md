# Indie Hackers post — draft

Two versions. The first is the honest-ask version and is the one I'd post.
The second is shorter if you want it as a comment/reply instead.

---

## Version A — the post

**Title:** I can only test my Mac app on one Mac. Would you run a 10-second check on yours?

I built CAVOK, a study app that runs a language model entirely on your own
Mac — no account, no API key, no data leaving the machine. It reads your
textbooks and answers questions from them.

It currently requires macOS 26. I want to lower that to macOS 14 so it runs on
every Apple Silicon Mac ever made, and I'm fairly confident it will work — every
dependency it uses declares macOS 14 or lower as its minimum, and it compiles
cleanly at that target.

"Fairly confident" isn't good enough to ship, though. The part I can't verify is
whether the GPU maths actually runs on macOS 14 and 15, because I own exactly one
Mac and it's on 26.

So I made a tiny separate app that answers that question:

**CAVOK Compatibility Check** — [link]

It's 28 MB, takes about ten seconds, and it does real work: it runs the same
kind of GPU tensor operations CAVOK does to generate a word, including the 4-bit
quantized path that the model actually uses at every token. Then it shows you a
list of pass/fail results and a "Copy report" button.

**What it does not do:**

- No network access at all. It isn't sending me anything.
- Nothing is written to disk.
- Nothing is downloaded — no model, no updates.
- It's signed and notarized by Apple, so it just opens.

You read the report, and *you* decide whether to paste it back here. If you'd
rather not, that's genuinely fine.

**Most useful to me right now:** anyone on **macOS 14 (Sonoma) or 15 (Sequoia)**
with an Apple Silicon Mac (M1 through M4). Intel Macs will correctly report that
they can't run it — that part I already know.

If you're Terminal-inclined and would rather not trust a GUI, the binary takes
`--headless` and prints the same report to stdout:

```
"/Applications/CAVOK Compatibility Check.app/Contents/MacOS/CavokCompat" --headless
```

Happy to return the favour on anything you're building — I'm reasonably deep in
Swift, Metal, and shipping to the Mac App Store, including the parts of
notarization that are genuinely annoying.

---

## Version B — short version

I'm trying to drop my Mac app's minimum from macOS 26 to macOS 14, but I only
own one Mac and it's on 26, so I can't verify the GPU path on older systems.

Made a 28 MB checker that runs the real tensor operations and prints a
pass/fail report: [link]

No network, nothing written to disk, nothing downloaded, notarized by Apple.
You copy the result and decide whether to paste it back.

Especially need **macOS 14 or 15 on Apple Silicon**. Takes ten seconds. Happy
to trade help on Swift/Metal/App Store stuff.

---

## Notes for you (don't post this bit)

**Answer the "why should I trust your binary" question before it's asked.** That's
why the no-network / no-disk / notarized lines are high up. Anyone technical
enough to be useful here is exactly the person who'll wonder.

They can verify the network claim themselves:

```
codesign -d --entitlements - "/Applications/CAVOK Compatibility Check.app"
```

The app ships with no entitlements file at all, so there's no
`com.apple.security.network.client` to find. Worth mentioning if someone asks —
it turns a claim into something checkable.

**What a useful reply looks like.** You're looking for the three MLX lines. If a
macOS 14 tester comes back with all three PASS, the port is de-risked and you can
schedule it. If the quantized matmul fails on 14 but passes on 15, that sets the
floor at 15 and you've still gained users. If someone reports the app *quit* partway,
that's a result too — the probe prints system rows before starting GPU work
specifically so a crash still tells you which machine and which step.

**Cross-post targets** beyond Indie Hackers, same text: r/macapps, r/swift, the
Swift forums, and MLX's GitHub Discussions (that last one is likely to get you a
direct answer from someone who already knows the OS floor).

**Don't oversell CAVOK in the post.** The ask is a favour, not a launch. The
soft-launch value is real but secondary — people who help will look it up anyway.
