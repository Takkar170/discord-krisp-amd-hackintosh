# Discord Krisp fix for AMD Hackintosh

Turning on **Krisp** noise suppression in the Discord desktop app on an AMD hackintosh
crashes Discord, usually a couple of seconds after you join a voice channel. This script
patches Discord's Krisp module so Krisp works on AMD CPUs.

> Not affiliated with Discord or Krisp. Use at your own risk. See [Risks](#risks).

## Symptoms

- Selecting **Krisp** under *Settings → Voice & Video → Noise Suppression* closes Discord, or
  Discord shows "something went wrong" and quits.
- Once Krisp is saved as on, Discord crashes every time you join voice.
- Launching Discord from Terminal
  (`/Applications/Discord.app/Contents/MacOS/Discord --enable-logging=stderr`) prints:

  ```
  Intel MKL ERROR: CPU 0 is not supported.
  Renderer process abnormal-exit ...
  ```

## Cause

Krisp's module (`discord_krisp.node`) has Intel's math library (MKL) built in.
On startup MKL checks the CPU vendor with `cpuid`. If it isn't `GenuineIntel`, MKL drops
to a generic "compatible" CPU type. The macOS build that Discord ships doesn't include kernels
for that type, so MKL prints the error above and kills the process. MKL environment
variables such as `MKL_CBWR` can't help, because they're checked against the same
Intel-only test.

## What the fix does

1. **Patches the x86_64 slice of `discord_krisp.node`:**
   - `mkl_serv_intel_cpu_true` and `mkl_serv_intel_cpu` always return 1, so MKL picks its
     code path from your CPU's real features (AVX2 on Zen 1–3) and stops checking the vendor.
   - `discord::util::IsSignedByDiscord` always returns true. Krisp checks that the
     process loading it is signed by Discord, and the next step changes that signature.
2. **Ad-hoc re-signs the patched module.**
3. **Re-signs `Discord Helper (Renderer).app` ad-hoc**, with library validation turned off
   so it can load the patched module. It also drops the two entitlements that only work
   under Discord's own team signature (`com.apple.application-identifier`,
   `keychain-access-groups`). Otherwise macOS kills the helper at launch with
   `Code Signature Invalid`.

The script finds the patch locations by symbol name and checks the original bytes first.
If Discord ships a different build, it stops instead of patching blindly. Originals are
backed up to `originals/` next to the script, and `undo-krisp-fix.sh` restores them.

No Discord files are included in this repo. Everything is patched in place on your own
machine.

## Usage

1. Open Discord once, so it downloads its Krisp module. If Discord keeps crashing,
   set *Noise Suppression* to **Standard** before you join voice.
2. Quit Discord completely (⌘Q).
3. In Terminal:

   ```sh
   git clone https://github.com/Takkar170/discord-krisp-amd-hackintosh.git
   cd discord-krisp-amd-hackintosh
   sudo ./fix-krisp.sh
   ```

   It should end with `Renderer helper re-signed` and `Done.`
4. Open Discord and set *Noise Suppression* to **Krisp**.

Keep this folder: it holds the backups that the undo script uses.

### Undo

```sh
sudo ./undo-krisp-fix.sh
```

Reinstalling Discord from discord.com also puts everything back.

## CPU compatibility

| CPU | Expected |
| --- | --- |
| Ryzen 1000–5000 (Zen 1–3), Threadripper, EPYC | Works. Tested on a Ryzen 5 5600X (MKL uses its AVX2 path). |
| Ryzen 7000/9000 (Zen 4/5) | Likely works, but untested. MKL will choose its AVX-512 path, so macOS on your hackintosh must actually enable AVX-512. If it doesn't, expect an illegal-instruction crash. |
| FX / Bulldozer / Phenom | Probably not. They lack AVX2, and this Krisp build may not include a path for them. |
| Intel or Apple Silicon Macs | Not needed. The script refuses to run. |

Tested on macOS 26.7.1 with Discord host 0.0.419 and `discord_krisp` module 1.

## Risks

- **Library validation is off for Discord's renderer process.** Normally it only loads
  code signed by Discord or Apple. After this fix it loads any code, so other software
  on your Mac could inject code into a process that can reach your microphone and your
  Discord session.
- **Krisp's own Discord-signature check is bypassed.** That check exists to stop
  non-Discord apps from using Discord's Krisp licence. This may go against Discord's
  terms. Use it at your own discretion.
- **The renderer no longer has Discord's keychain group**, which holds keys for Discord's
  end-to-end-encrypted voice (DAVE). Voice keeps working, but those keys aren't kept
  between launches.

## Troubleshooting

- **Krisp crashes again after a Discord update.** Updates replace the patched files.
  Quit Discord and run `sudo ./fix-krisp.sh` again.
- **`unexpected bytes at ...`** Discord shipped a Krisp build this patch doesn't know.
  Nothing was changed. Please open an issue with the output.
- **`Operation not permitted`** Allow Terminal under *System Settings → Privacy &
  Security → App Management* and run the script again.
- **Discord won't open at all.** Run `sudo ./undo-krisp-fix.sh`, or reinstall Discord.
- **Want to confirm Krisp is running?** After joining voice, check the end of
  `~/Library/Application Support/discord/logs/discord_krisp.log`. It should show
  `Setting Krisp model: full_NC`, and Discord should still be running.

## License

[MIT](LICENSE)
