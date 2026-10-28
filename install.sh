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
TMP_DIR="${TMPDIR:-/tmp}/opencode-install-$$"

echo "==> opencode for Termux (Android/Bionic)"
echo "    prefix: ${PREFIX_DIR}"

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

for cmd in curl tar sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Error: '$cmd' not found (pkg install $cmd)" >&2; exit 1; }
done

mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

BASE_URL="https://github.com/${REPO}/releases/latest/download"
echo "==> downloading opencode + checksums..."
curl -fsSL "${BASE_URL}/opencode" -o "$TMP_DIR/opencode"
curl -fsSL "${BASE_URL}/SHA256SUMS" -o "$TMP_DIR/SHA256SUMS"

echo "==> verifying checksum..."
# Portable hash comparison (works with GNU coreutils and BusyBox).
actual="$(sha256sum "$TMP_DIR/opencode" | awk '{print $1}')"
expected="$(grep -E ' opencode$' "$TMP_DIR/SHA256SUMS" | awk '{print $1}')"
if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
  echo "Error: checksum verification failed" >&2
  echo "  expected: ${expected:-<missing>}" >&2
  echo "  actual:   $actual" >&2
  exit 1
fi
echo "    checksum OK"

echo "==> installing to ${PREFIX_DIR}/bin/opencode..."
install -m755 "$TMP_DIR/opencode" "${PREFIX_DIR}/bin/opencode"

echo "==> checking dependencies..."
missing=0
command -v rg >/dev/null || { echo "    [!] ripgrep missing (file search needs it): pkg install ripgrep"; missing=1; }
command -v git >/dev/null || { echo "    [!] git missing (recommended): pkg install git"; missing=1; }
command -v ssh >/dev/null || { echo "    [!] openssh missing (needed for SSH sessions): pkg install openssh"; missing=1; }
[ "$missing" -eq 0 ] && echo "    all optional dependencies present"

echo "==> verifying..."
"${PREFIX_DIR}/bin/opencode" --version

echo ""
echo "Done. Run 'opencode' in your project directory."
echo "First run: use /connect in the TUI to sign in to a provider."
