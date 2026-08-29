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

declare -A RESULTS
FAILED=0

section() { printf '\n\033[1m── %s ─────────────────────────────\033[0m\n' "$1"; }

record() {
  local language="$1" status="$2"
  RESULTS[$language]=$status
  [[ "$status" == "pass" ]] || FAILED=1
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
    python3 -m venv .venv >/dev/null 2>&1
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
    if command -v bundle >/dev/null 2>&1; then
      bundle install --quiet && bundle exec ruby main.rb
    else
      gem install --silent kryptic-daemon-client --version 0.1.0
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
  ( cd "$ROOT/rust" && cargo run --quiet ) && record rust pass || record rust fail
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
  if [[ "${RESULTS[$language]}" == "pass" ]]; then
    printf '  \033[32m✓\033[0m %s\n' "$language"
  else
    printf '  \033[31m✗\033[0m %s\n' "$language"
  fi
done

exit $FAILED
