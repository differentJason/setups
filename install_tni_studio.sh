#!/usr/bin/env bash
#
# install_tni_studio.sh
# ----------------------------------------------------------------------------
# The Noises Inside studio bootstrap for T2-Mint 22.3 (Cinnamon, noble base).
#
# Primary anchor: REAPER 7.72 (with Python ReaScript ready)
# Secondary DAW:  Ardour (good companion + Overwitch-friendly)
# Hardware glue:  Overwitch + Elektroid (Digitakt over USB → JACK/PipeWire)
# Audio stack:    PipeWire-JACK (already shipping in Mint 22.3), realtime privs
# Plugins:        LSP, Calf, x42, ZAM, Dragonfly, DPF, distrho ports
# Soft synths:    ZynAddSubFX, Yoshimi, Surge XT, Dexed, Helm, Hydrogen
# Plugin host:    Carla
# Python toolkit: rtmidi, mido, sounddevice, PyQt6, pyserial
#
# Designed to be idempotent. Run from your user account; will prompt for sudo.
# Sections are marked SECTION N — comment any out to skip.
# ----------------------------------------------------------------------------

set -euo pipefail

# Pretty-print helpers
say()  { printf "\n\033[1;36m▌ %s\033[0m\n" "$*"; }
ok()   { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[1;33m!\033[0m %s\n" "$*"; }

require_user() {
  if [[ $EUID -eq 0 ]]; then
    echo "Run as your normal user, not root. Sudo will prompt where needed." >&2
    exit 1
  fi
}
require_user

REAPER_VERSION="7.72"
REAPER_TARBALL="reaper${REAPER_VERSION//./}_linux_x86_64.tar.xz"
REAPER_URL="https://www.reaper.fm/files/${REAPER_VERSION%%.*}.x/${REAPER_TARBALL}"
WORKDIR="${HOME}/tni_install_tmp"
mkdir -p "$WORKDIR"

# ============================================================================
# SECTION 1 — System prep & realtime audio privileges
# ============================================================================
say "[1/12] System update + realtime audio privileges"

sudo apt-get update
sudo apt-get install -y \
  build-essential git curl wget xz-utils \
  pkg-config autoconf automake libtool \
  software-properties-common ca-certificates

# Audio group + realtime limits (PipeWire honors these for rtprio)
if ! getent group audio | grep -qw "$USER"; then
  sudo usermod -aG audio "$USER"
  warn "Added $USER to 'audio' group — log out/in (or reboot) to take effect."
fi

sudo tee /etc/security/limits.d/95-audio-tni.conf >/dev/null <<'EOF'
# TNI studio realtime privileges
@audio   -  rtprio     95
@audio   -  memlock    unlimited
@audio   -  nice       -19
EOF
ok "Realtime limits installed at /etc/security/limits.d/95-audio-tni.conf"

# ============================================================================
# SECTION 2 — PipeWire / JACK / ALSA tooling
# ============================================================================
# Mint 22.3 ships PipeWire by default. We just ensure the JACK bridge is
# present and add the ALSA-MIDI ↔ JACK bridge for Eurorack/MIDI-CV setups.
say "[2/12] PipeWire JACK bridge + MIDI tooling"

sudo apt-get install -y \
  pipewire pipewire-pulse pipewire-jack libspa-0.2-bluetooth \
  wireplumber pipewire-audio-client-libraries \
  qjackctl helvum pavucontrol \
  a2jmidid jack-tools alsa-utils
ok "PipeWire-JACK, Helvum patchbay, a2jmidid, qjackctl installed"

# Sensible PipeWire defaults: 48 kHz, allow common rates, reasonable quantum
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"
cat > "$HOME/.config/pipewire/pipewire.conf.d/10-tni-rates.conf" <<'EOF'
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 ]
    default.clock.quantum       = 512
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 8192
}
EOF
ok "PipeWire default rate locked to 48 kHz (TNI standard)"

# ============================================================================
# SECTION 3 — Verify UMC1820 visible to ALSA (informational)
# ============================================================================
say "[3/12] Audio device check"
echo "Playback devices:" && aplay -l || true
echo "Capture devices:"  && arecord -l || true
warn "Confirm UMC1820 appears above. If not, plug it in & re-run from here."

# ============================================================================
# SECTION 4 — REAPER 7.72
# ============================================================================
say "[4/12] REAPER ${REAPER_VERSION}"

if ! command -v reaper >/dev/null 2>&1; then
  cd "$WORKDIR"
  wget -nc "$REAPER_URL"
  tar -xf "$REAPER_TARBALL"
  cd "reaper_linux_x86_64"
  # Non-interactive system-wide install
  sudo ./install-reaper.sh --install /opt --integrate-desktop --quiet
  ok "REAPER installed to /opt/REAPER"
else
  ok "REAPER already present, skipping"
fi

# ============================================================================
# SECTION 5 — REAPER extensions: SWS + ReaPack
# ============================================================================
# say "[5/12] REAPER extensions (SWS, ReaPack)"
# 
# REAPER_PLUGINS_DIR="$HOME/.config/REAPER/UserPlugins"
# mkdir -p "$REAPER_PLUGINS_DIR"
# 
# ReaPack (the package manager — gateway to scripts/extensions ecosystem)
# REAPACK_URL="https://reapack.com/latest/linux-x86_64"
# if [[ ! -f "$REAPER_PLUGINS_DIR/reaper_reapack-x86_64.so" ]]; then
#   wget -O "$REAPER_PLUGINS_DIR/reaper_reapack-x86_64.so" "$REAPACK_URL"
#   ok "ReaPack installed → $REAPER_PLUGINS_DIR"
# else
#   ok "ReaPack already present"
# fi
# 
# SWS Extension (must-have; adds hundreds of actions + script-friendly API)
# SWS_URL="https://www.sws-extension.org/download/featured/sws-2.14.0.4-linux-x86_64.tar.xz"
# if [[ ! -f "$REAPER_PLUGINS_DIR/reaper_sws-x86_64.so" ]]; then
#   cd "$WORKDIR"
#   wget -nc "$SWS_URL" -O sws.tar.xz
#   tar -xf sws.tar.xz
#   cp reaper_sws-x86_64.so "$REAPER_PLUGINS_DIR/"
#   ok "SWS Extension installed"
# else
#   ok "SWS already present"
# fi
# 
# warn "First REAPER launch: Extensions → ReaPack → Browse packages, then import"
# warn "  https://github.com/ReaTeam/Extensions/raw/master/index.xml for ReaTeam"

# ============================================================================
# SECTION 6 — Ardour (secondary DAW, great for stem capture)
# ============================================================================
say "[6/12] Ardour"
sudo apt-get install -y ardour
ok "Ardour installed"

# ============================================================================
# SECTION 7 — Plugin packages (LV2 / VST / VST3 / CLAP friendly)
# ============================================================================
say "[7/12] Plugin packs"
sudo apt-get install -y \
  lsp-plugins \
  calf-plugins \
  x42-plugins \
  zam-plugins \
  dragonfly-reverb \
  dpf-plugins-lv2 \
  distrho-plugin-ports-lv2 \
  noise-repellent \
  swh-plugins \
  caps
ok "LSP, Calf, x42, ZAM, Dragonfly, DPF, distrho, swh, CAPS installed"

# Carla — universal plugin host, can rack any plugin format and JACK-route it
sudo apt-get install -y carla carla-bridges-native carla-data
ok "Carla plugin host installed"

# ============================================================================
# SECTION 8 — Soft synths & instruments
# ============================================================================
say "[8/12] Soft synths"
sudo apt-get install -y \
  zynaddsubfx \
  yoshimi \
  surge-xt \
  dexed \
  helm \
  hydrogen \
  amsynth \
  bristol
ok "Synths installed: Zyn, Yoshimi, Surge XT, Dexed, Helm, Hydrogen, AMSynth, Bristol"

# ============================================================================
# SECTION 9 — Overwitch (Elektron Digitakt → JACK multichannel)
# ============================================================================
say "[9/12] Overwitch (Digitakt over USB)"

sudo apt-get install -y \
  libjack-jackd2-dev \
  libsamplerate0-dev \
  libusb-1.0-0-dev \
  libsndfile1-dev \
  libgtk-3-dev \
  libjson-glib-dev

if ! command -v overwitch >/dev/null 2>&1; then
  cd "$WORKDIR"
  if [[ ! -d overwitch ]]; then
    git clone https://github.com/dagargo/overwitch.git
  fi
  cd overwitch
  autoreconf --install
  ./configure
  make -j"$(nproc)"
  sudo make install
  # Refresh udev so non-root can hit the Digitakt
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  ok "Overwitch built & installed; udev rules reloaded"
else
  ok "Overwitch already installed"
fi

# ============================================================================
# SECTION 10 — Elektroid (sample/pattern transfer to/from Elektron gear)
# ============================================================================
say "[10/12] Elektroid"
if apt-cache show elektroid >/dev/null 2>&1; then
  sudo apt-get install -y elektroid
  ok "Elektroid installed from repo"
else
  warn "Elektroid not in repo — grab .deb from https://github.com/dagargo/elektroid/releases"
fi

# ============================================================================
# SECTION 11 — Python audio/MIDI toolkit (Reaper Python ReaScript + your tools)
# ============================================================================
say "[11/12] Python audio/MIDI toolkit"

sudo apt-get install -y python3 python3-pip python3-venv python3-dev

# Build a dedicated venv so we don't fight system Python
TNI_VENV="$HOME/.venvs/tni"
if [[ ! -d "$TNI_VENV" ]]; then
  python3 -m venv "$TNI_VENV"
fi
# shellcheck disable=SC1091
source "$TNI_VENV/bin/activate"
pip install --upgrade pip wheel
pip install \
  python-rtmidi \
  mido \
  sounddevice \
  numpy scipy \
  PyQt6 \
  pyserial \
  jack-client
deactivate
ok "Python venv at $TNI_VENV (activate with: source $TNI_VENV/bin/activate)"

# Reaper Python ReaScript needs to know where Python lives. Reaper UI:
#   Options → Preferences → Plug-ins → ReaScript
#   Custom path = $TNI_VENV/lib
#   Force ReaScript to use Python = python3.12 (or whatever your venv shows)
warn "REAPER → Prefs → Plug-ins → ReaScript: point Python path at $TNI_VENV/lib"

# ============================================================================
# SECTION 12 — Quality-of-life utilities
# ============================================================================
say "[12/12] Utilities"
sudo apt-get install -y \
  audacity \
  sox \
  ffmpeg \
  vmpk \
  meterbridge \
  jaaa \
  jamin
ok "Audacity, sox, ffmpeg, VMPK, meterbridge, JAAA, JAMin installed"

# ============================================================================
# DONE
# ============================================================================
say "Install complete"
cat <<EOF

  Reboot once so the audio-group + realtime limits take effect.

  After reboot, verify quickly:
    groups | grep audio        → should list 'audio'
    ulimit -r                  → should be 95
    pw-metadata -n settings 0  → should show clock.rate 48000
    overwitch-cli -l           → should detect the Digitakt when plugged in

  First REAPER launch:
    1. Run 'reaper' from terminal or app menu
    2. Audio prefs → Device: PipeWire (or ALSA hw:UMC1820 directly)
    3. Sample rate: 48000, block: 256 (your TNI recording standard)
    4. Extensions menu → ReaPack → Manage repositories → import
       https://github.com/ReaTeam/Extensions/raw/master/index.xml

  Workdir at $WORKDIR can be removed when you're confident:
    rm -rf "$WORKDIR"

EOF
