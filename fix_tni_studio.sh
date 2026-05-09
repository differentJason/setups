#!/usr/bin/env bash
#
# fix_tni_studio.sh — cleanup for the v2 install gaps
#
# Handles:
#   1. Overwitch — install missing build deps (autopoint, gettext,
#      libsystemd-dev, libgtk-4-dev), then rebuild.
#   2. Surge XT — fetch latest .deb from GitHub releases.
#   3. Dexed — fetch latest .deb from GitHub releases.
#   4. Helm — fetch the (old) tytel.org .deb if you still want it.
#
# carla-bridges-native is dropped: noble's `carla` package already provides
# native bridges, so the separate package is gone.
# ----------------------------------------------------------------------------

set -uo pipefail

say()  { printf "\n\033[1;36m▌ %s\033[0m\n" "$*"; }
ok()   { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[1;33m!\033[0m %s\n" "$*"; }
err()  { printf "  \033[1;31m✗\033[0m %s\n" "$*"; }

WORKDIR="${HOME}/tni_install_tmp"
mkdir -p "$WORKDIR"

if [[ $EUID -eq 0 ]]; then
  echo "Run as your normal user, not root." >&2
  exit 1
fi

# ============================================================================
# 1. Overwitch — install corrected deps and rebuild
# ============================================================================
say "[1/4] Overwitch: install missing build deps"

sudo apt-get update >/dev/null
sudo apt-get install -y \
  autopoint gettext libsystemd-dev libgtk-4-dev \
  automake libtool libusb-1.0-0-dev libjack-jackd2-dev \
  libsamplerate0-dev libsndfile1-dev libjson-glib-dev \
  || warn "Some deps may have failed — continuing"
ok "Build deps refreshed"

say "[1/4] Overwitch: rebuild"
cd "$WORKDIR"
if [[ ! -d overwitch ]]; then
  git clone https://github.com/dagargo/overwitch.git
fi
cd overwitch
make clean >/dev/null 2>&1 || true
if autoreconf --install \
   && ./configure \
   && make -j"$(nproc)" \
   && sudo make install; then
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  ok "Overwitch built & installed"
  if command -v overwitch-cli >/dev/null 2>&1; then
    ok "overwitch-cli is on PATH"
  fi
else
  err "Overwitch still failing — check $WORKDIR/overwitch/config.log"
fi

# ============================================================================
# 2. Surge XT — pull latest .deb from GitHub releases
# ============================================================================
say "[2/4] Surge XT"

if dpkg -s surge-xt >/dev/null 2>&1; then
  ok "Surge XT already installed"
else
  cd "$WORKDIR"
  # Resolve latest .deb URL from GitHub releases (no token required)
  SURGE_URL=$(curl -s https://api.github.com/repos/surge-synthesizer/releases-xt/releases/latest \
    | grep -oE 'https://[^"]+linux[^"]+amd64\.deb' \
    | head -n1)
  if [[ -n "$SURGE_URL" ]]; then
    echo "  Downloading: $SURGE_URL"
    if wget -q --show-progress -O surge-xt.deb "$SURGE_URL" \
       && sudo dpkg -i surge-xt.deb; then
      sudo apt-get install -f -y >/dev/null 2>&1 || true
      ok "Surge XT installed"
    else
      err "Surge XT install failed"
    fi
  else
    err "Couldn't find Surge XT .deb in GitHub releases"
    warn "Browse manually: https://github.com/surge-synthesizer/releases-xt/releases"
  fi
fi

# ============================================================================
# 3. Dexed — pull latest .deb from GitHub releases
# ============================================================================
say "[3/4] Dexed"

if dpkg -s dexed >/dev/null 2>&1; then
  ok "Dexed already installed"
else
  cd "$WORKDIR"
  DEXED_URL=$(curl -s https://api.github.com/repos/asb2m10/dexed/releases/latest \
    | grep -oE 'https://[^"]+\.deb' \
    | head -n1)
  if [[ -n "$DEXED_URL" ]]; then
    echo "  Downloading: $DEXED_URL"
    if wget -q --show-progress -O dexed.deb "$DEXED_URL" \
       && sudo dpkg -i dexed.deb; then
      sudo apt-get install -f -y >/dev/null 2>&1 || true
      ok "Dexed installed"
    else
      err "Dexed install failed (may be no Linux .deb in latest release)"
      warn "Browse manually: https://github.com/asb2m10/dexed/releases"
    fi
  else
    warn "No .deb in latest Dexed release — alternatives:"
    warn "  - Flatpak: flatpak install flathub com.github.asb2m10.dexed"
    warn "  - Build from source: https://github.com/asb2m10/dexed"
  fi
fi

# ============================================================================
# 4. Helm — old but works; only install if you want it
# ============================================================================
say "[4/4] Helm (optional)"

if dpkg -s helm >/dev/null 2>&1; then
  ok "Helm already installed"
else
  warn "Helm hasn't been updated since 2017. Skipping by default."
  warn "If you want it: download .deb from https://tytel.org/helm/"
  warn "                then: sudo dpkg -i helm-VERSION.deb"
fi

# ============================================================================
# Done
# ============================================================================
say "Fix-up complete"
cat <<EOF

  Verify Overwitch:
    overwitch-cli -l        # plug Digitakt in first
    overwitch                # GUI, if libgtk-4 found

  Verify synths landed:
    dpkg -l | grep -E 'surge|dexed'

  If anything's still broken, paste the relevant section's output and we'll
  dig in.

EOF
