# CS35L56 speaker amplifier firmware (GA403WM)

Firmware and tuning for the two Cirrus Logic CS35L56 (rev B0) speaker amplifiers at I2C 0x30 / 0x31, used by
`tools/strixampctl` through the `StrixAmp` kext (`docs/AUDIO-ROG.md`). Nothing here is compiled into a kext: the files are
read from disk by the userland tool at run time.

| File | Role | SHA-256 |
|---|---|---|
| `CS35L56_Rev3.11.16.wmfw` | HALO DSP firmware, core ID `0x1a00d6` v3.11.16 | `12c6d4fe63dc6a471473182dfdb72b1a91092e62db0038c48d9676d9566eff58` |
| `cs35l56-b0-dsp1-misc-10431044-spkid0-amp1.bin` | tuning, speaker-ID 0, amp at 0x30 | `80991ea93c5cb52a5bb5186a121c7c6322b1437a66270991f4289eab00bc410f` |
| `cs35l56-b0-dsp1-misc-10431044-spkid0-amp2.bin` | tuning, speaker-ID 0, amp at 0x31 | `5f691b512e95995ddbce81ffb6a9c47723c9e0e9e1b4a6f5acacea243c2bb024` |
| `cs35l56-b0-dsp1-misc-10431044-spkid1-amp1.bin` | tuning, speaker-ID 1, amp at 0x30 | `108671391e61a59688dc99a57918253a04ff439d28948c83684c4da652209997` |
| `cs35l56-b0-dsp1-misc-10431044-spkid1-amp2.bin` | tuning, speaker-ID 1, amp at 0x31 | `380e8f976532c5d6525235329c607de1609fdc0e957607169a56fe60a4b56c5f` |

## Provenance

Taken unchanged from the ASUS audio driver package on the machine's own Windows installation
(`csaudioext.inf_amd64_*/Jamerson/Firmware/CS35L56_Rev3_11_16` and `Tuning/ASUS_GA403K_10431044_241108`, files
`10431044_241108_V{0,1}_A{0,1}-init.bin`). The package's INF maps this laptop (`SUBSYS_10431024`) to the GA403K / `10431044`
tuning set. The four tuning files are byte-identical to `cirrus/cs35l56-b0-dsp1-misc-10431044-spkid{0,1}-amp{1,2}.bin` of
linux-firmware, which is where the names above come from (`V` = speaker-ID strap, GPIO 104; `A0`/`A1` = amp 1 / amp 2).

The speaker-ID strap is read by the kext (`ioreg -l -n StrixAmp | grep SpeakerId`) and selects the `spkid0` / `spkid1` pair.

## License

These are Cirrus Logic firmware files, redistributable for use with Cirrus Logic devices (see the `cs35l56` entries of
linux-firmware's `WHENCE`). **They are not under the Clear BSD License of this repository.** Do not combine them into
anything that would require them to be licensed under GPL/LGPL.
