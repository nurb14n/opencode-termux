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
TOTAL_STEPS=7

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

step 3 "Downloading opencode binary"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
curl -fL --progress-bar -o "$TMP_DIR/opencode" "${BASE_URL}/opencode"

step 4 "Downloading checksum file"
curl -fL --progress-bar -o "$TMP_DIR/SHA256SUMS" "${BASE_URL}/SHA256SUMS"

step 5 "Verifying SHA256 checksum"
actual="$(sha256sum "$TMP_DIR/opencode" | awk '{print $1}')"
expected="$(awk '$2 == "opencode" { print $1; exit }' "$TMP_DIR/SHA256SUMS" || true)"

echo "    expected: ${expected:-<missing>}"
echo "    actual:   $actual"

if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
  echo "Error: checksum verification failed" >&2
  exit 1
fi
echo "    checksum OK"

step 6 "Installing binary"
mkdir -p "${PREFIX_DIR}/bin"
install -m755 "$TMP_DIR/opencode" "${PREFIX_DIR}/bin/opencode"

step 7 "Checking optional dependencies"
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
