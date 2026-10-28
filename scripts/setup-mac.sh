#!/usr/bin/env bash
# One-step Mac setup: checks the tools, builds the Rust core for iOS, generates the
# Xcode project with XcodeGen and opens it. Run from anywhere in the repo:
#   scripts/setup-mac.sh            (team ID asked once, or set MELDE_TEAM_ID)
#   MELDE_TEAM_ID=ABCDE12345 scripts/setup-mac.sh
# Safe to re-run after pulling changes.
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: run this on the Mac." >&2
  exit 1
fi
root="$(cd "$(dirname "$0")/.." && pwd)"

step() { printf '\n\033[1m› %s\033[0m\n' "$1"; }

step "Xcode"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is missing or not selected. Install Xcode 26 from the App Store, open it once," >&2
  echo "then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi
xcodebuild -version | head -1

step "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is missing. Install it from https://brew.sh, then run this script again." >&2
  exit 1
fi

step "XcodeGen"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen --version

step "Rust"
# Homebrew's rustup is keg-only and no longer ships rustup-init: its cargo/rustc/rustup
# proxies live in the keg's bin, so put that on PATH and install the toolchain directly.
if ! command -v cargo >/dev/null 2>&1; then
  brew list rustup >/dev/null 2>&1 || brew install rustup
  export PATH="$(brew --prefix rustup)/bin:$PATH"
fi
command -v rustup >/dev/null 2>&1 && ! rustup default >/dev/null 2>&1 && rustup default stable
cargo --version
if [[ ":$PATH:" == *":$(brew --prefix rustup 2>/dev/null)/bin:"* ]] && ! grep -q 'opt/rustup/bin' "$HOME/.zshrc" 2>/dev/null; then
  echo "Tip: add Rust to new shells with:"
  echo "  echo 'export PATH=\"$(brew --prefix rustup)/bin:\$PATH\"' >> ~/.zshrc"
fi

step "Rust core for iOS (first run takes a few minutes)"
git -C "$root" submodule update --init
"$root/scripts/build-rust-ios.sh"

step "Signing team"
# project.yml reads the Apple Developer team from MELDE_TEAM_ID. Without one the
# project still opens; pick the team in Xcode under Signing & Capabilities.
if [[ -z "${MELDE_TEAM_ID:-}" ]]; then
  read -r -p "Apple Developer Team ID (Enter to skip, set it in Xcode later): " MELDE_TEAM_ID || true
fi
export MELDE_TEAM_ID="${MELDE_TEAM_ID:-}"

step "Xcode project"
cd "$root"
xcodegen generate
open MeldePlanner.xcodeproj
echo
echo "Done. In Xcode pick the MeldePlanner scheme and an iOS 26 simulator or your iPhone, then Run (⌘R)."
