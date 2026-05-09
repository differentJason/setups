CONTEXT HANDOFF — TNI Studio Install Cleanup
═══════════════════════════════════════════════════════════════════

USER: J (The Noises Inside project)
MACHINE: 2020 27" iMac (Intel, T2 chip), fresh T2-Mint 22.3 Cinnamon install
GOAL: Linux-based music production OS for hardware-centric experimental electronic music

CURRENT STATE:
- Primary install script (install_tni_studio_v2.sh) completed with partial success
- Failed packages: carla-bridges-native (ignore — not needed), surge-xt, dexed, helm
- Failed build: Overwitch (missing deps: autopoint, gettext, libsystemd-dev, libgtk-4-dev)
- Skipped: ReaPack + SWS (manual install from inside Reaper — correct choice)

ACTIVE TASK:
Run fix_tni_studio.sh located at ~/fix_tni_studio.sh (or grab from outputs dir).
This script will:
  1. Install missing Overwitch build deps + rebuild from ~/tni_install_tmp/overwitch
  2. Download Surge XT .deb from GitHub releases API + install
  3. Download Dexed .deb from GitHub releases API + install  
  4. Skip Helm (abandoned project, optional)

KEY PATHS:
- Install workdir: ~/tni_install_tmp/
- Scripts: ~/install_tni_studio_v2.sh, ~/fix_tni_studio.sh
- Install log: ~/tni_install_YYYYMMDD_HHMMSS.log (timestamped)
- Python venv: ~/.venvs/tni (rtmidi, mido, sounddevice, PyQt6, jack-client)
- Reaper config: ~/.config/REAPER/ (doesn't exist until first launch)

HARDWARE CONTEXT:
- Audio interface: Behringer UMC1820 (USB, class-compliant)
- Primary gear: Elektron Digitakt (needs Overwitch for multichannel JACK routing)
- Eurorack modular chain
- Python MIDI tools in development (MC-303 SysEx proxy project)

NEXT STEPS AFTER CLEANUP:
1. Reboot (activate audio group + realtime limits)
2. Verify: `groups | grep audio`, `ulimit -r` (should be 95)
3. First Reaper launch → audio config (PipeWire, 48kHz, 256 buffer)
4. Install ReaPack manually (download .so from reapack.com → ~/.config/REAPER/UserPlugins/)
5. Use ReaPack to install SWS Extension + other scripts from inside Reaper
6. Test Overwitch with Digitakt: `overwitch-cli -l`

WATCH FOR:
- Overwitch build failures: check config.log in ~/tni_install_tmp/overwitch/
- GitHub API rate limits on .deb downloads (shouldn't hit, but fallback to manual download URLs)
- Missing deps that autopoint/gettext might pull in (glib-related usually)

USER PREFERENCES:
- DIY/hacker ethos, visual learner, experimental approach
- Prioritizes pristine recording quality (48kHz/24-bit standard from studio skill)
- Python-fluent (PyQt6 toolkit)
- Reaper chosen specifically for Python ReaScript scripting capability

Run ./fix_tni_studio.sh and handle any failures. User will paste output.
═══════════════════════════════════════════════════════════════════
