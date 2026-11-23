# rogaudio-test

Small CoreAudio probes used for the mic and speaker checks in docs/AUDIO-ROG.md (sections 14-18). Build into a scratch folder:

    swiftc -O tools/rogaudio-test/rec.swift   -o /private/tmp/claude-501/rec
    swiftc -O tools/rogaudio-test/inctl.swift -o /private/tmp/claude-501/inctl

* `rec UID seconds [channels]`: per-channel peak / RMS every 0.5 s; `CORR=1` adds channel-pair correlation.
  Built-in Input UID `AppleHDAEngineInput:0,6,0,1,0:1`, ROG Clear Mic `com.itlmt7925.rogaudio.mic`.
* `inctl [UID [source]]`: input gain elements, mute, data sources (and optionally selects one).

Speech source for tests: `say -a "Built-in Output" -v Samantha "Testing the microphone, one two three"`.
