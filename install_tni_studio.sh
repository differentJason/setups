#!/usr/bin/env bash
#
# install_tni_studio.sh  (v2 — resilient)
# ----------------------------------------------------------------------------
# The Noises Inside studio bootstrap for T2-Mint 22.3 (Cinnamon, noble base).
#
# Anchor:    REAPER 7.72 + Python ReaScript
# Audio:     PipeWire-JACK, 48kHz, realtime privs
# Hardware:  Overwitch (Digitakt → JACK) + Elektroid
# Plugins:   LSP, Calf, x42, ZAM, Dragonfly, DPF, swh, CAPS
# Synths:    Zyn, Yoshimi, Surge XT, Dexed, Helm, Hydrogen, AMSynth, Bristol
# Hosting:   Carla
# Python:    rtmidi, mido, sounddevice, PyQt6, pyserial, jack-client (in venv)
#
# v2 changes:
#  - Failures no longer kill the script.
#  - Each apt package installed individually; failures tracked & reported.
#  - SWS + ReaPack moved to manual post-install (cleaner via ReaPack GUI).
#  - Final summary lists what installed, what failed, and remaining manual steps.
# ----------------------------------------------------------------------------

# Note: NO `set -e` — we want to continue past failures and report them.
set -uo pipefail

# ---------- output helpers --------------------------------------------------
say()  { printf "\n\033[1;36m▌ %s\033[0m\n" "$*"; }
ok()   { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[1;33m!\033[0m %s\n" "$*"; }
err()  { printf "  \033[1;31m✗\033[0m %s\n" "$*"; }

# ---------- result tracking -------------------------------------------------
INSTALLED=()       # successfully installed (or already present) packages
FAILED_PKGS=()     # packages apt could not install
FAILED_STEPS=()    # higher-level step failures (build, download, etc.)
SKIPPED_STEPS=()   # explicitly skipped sections

# ---------- safety: no root -------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  echo "Run as your normal user, not root. Sudo will prompt where needed." >&2
  exit 1
fi

# ---------- apt install helper (idempotent, non-fatal) ----------------------
apt_install() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    INSTALLED+=("$pkg (already)")
    ok "$pkg (already installed)"
    return 0
  fi
  if sudo apt-get install -y "$pkg" >/dev/null 2>&1; then
    INSTALLED+=("$pkg")
    ok "$pkg"
    return 0
  else
    FAILED_PKGS+=("$pkg")
    err "$pkg — not available or failed"
    return 1
  fi
}

# ---------- step wrapper for non-apt operations -----------------------------
run_step() {
  local desc="$1"; shift
  if "$@"; then
    ok "$desc"
    return 0
  else
    FAILED_STEPS+=("$desc")
    err "$desc — failed (continuing)"
    return 1
  fi
}

REAPER_VERSION="7.72"
REAPER_TARBALL="reaper${REAPER_VERSION//./}_linux_x86_64.tar.xz"
REAPER_URL="https://www.reaper.fm/files/${REAPER_VERSION%%.*}.x/${REAPER_TARBALL}"
WORKDIR="${HOME}/tni_install_tmp"
mkdir -p "$WORKDIR"

# ============================================================================
# SECTION 1 — System prep & realtime audio privileges
# ============================================================================
say "[1/11] System update + realtime audio privileges"

sudo apt-get update || warn "apt-get update returned non-zero (continuing)"

for p in build-essential git curl wget xz-utils \
         pkg-config autoconf automake libtool \
         software-properties-common ca-certificates; do
  apt_install "$p"
done

if ! getent group audio | grep -qw "$USER"; then
  if sudo usermod -aG audio "$USER"; then
    ok "Added $USER to 'audio' group (re-login required)"
  else
    FAILED_STEPS+=("add user to audio group")
  fi
else
  ok "$USER already in audio group"
fi

if sudo tee /etc/security/limits.d/95-audio-tni.conf >/dev/null <<'EOF'
# TNI studio realtime privileges
@audio   -  rtprio     95
@audio   -  memlock    unlimited
@audio   -  nice       -19
EOF
then
  ok "Realtime limits installed"
else
  FAILED_STEPS+=("realtime limits file")
fi

# ============================================================================
# SECTION 2 — PipeWire / JACK / ALSA tooling
# ============================================================================
say "[2/11] PipeWire JACK bridge + MIDI tooling"

for p in pipewire pipewire-pulse pipewire-jack libspa-0.2-bluetooth \
         wireplumber pipewire-audio-client-libraries \
         qjackctl helvum pavucontrol \
         a2jmidid jack-tools alsa-utils; do
  apt_install "$p"
done

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
ok "PipeWire 48 kHz default written"

# ============================================================================
# SECTION 3 — Audio device check (informational only)
# ============================================================================
say "[3/11] Audio device check"
echo "--- Playback devices ---"
aplay -l 2>/dev/null || warn "aplay not yet available"
echo "--- Capture devices ---"
arecord -l 2>/dev/null || warn "arecord not yet available"
warn "Confirm UMC1820 appears above (or plug it in & check later)"

# ============================================================================
# SECTION 4 — REAPER 7.72
# ============================================================================
say "[4/11] REAPER ${REAPER_VERSION}"

if command -v reaper >/dev/null 2>&1; then
  ok "REAPER already installed"
  INSTALLED+=("REAPER ${REAPER_VERSION} (already)")
else
  cd "$WORKDIR"
  if wget -nc "$REAPER_URL" 2>/dev/null && tar -xf "$REAPER_TARBALL"; then
    cd "reaper_linux_x86_64"
    if sudo ./install-reaper.sh --install /opt --integrate-desktop --quiet; then
      ok "REAPER installed to /opt/REAPER"
      INSTALLED+=("REAPER ${REAPER_VERSION}")
    else
      err "REAPER installer failed"
      FAILED_STEPS+=("REAPER install")
    fi
  else
    err "REAPER download/extract failed"
    FAILED_STEPS+=("REAPER download")
  fi
  cd "$WORKDIR"
fi

# ============================================================================
# SECTION 5 — REAPER extensions: SKIPPED (do via ReaPack GUI post-install)
# ============================================================================
say "[5/11] REAPER extensions — SKIPPED"
warn "ReaPack + SWS install via Reaper itself after first launch."
warn "Instructions printed in the final summary."
SKIPPED_STEPS+=("Section 5: ReaPack/SWS — install from inside REAPER")

# ============================================================================
# SECTION 6 — Ardour
# ============================================================================
say "[6/11] Ardour"
apt_install ardour

# ============================================================================
# SECTION 7 — Plugin packages (per-package; tolerant of missing)
# ============================================================================
say "[7/11] Plugin packs"
for p in lsp-plugins calf-plugins x42-plugins zam-plugins \
         dragonfly-reverb dpf-plugins-lv2 swh-plugins caps; do
  apt_install "$p"
done
# Carla plugin host
for p in carla carla-bridges-native carla-data; do
  apt_install "$p"
done

# ============================================================================
# SECTION 8 — Soft synths & instruments
# ============================================================================
say "[8/11] Soft synths"
for p in zynaddsubfx yoshimi surge-xt dexed helm hydrogen amsynth bristol; do
  apt_install "$p"
done

# ============================================================================
# SECTION 9 — Overwitch (Digitakt → JACK)
# ============================================================================
say "[9/11] Overwitch"

OW_DEPS_OK=true
for p in libjack-jackd2-dev libsamplerate0-dev libusb-1.0-0-dev \
         libsndfile1-dev libgtk-3-dev libjson-glib-dev; do
  apt_install "$p" || OW_DEPS_OK=false
done

if command -v overwitch >/dev/null 2>&1; then
  ok "Overwitch already installed"
  INSTALLED+=("overwitch (already)")
elif ! $OW_DEPS_OK; then
  err "Overwitch build deps missing — skipping build"
  FAILED_STEPS+=("Overwitch build deps")
else
  cd "$WORKDIR"
  build_overwitch() {
    [[ -d overwitch ]] || git clone https://github.com/dagargo/overwitch.git || return 1
    cd overwitch || return 1
    autoreconf --install || return 1
    ./configure || return 1
    make -j"$(nproc)" || return 1
    sudo make install || return 1
    sudo udevadm control --reload-rules
    sudo udevadm trigger
  }
  if build_overwitch; then
    ok "Overwitch built & installed"
    INSTALLED+=("overwitch (from source)")
  else
    err "Overwitch build failed — check logs in $WORKDIR/overwitch"
    FAILED_STEPS+=("Overwitch build")
  fi
  cd "$WORKDIR"
fi

# ============================================================================
# SECTION 10 — Elektroid (also via apt; falls back to manual instruction)
# ============================================================================
say "[10/11] Elektroid"
if apt-cache show elektroid >/dev/null 2>&1; then
  apt_install elektroid
else
  warn "Elektroid not in repo — grab .deb from https://github.com/dagargo/elektroid/releases"
  SKIPPED_STEPS+=("Elektroid: install .deb manually from GitHub releases")
fi

# ============================================================================
# SECTION 11 — Python venv + utilities
# ============================================================================
say "[11/11] Python toolkit + utilities"

for p in python3 python3-pip python3-venv python3-dev; do
  apt_install "$p"
done

TNI_VENV="$HOME/.venvs/tni"
if [[ ! -d "$TNI_VENV" ]]; then
  if python3 -m venv "$TNI_VENV"; then
    ok "Created venv at $TNI_VENV"
  else
    FAILED_STEPS+=("create venv")
  fi
fi

if [[ -f "$TNI_VENV/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$TNI_VENV/bin/activate"
  pip install --upgrade pip wheel >/dev/null 2>&1 || warn "pip upgrade failed"
  for pypkg in python-rtmidi mido sounddevice numpy scipy PyQt6 pyserial jack-client; do
    if pip install "$pypkg" >/dev/null 2>&1; then
      ok "py: $pypkg"
      INSTALLED+=("py: $pypkg")
    else
      err "py: $pypkg failed"
      FAILED_PKGS+=("py: $pypkg")
    fi
  done
  deactivate
fi

# Quality-of-life utilities
for p in audacity sox ffmpeg vmpk meterbridge jaaa jamin; do
  apt_install "$p"
done

# ============================================================================
# SUMMARY
# ============================================================================
say "INSTALL SUMMARY"

echo ""
echo "  Installed (or already present): ${#INSTALLED[@]} items"
echo ""

if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
  printf "\033[1;33m  Failed packages (${#FAILED_PKGS[@]}):\033[0m\n"
  for p in "${FAILED_PKGS[@]}"; do
    echo "    - $p"
  done
  echo ""
fi

if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
  printf "\033[1;31m  Failed steps (${#FAILED_STEPS[@]}):\033[0m\n"
  for s in "${FAILED_STEPS[@]}"; do
    echo "    - $s"
  done
  echo ""
fi

if [[ ${#SKIPPED_STEPS[@]} -gt 0 ]]; then
  printf "\033[1;36m  Intentionally skipped (handle manually):\033[0m\n"
  for s in "${SKIPPED_STEPS[@]}"; do
    echo "    - $s"
  done
  echo ""
fi

cat <<EOF

────────────────────────────────────────────────────────────────────
  NEXT STEPS

  1.  Reboot to activate audio group + realtime limits:
        sudo reboot

  2.  After reboot, verify:
        groups | grep audio        → should list 'audio'
        ulimit -r                  → should be 95
        pw-metadata -n settings 0  → should show clock.rate 48000

  3.  Install ReaPack (REAPER package manager):
        Visit https://reapack.com/ in a browser, click the Linux
        x86_64 download, save the .so file to:
          ~/.config/REAPER/UserPlugins/

  4.  Launch REAPER (terminal: 'reaper').
      a) Audio prefs → Device: PipeWire (or ALSA hw:UMC1820)
      b) Sample rate: 48000, block: 256
      c) Extensions → ReaPack → Browse packages → install:
           - SWS/S&M Extension  (mandatory)
           - ReaImGui           (modern script GUI)
           - any cfillion/X-Raym scripts that catch your eye
      d) Prefs → Plug-ins → ReaScript: point Python path at:
           $TNI_VENV/lib

  5.  Overwitch (Digitakt) sanity check:
        overwitch-cli -l    # plug in Digitakt first
        overwitch-service   # starts JACK client for it

  6.  Workdir cleanup when confident:
        rm -rf "$WORKDIR"

────────────────────────────────────────────────────────────────────

EOF

# Write a machine-readable log too
LOG="$HOME/tni_install_$(date +%Y%m%d_%H%M%S).log"
{
  echo "TNI install run: $(date)"
  echo ""
  echo "INSTALLED (${#INSTALLED[@]}):"
  printf '  %s\n' "${INSTALLED[@]}"
  echo ""
  echo "FAILED PACKAGES (${#FAILED_PKGS[@]}):"
  printf '  %s\n' "${FAILED_PKGS[@]}"
  echo ""
  echo "FAILED STEPS (${#FAILED_STEPS[@]}):"
  printf '  %s\n' "${FAILED_STEPS[@]}"
  echo ""
  echo "SKIPPED STEPS (${#SKIPPED_STEPS[@]}):"
  printf '  %s\n' "${SKIPPED_STEPS[@]}"
} > "$LOG"

echo "  Full log: $LOG"
echo ""
