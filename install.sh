#!/data/data/com.termux/files/usr/bin/bash
# opencode-termux — one-liner installer for native Termux (Android/Bionic).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nurb14n/opencode-termux/main/install.sh | bash
#
# Respects $PREFIX (Termux). Installs the `opencode` binary from the latest
# GitHub release and verifies its SHA256 checksum before installing.
set -euo pipefail

REPO="nurb14n/opencode-termux"
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
TOTAL_STEPS=9

step() {
  echo
  echo "==> [$1/$TOTAL_STEPS] $2"
}

echo "==> opencode for Termux (Android/Bionic)"
echo "    prefix: ${PREFIX_DIR}"

step 1 "Checking environment"
if [ ! -d "$PREFIX_DIR" ]; then
  echo "Error: PREFIX directory not found: $PREFIX_DIR" >&2
  echo "This installer must run inside Termux." >&2
  exit 1
fi

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "Error: unsupported architecture: $ARCH (need aarch64)" >&2
  exit 1
fi

for cmd in curl sha256sum install mktemp; do
  command -v "$cmd" >/dev/null || {
    echo "Error: '$cmd' not found (pkg install $cmd)" >&2
    exit 1
  }
done

step 2 "Preparing temporary directory"
TMP_BASE="${TMPDIR:-${PREFIX_DIR}/tmp}"
mkdir -p "$TMP_BASE"
TMP_DIR="$(mktemp -d "${TMP_BASE}/opencode-install-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

step 3 "Downloading checksum file"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
curl -fL --progress-bar -o "$TMP_DIR/SHA256SUMS" "${BASE_URL}/SHA256SUMS"

step 4 "Reading version information"
current_version=""
if [ -x "${PREFIX_DIR}/bin/opencode" ]; then
  current_version="$("${PREFIX_DIR}/bin/opencode" --version 2>/dev/null || true)"
fi

# Best-effort query; do not fail installation if GitHub API is unavailable.
latest_version="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
  | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n 1 || true)"

echo "    current: ${current_version:-<not installed>}"
echo "    latest:  ${latest_version:-<unknown>}"

step 5 "Checking installed binary"
expected="$(awk '$2 == "opencode" { print $1; exit }' "$TMP_DIR/SHA256SUMS" || true)"
if [ -z "$expected" ]; then
  echo "Error: could not find 'opencode' entry in SHA256SUMS" >&2
  exit 1
fi

local_hash=""
if [ -x "${PREFIX_DIR}/bin/opencode" ]; then
  local_hash="$(sha256sum "${PREFIX_DIR}/bin/opencode" | awk '{print $1}')"
fi

skip_download=0
if [ -n "$local_hash" ] && [ "$local_hash" = "$expected" ]; then
  skip_download=1
  echo "    installed binary already matches release checksum"
  echo "    skipping download and install"
else
  if [ -n "$local_hash" ]; then
    echo "    installed binary differs from release; updating"
  else
    echo "    no installed binary found; installing"
  fi
fi
echo "    expected: $expected"
if [ -n "$local_hash" ]; then
  echo "    installed: $local_hash"
fi

step 6 "Downloading opencode binary"
if [ "$skip_download" -eq 0 ]; then
  if [ "${OPENCODE_AUTO_UPDATE:-}" != "1" ] && [ -r /dev/tty ]; then
    printf "    Update available. Continue? [Y/n] "
    read -r answer < /dev/tty || answer=""
    case "${answer:-Y}" in
      [Yy]*) ;;
      *)
        echo "    Update cancelled by user."
        exit 0
        ;;
    esac
  fi
  curl -fL --progress-bar -o "$TMP_DIR/opencode" "${BASE_URL}/opencode"
else
  echo "    skipped"
fi

step 7 "Verifying SHA256 checksum"
if [ "$skip_download" -eq 0 ]; then
  actual="$(sha256sum "$TMP_DIR/opencode" | awk '{print $1}')"
  echo "    actual:   $actual"
  if [ "$actual" != "$expected" ]; then
    echo "Error: checksum verification failed" >&2
    exit 1
  fi
  echo "    checksum OK"
else
  echo "    skipped (already up to date)"
fi

step 8 "Installing binary"
if [ "$skip_download" -eq 0 ]; then
  mkdir -p "${PREFIX_DIR}/bin"
  install -m755 "$TMP_DIR/opencode" "${PREFIX_DIR}/bin/opencode"
else
  echo "    skipped"
fi

step 9 "Checking optional dependencies"
missing=0
command -v rg >/dev/null || { echo "    [!] ripgrep missing (file search needs it): pkg install ripgrep"; missing=1; }
command -v git >/dev/null || { echo "    [!] git missing (recommended): pkg install git"; missing=1; }
command -v ssh >/dev/null || { echo "    [!] openssh missing (needed for SSH sessions): pkg install openssh"; missing=1; }
if [ "$missing" -eq 0 ]; then
  echo "    all optional dependencies present"
fi

echo
echo "==> Verifying installation"
"${PREFIX_DIR}/bin/opencode" --version

echo
echo "Done. Run 'opencode' in your project directory."
echo "First run: use /connect in the TUI to sign in to a provider."
