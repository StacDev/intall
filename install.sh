#!/usr/bin/env bash
set -euo pipefail

REPO="${STAC_RELEASES_REPO:-StacDev/intall}" # fallback org/repo if not set
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
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'
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
  trap 'rm -rf "${tmpdir:-}"' EXIT
  _log "Downloading $asset from $REPO ($tag)"
  _download "$url" "$tmpdir/$asset"

  tar -C "$tmpdir" -xzf "$tmpdir/$asset"

  if [[ -n "${STAC_INSTALL_DIR:-}" ]]; then
    bin_dir="$STAC_INSTALL_DIR"
    mkdir -p "$bin_dir"
  else
    # Install to ~/.stac/bin by default
    bin_dir="$HOME/.stac/bin"
    mkdir -p "$bin_dir"
  fi

  install -m 0755 "$tmpdir/stac" "$bin_dir/$BIN_NAME"
  _log "Installed to $bin_dir/$BIN_NAME"

  case :$PATH: in
    *:$bin_dir:*) 
      _log "✓ $bin_dir is already in PATH" 
      ;;
    *) 
      _log "Adding $bin_dir to PATH..."
      # Auto-update shell profiles for ~/.stac/bin
      if [[ "$bin_dir" == "$HOME/.stac/bin" ]] && [[ -z "${STAC_NO_PATH_UPDATE:-}" ]]; then
        updated_profile=""
        for profile in ~/.zshrc ~/.bashrc ~/.bash_profile ~/.profile; do
          # Create profile if it doesn't exist and matches current shell
          if [[ ! -f "$profile" ]]; then
            if [[ "$profile" == ~/.zshrc && "$SHELL" == *zsh* ]]; then
              touch "$profile"
            elif [[ "$profile" == ~/.bashrc && "$SHELL" == *bash* ]]; then
              touch "$profile"
            fi
          fi
          
          # Update existing profiles
          if [[ -f "$profile" ]]; then
            if ! grep -q "\.stac/bin\|\.stac\/bin" "$profile" 2>/dev/null; then
              echo 'export PATH="$HOME/.stac/bin:$PATH"' >> "$profile"
              updated_profile="$profile"
              _log "✓ Added to PATH in $profile"
              break
            else
              _log "✓ PATH already configured in $profile"
              updated_profile="found"
              break
            fi
          fi
        done
        
        if [[ -n "$updated_profile" && "$updated_profile" != "found" ]]; then
          _log "Run: source $updated_profile  # or restart your terminal"
        elif [[ "$updated_profile" == "found" ]]; then
          _log "PATH is already configured. You may need to restart your terminal."
        else
          _log "Add manually: export PATH=\"$bin_dir:\$PATH\""
        fi
      else
        _log "Add to PATH: export PATH=\"$bin_dir:\$PATH\""
      fi
      ;;
  esac

  _log "Run: stac --help"
}

main "$@"
