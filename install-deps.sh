#!/usr/bin/env bash
# Installs the language toolchains needed to run run-all.sh on macOS or Linux.
# Already-installed tools are skipped.
#
#   ./install-deps.sh              # every language
#   ./install-deps.sh node python  # a subset
#
# macOS uses Homebrew. Linux uses apt, dnf, yum, pacman, zypper, or apk.
# Open a new terminal after this finishes if a later command is still not found.
set -uo pipefail

VALID_LANGUAGES=(dotnet node python go ruby java cpp rust)

usage_error() {
  echo "unknown language: $1" >&2
  echo "valid: ${VALID_LANGUAGES[*]}" >&2
  exit 2
}

if [[ $# -eq 0 ]]; then
  LANGUAGES=("${VALID_LANGUAGES[@]}")
else
  LANGUAGES=("$@")
fi

for language in "${LANGUAGES[@]}"; do
  found=0
  for valid in "${VALID_LANGUAGES[@]}"; do
    if [[ "$language" == "$valid" ]]; then
      found=1
      break
    fi
  done
  if [[ $found -eq 0 ]]; then
    usage_error "$language"
  fi
done

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

want() {
  local needle="$1" lang
  for lang in "${LANGUAGES[@]}"; do
    if [[ "$lang" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

have_java() {
  have_cmd java && java -version >/dev/null 2>&1
}

have_cxx() {
  have_cmd c++ || have_cmd clang++ || have_cmd g++
}

have_python() {
  if have_cmd python3 && python3 -c 'import sys' >/dev/null 2>&1; then
    return 0
  fi
  if have_cmd python && python -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

have_clt() {
  xcode-select -p >/dev/null 2>&1
}

FAILED=()
fail() {
  FAILED+=("$1")
}

APT_UPDATED=0

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif have_cmd sudo; then
    sudo "$@"
  else
    echo "need root to install packages (sudo not found): $*" >&2
    return 1
  fi
}

persist_line() {
  local line="$1"
  local rc=""
  case "${SHELL##*/}" in
    zsh) rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *) rc="$HOME/.profile" ;;
  esac
  mkdir -p "$(dirname "$rc")"
  touch "$rc"
  if grep -Fqs "$line" "$rc"; then
    return 0
  fi
  printf '\n%s\n' "$line" >> "$rc"
  echo "  added to $rc"
}

refresh_path() {
  if have_cmd brew; then
    eval "$(brew shellenv)"
  fi
  if [[ -d "$HOME/.dotnet" ]]; then
    export DOTNET_ROOT="$HOME/.dotnet"
    export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
  fi
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  if have_cmd brew; then
    local ruby_prefix
    ruby_prefix="$(brew --prefix ruby 2>/dev/null || true)"
    if [[ -n "$ruby_prefix" && -d "$ruby_prefix/bin" ]]; then
      export PATH="$ruby_prefix/bin:$PATH"
    fi
    local java_prefix
    java_prefix="$(brew --prefix openjdk@17 2>/dev/null || true)"
    if [[ -n "$java_prefix" && -d "$java_prefix/bin" ]]; then
      export PATH="$java_prefix/bin:$PATH"
    fi
  fi
  hash -r 2>/dev/null || true
}

UNAME="$(uname -s)"
case "$UNAME" in
  MINGW*|MSYS*|CYGWIN*)
    echo "On Windows, run .\\install-deps.ps1 from PowerShell." >&2
    exit 1
    ;;
  Darwin)
    OS=macos
    ;;
  Linux)
    OS=linux
    ;;
  *)
    echo "unsupported OS: $UNAME" >&2
    exit 1
    ;;
esac

PM=""
if [[ "$OS" == macos ]]; then
  PM=brew
  if ! have_cmd brew; then
    echo "Homebrew is not on PATH. Install it from https://brew.sh then re-run this script:" >&2
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
    exit 1
  fi
  eval "$(brew shellenv)"
elif have_cmd apt-get; then
  PM=apt
elif have_cmd dnf; then
  PM=dnf
elif have_cmd yum; then
  PM=yum
elif have_cmd pacman; then
  PM=pacman
elif have_cmd zypper; then
  PM=zypper
elif have_cmd apk; then
  PM=apk
else
  echo "no supported package manager found (apt, dnf, yum, pacman, zypper, apk)." >&2
  exit 1
fi

install_packages() {
  echo "Installing $*..."
  case "$PM" in
    brew)
      brew install "$@"
      ;;
    apt)
      if [[ "$APT_UPDATED" -eq 0 ]]; then
        run_root apt-get update -y || { fail "apt-update"; return 1; }
        APT_UPDATED=1
      fi
      run_root apt-get install -y "$@"
      ;;
    dnf)
      run_root dnf install -y "$@"
      ;;
    yum)
      run_root yum install -y "$@"
      ;;
    pacman)
      run_root pacman -S --noconfirm --needed "$@"
      ;;
    zypper)
      run_root zypper --non-interactive install -y "$@"
      ;;
    apk)
      run_root apk add --no-cache "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

install_dotnet_script() {
  echo "  using the official dotnet-install script..."
  if ! have_cmd curl; then
    echo "  curl is required to install the .NET SDK" >&2
    return 1
  fi
  local script
  script="$(mktemp)"
  if ! curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$script"; then
    rm -f "$script"
    return 1
  fi
  bash "$script" --channel 10.0
  local code=$?
  rm -f "$script"
  if [[ $code -ne 0 ]]; then
    return 1
  fi
  export DOTNET_ROOT="$HOME/.dotnet"
  export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
  persist_line 'export DOTNET_ROOT="$HOME/.dotnet"'
  persist_line 'export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"'
  return 0
}

NEED_GIT=0
NEED_CXX=0
for language in "${LANGUAGES[@]}"; do
  case "$language" in
    go|cpp) NEED_GIT=1 ;;
  esac
  case "$language" in
    cpp|rust) NEED_CXX=1 ;;
  esac
done

if [[ "$OS" == macos ]] && [[ "$NEED_CXX" -eq 1 ]]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Installing Xcode Command Line Tools (a GUI prompt will appear)..."
    xcode-select --install >/dev/null 2>&1 || true
    fail "xcode-clt"
    echo "  finish the Command Line Tools installer, then re-run ./install-deps.sh"
  fi
fi

if [[ "$NEED_GIT" -eq 1 ]] && ! have_cmd git; then
  case "$PM" in
    brew) install_packages git || fail git ;;
    apt) install_packages git || fail git ;;
    dnf|yum) install_packages git || fail git ;;
    pacman) install_packages git || fail git ;;
    zypper) install_packages git || fail git ;;
    apk) install_packages git || fail git ;;
  esac
  refresh_path
fi

if want dotnet && ! have_cmd dotnet; then
  echo "Installing .NET SDK 10..."
  installed=0
  case "$PM" in
    brew)
      if brew install --cask dotnet-sdk; then
        installed=1
      fi
      ;;
    apt)
      if [[ "$APT_UPDATED" -eq 0 ]]; then
        if run_root apt-get update -y; then
          APT_UPDATED=1
        fi
      fi
      if [[ "$APT_UPDATED" -eq 1 ]] && run_root apt-get install -y dotnet-sdk-10.0; then
        installed=1
      fi
      ;;
    dnf)
      if run_root dnf install -y dotnet-sdk-10.0; then
        installed=1
      fi
      ;;
    yum)
      if run_root yum install -y dotnet-sdk-10.0; then
        installed=1
      fi
      ;;
    pacman)
      if run_root pacman -S --noconfirm --needed dotnet-sdk; then
        installed=1
      fi
      ;;
    zypper)
      if run_root zypper --non-interactive install -y dotnet-sdk-10.0; then
        installed=1
      fi
      ;;
  esac
  if [[ "$installed" -eq 0 ]]; then
    install_dotnet_script || fail dotnet
  fi
  refresh_path
fi

if want node && ! have_cmd node; then
  case "$PM" in
    brew) install_packages node || fail node ;;
    apt) install_packages nodejs npm || fail node ;;
    dnf|yum) install_packages nodejs || fail node ;;
    pacman) install_packages nodejs npm || fail node ;;
    zypper) install_packages nodejs npm || fail node ;;
    apk) install_packages nodejs npm || fail node ;;
  esac
  refresh_path
fi

if want python && ! have_python; then
  case "$PM" in
    brew) install_packages python || fail python ;;
    apt) install_packages python3 python3-venv python3-pip || fail python ;;
    dnf|yum) install_packages python3 python3-pip || fail python ;;
    pacman) install_packages python python-pip || fail python ;;
    zypper) install_packages python3 python3-pip python3-venv || fail python ;;
    apk) install_packages python3 py3-pip || fail python ;;
  esac
  refresh_path
fi

# run-all.sh uses python3 -m venv; Debian splits that into python3-venv.
# The venv module can import while ensurepip is still missing, which creates
# a venv with no pip.
if want python && have_cmd python3 && [[ "$PM" == apt ]]; then
  if ! python3 -c "import ensurepip" >/dev/null 2>&1; then
    install_packages python3-venv python3-pip || fail python3-venv
  fi
fi

if want go && ! have_cmd go; then
  case "$PM" in
    brew) install_packages go || fail go ;;
    apt) install_packages golang-go || fail go ;;
    dnf|yum) install_packages golang || fail go ;;
    pacman) install_packages go || fail go ;;
    zypper) install_packages go || fail go ;;
    apk) install_packages go || fail go ;;
  esac
  refresh_path
fi

if want ruby && ! have_cmd ruby; then
  case "$PM" in
    brew) install_packages ruby || fail ruby ;;
    apt) install_packages ruby ruby-dev || fail ruby ;;
    dnf|yum) install_packages ruby ruby-devel || fail ruby ;;
    pacman) install_packages ruby || fail ruby ;;
    zypper) install_packages ruby ruby-devel || fail ruby ;;
    apk) install_packages ruby ruby-dev || fail ruby ;;
  esac
  refresh_path
fi

if want ruby && have_cmd ruby && ! have_cmd bundle; then
  echo "Installing bundler..."
  if have_cmd gem; then
    if gem install bundler --no-document; then
      refresh_path
    elif gem install bundler --no-document --user-install; then
      gem_bin="$(ruby -e 'print Gem.user_dir' 2>/dev/null)/bin"
      if [[ -d "$gem_bin" ]]; then
        export PATH="$gem_bin:$PATH"
        persist_line "export PATH=\"$gem_bin:\$PATH\""
      fi
    else
      fail bundler
    fi
  else
    case "$PM" in
      apt) install_packages ruby-bundler || fail bundler ;;
      dnf|yum) install_packages rubygem-bundler || fail bundler ;;
      pacman) install_packages ruby-bundler || fail bundler ;;
      zypper) install_packages ruby-bundler || fail bundler ;;
      apk) install_packages ruby-bundler || fail bundler ;;
      *) fail bundler ;;
    esac
  fi
fi

if want java && ! have_java; then
  case "$PM" in
    brew)
      echo "Installing Temurin JDK 17..."
      if brew install --cask temurin@17; then
        true
      elif brew install openjdk@17; then
        persist_line "export PATH=\"$(brew --prefix openjdk@17)/bin:\$PATH\""
      else
        fail java
      fi
      ;;
    apt) install_packages openjdk-17-jdk || fail java ;;
    dnf|yum) install_packages java-17-openjdk-devel || fail java ;;
    pacman) install_packages jdk17-openjdk || fail java ;;
    zypper) install_packages java-17-openjdk-devel || fail java ;;
    apk) install_packages openjdk17-jdk || fail java ;;
  esac
  refresh_path
fi

if want java && ! have_cmd mvn; then
  case "$PM" in
    brew) install_packages maven || fail maven ;;
    apt) install_packages maven || fail maven ;;
    dnf|yum) install_packages maven || fail maven ;;
    pacman) install_packages maven || fail maven ;;
    zypper) install_packages maven || fail maven ;;
    apk) install_packages maven || fail maven ;;
  esac
  refresh_path
fi

if want cpp && ! have_cmd cmake; then
  case "$PM" in
    brew) install_packages cmake || fail cmake ;;
    apt) install_packages cmake || fail cmake ;;
    dnf|yum) install_packages cmake || fail cmake ;;
    pacman) install_packages cmake || fail cmake ;;
    zypper) install_packages cmake || fail cmake ;;
    apk) install_packages cmake || fail cmake ;;
  esac
  refresh_path
fi

if [[ "$NEED_CXX" -eq 1 ]] && ! have_cxx && [[ "$OS" == linux ]]; then
  case "$PM" in
    apt) install_packages g++ make build-essential || fail g++ ;;
    dnf|yum) install_packages gcc-c++ make || fail g++ ;;
    pacman) install_packages gcc make || fail g++ ;;
    zypper) install_packages gcc-c++ make || fail g++ ;;
    apk) install_packages g++ make || fail g++ ;;
  esac
  refresh_path
fi

if want rust; then
  if ! have_cmd rustup && ! have_cmd cargo; then
    echo "Installing Rustup..."
    if ! have_cmd curl; then
      case "$PM" in
        brew) install_packages curl || true ;;
        apt) install_packages curl ca-certificates || true ;;
        dnf|yum) install_packages curl ca-certificates || true ;;
        pacman) install_packages curl ca-certificates || true ;;
        zypper) install_packages curl ca-certificates || true ;;
        apk) install_packages curl ca-certificates || true ;;
      esac
    fi
    if have_cmd curl; then
      if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable; then
        refresh_path
      else
        fail rust
      fi
    else
      fail rust
    fi
  fi
  refresh_path
  if have_cmd rustup; then
    echo "Selecting the stable Rust toolchain..."
    if ! rustup default stable; then
      fail rust-toolchain
    fi
  fi
fi

refresh_path

echo ""
echo "── Toolchain check ─────────────────────────────"

write_check() {
  local label="$1"
  local ok="$2"
  if [[ "$ok" -eq 1 ]]; then
    printf '  \033[32m[ok]\033[0m   %s\n' "$label"
  else
    printf '  \033[33m[miss]\033[0m %s\n' "$label"
  fi
}

bool() {
  if "$@"; then
    echo 1
  else
    echo 0
  fi
}

if want dotnet; then write_check dotnet "$(bool have_cmd dotnet)"; fi
if want node; then write_check node "$(bool have_cmd node)"; fi
if want python; then write_check python "$(bool have_python)"; fi
if want go; then write_check go "$(bool have_cmd go)"; fi
if want ruby; then write_check ruby "$(bool have_cmd ruby)"; fi
if want java; then
  write_check java "$(bool have_java)"
  write_check mvn "$(bool have_cmd mvn)"
fi
if want cpp; then
  write_check cmake "$(bool have_cmd cmake)"
  if [[ "$OS" == macos ]]; then
    write_check "xcode-clt" "$(bool have_clt)"
  else
    write_check "g++/clang++" "$(bool have_cxx)"
  fi
fi
if want rust; then write_check cargo "$(bool have_cmd cargo)"; fi
if [[ "$NEED_GIT" -eq 1 ]]; then write_check git "$(bool have_cmd git)"; fi

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Failed to install: ${FAILED[*]}" >&2
  echo "Fix those, open a new terminal, and re-run ./install-deps.sh" >&2
  exit 1
fi

echo "Toolchains are ready. Run ./run-all.sh (new terminal if a command is still missing)."
exit 0
