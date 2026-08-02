CAVOK COMPATIBILITY CHECK
=========================

Thanks for helping. This takes about ten seconds.


WHAT IT IS

CAVOK is a Mac study app that runs a language model entirely on your own
machine -- no account, no API key, nothing sent to a server. It reads your
textbooks and answers questions from them.

It currently requires macOS 26. I want to lower that to macOS 15, so people
who simply haven't updated aren't locked out. Everything says it should
work, but I own one Mac and it's on macOS 26, so I can't actually verify it.

This app checks whether the part I can't test -- the GPU maths -- runs on
your Mac.


HOW TO USE IT

1. Drag the app anywhere you like (Applications, Desktop, wherever).
2. Double-click it.
3. Click "Run check".
4. Click "Copy report" and paste it back to me, if you're willing.

That's it. If you'd rather not send the report, that is completely fine --
have a look at it yourself and delete the app.


WHAT IT DOES NOT DO

- No network access. It cannot send me anything; there's no code to do it.
- Nothing is written to disk.
- Nothing is downloaded. No model, no updates, no installer.
- No login, no analytics, no identifiers.

You can verify the network claim yourself. This app ships with no
entitlements at all, so there is no network permission to find:

    codesign -d --entitlements - "CAVOK Compatibility Check.app"

It's signed and notarized by Apple under my Developer ID (John Tubbert),
so it opens normally -- no Gatekeeper warning, no right-click-Open.


PREFER THE TERMINAL?

The same report, without the GUI:

    "CAVOK Compatibility Check.app/Contents/MacOS/CavokCompat" --headless


WHAT IT ACTUALLY MEASURES

Some easy stuff -- your macOS version, chip, memory, free disk, GPU.

Then the part that matters: it runs real work on your GPU, including a
4-bit quantized matrix multiply. That's not a synthetic benchmark -- it's
the same operation the app performs for every single word it generates.
If that works on your Mac, the app will work on your Mac.


MOST USEFUL RIGHT NOW

macOS 15 (Sequoia) on Apple Silicon (M1-M4). That's the version I'm
planning to support, and the one I most need confirmed.

macOS 14 (Sonoma) is still worth running -- it tells me whether going even
further back would be worth the work.

Intel Macs will correctly report that they can't run it -- I already know
that, so no need to check unless you're curious.

If the app quits partway through, that's a useful result too -- please tell
me which step it reached. It deliberately shows your system details before
starting the GPU work so that a crash still tells me something.


Thanks again.
-- John
