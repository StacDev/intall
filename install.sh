#!/usr/bin/env bash
set -euo pipefail

REPO="${STAC_RELEASES_REPO:-stac-app/releases}" # fallback org/repo if not set
VERSION="${STAC_VERSION:-latest}"
BIN_NAME="stac"

_err() { echo "[stac_cli] $*" >&2; }
_log() { echo "[stac_cli] $*"; }

_detect_os_arch() {
  local os arch
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) _err "Unsupported architecture: $arch"; exit 1 ;;
  esac
  echo "$os" "$arch"
}

_download() {
  local url=$1 dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    _err "curl or wget required"; exit 1
  fi
}

_latest_tag() {
  # Requires public repo
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name":\s*"\([^"]*\)".*/\1/p'
}

main() {
  local os arch tag version asset url tmpdir bin_dir
  read -r os arch < <(_detect_os_arch)

  if [[ "$VERSION" == "latest" ]]; then
    tag=$(_latest_tag)
    if [[ -z "$tag" ]]; then _err "Failed to resolve latest release"; exit 1; fi
  else
    tag="stac-cli-v${VERSION}"
  fi
  version=${tag#stac-cli-v}

  case "$os" in
    darwin|linux) asset="stac_cli_${version}_${os}_${arch}.tar.gz" ;;
    *) _err "Unsupported OS: $os"; exit 1 ;;
  esac

  url="https://github.com/${REPO}/releases/download/${tag}/${asset}"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  _log "Downloading $asset from $REPO ($tag)"
  _download "$url" "$tmpdir/$asset"

  tar -C "$tmpdir" -xzf "$tmpdir/$asset"

  if [[ -n "${STAC_INSTALL_DIR:-}" ]]; then
    bin_dir="$STAC_INSTALL_DIR"
    mkdir -p "$bin_dir"
  else
    # Prefer ~/.local/bin or /usr/local/bin
    if [[ -d "$HOME/.local/bin" ]]; then
      bin_dir="$HOME/.local/bin"
    else
      bin_dir="/usr/local/bin"
    fi
    mkdir -p "$bin_dir" || true
  fi

  install -m 0755 "$tmpdir/stac" "$bin_dir/$BIN_NAME"
  _log "Installed to $bin_dir/$BIN_NAME"

  case :$PATH: in
    *:$bin_dir:*) : ;;
    *) _log "WARNING: $bin_dir not in PATH. Add: export PATH=\"$bin_dir:\$PATH\"" ;;
  esac

  _log "Run: stac --help"
}

main "$@"
