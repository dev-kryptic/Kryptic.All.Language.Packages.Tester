#!/usr/bin/env bash
# Runs the Kryptic package verification app for every supported language
# against the running daemon, and reports a per-language pass/fail table.
#
#   ./run-all.sh              # all languages
#   ./run-all.sh node python  # a subset
#
# Prerequisites: the daemon is running and signed in (`kryptic status`), and
# kryptic.json in each directory points at a project you can read.
# On a fresh machine, run ./install-deps.sh first.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

LANGUAGES=("$@")
if [[ ${#LANGUAGES[@]} -eq 0 ]]; then
  LANGUAGES=(dotnet node python go ruby java cpp rust)
fi

# Space-delimited names of languages that passed. Avoids associative arrays
# so this script runs on macOS /bin/bash 3.2 (no `declare -A`).
PASSED=" "
FAILED=0

section() { printf '\n\033[1m── %s ─────────────────────────────\033[0m\n' "$1"; }

record() {
  local language="$1" status="$2"
  if [[ "$status" == "pass" ]]; then
    PASSED="${PASSED}${language} "
  else
    FAILED=1
  fi
}

run_dotnet() {
  section ".NET"
  ( cd "$ROOT/dotnet" && dotnet run ) && record dotnet pass || record dotnet fail
}

run_node() {
  section "Node.js"
  ( cd "$ROOT/node" && npm install --silent && node index.js ) && record node pass || record node fail
}

run_python() {
  section "Python"
  (
    cd "$ROOT/python"
    if [[ -d .venv && ! -x .venv/bin/pip ]]; then
      rm -rf .venv
    fi
    if ! python3 -m venv .venv; then
      echo "python3 -m venv failed. On Ubuntu/Debian: sudo apt install python3-venv python3-pip" >&2
      exit 1
    fi
    if [[ ! -x .venv/bin/pip ]]; then
      python3 -m venv --clear --upgrade-deps .venv >/dev/null 2>&1 || true
    fi
    if [[ ! -x .venv/bin/pip ]]; then
      echo "venv has no pip. On Ubuntu/Debian: sudo apt install python3-venv python3-pip" >&2
      exit 1
    fi
    ./.venv/bin/pip install --quiet --upgrade -r requirements.txt
    ./.venv/bin/python main.py
  ) && record python pass || record python fail
}

run_go() {
  section "Go"
  ( cd "$ROOT/go" && go run . ) && record go pass || record go fail
}

run_ruby() {
  section "Ruby"
  (
    cd "$ROOT/ruby"
    if command -v gem >/dev/null 2>&1; then
      gem install bundler --no-document --user-install >/dev/null 2>&1 \
        || gem install bundler --no-document >/dev/null 2>&1 \
        || true
      gem_bin="$(ruby -e 'print Gem.user_dir' 2>/dev/null)/bin"
      if [[ -d "$gem_bin" ]]; then
        export PATH="$gem_bin:$PATH"
      fi
    fi
    if command -v bundle >/dev/null 2>&1; then
      bundle install --quiet && bundle exec ruby main.rb
    else
      gem install --user-install --no-document kryptic-daemon-client --version 0.1.3 \
        || gem install --no-document kryptic-daemon-client --version 0.1.3
      ruby main.rb
    fi
  ) && record ruby pass || record ruby fail
}

run_java() {
  section "Java"
  ( cd "$ROOT/java" && mvn -q compile exec:java ) && record java pass || record java fail
}

run_cpp() {
  section "C++"
  (
    cd "$ROOT/cpp"
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build build
    ./build/kryptic-test-runner
  ) && record cpp pass || record cpp fail
}

run_rust() {
  section "Rust"
  (
    if [[ -f "$HOME/.cargo/env" ]]; then
      # rustup puts cargo here; a new login is not required.
      # shellcheck disable=SC1091
      . "$HOME/.cargo/env"
    fi
    if ! command -v cargo >/dev/null 2>&1; then
      echo "cargo not found. Run ./install-deps.sh rust" >&2
      exit 1
    fi
    cd "$ROOT/rust" && cargo run --quiet
  ) && record rust pass || record rust fail
}

for language in "${LANGUAGES[@]}"; do
  case "$language" in
    dotnet) run_dotnet ;;
    node)   run_node ;;
    python) run_python ;;
    go)     run_go ;;
    ruby)   run_ruby ;;
    java)   run_java ;;
    cpp)    run_cpp ;;
    rust)   run_rust ;;
    *)      echo "unknown language: $language" >&2; exit 2 ;;
  esac
done

section "Summary"
for language in "${LANGUAGES[@]}"; do
  if [[ "$PASSED" == *" ${language} "* ]]; then
    printf '  \033[32m[ok]\033[0m   %s\n' "$language"
  else
    printf '  \033[31m[fail]\033[0m %s\n' "$language"
  fi
done

exit $FAILED
