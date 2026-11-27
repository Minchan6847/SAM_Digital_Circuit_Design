#!/usr/bin/env bash
# Build one project's testbench with Verilator and decide PASS/FAIL
# from the exit code and the simulation log.
#
# usage: sim.sh <project_dir> <tb_top> <expect_regex>
#   expect_regex : a line that must appear in the log for the run to count as passed
#                  (e.g. '^PASS:' for self-checking TBs, '\$finish' for smoke-only TBs)
set -euo pipefail

dir=$1; top=$2; expect=$3
build=${BUILD_DIR:-$(mktemp -d)}
log="$build/sim.log"
mkdir -p "$build"

cd "$dir"
shopt -s nullglob
srcs=(*.v *.sv)

verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
  --top-module "$top" -Mdir "$build/obj" "${srcs[@]}" > "$build/build.log" 2>&1 \
  || { cat "$build/build.log"; echo "::error title=$dir::Verilator build failed"; exit 1; }

set +e
timeout 600 "$build/obj/V$top" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
set -e

status=0
if [ "$rc" -ne 0 ]; then
  echo "::error title=$dir::simulation exited with code $rc"; status=1
fi
if grep -qE '(^|[^A-Za-z])(ERROR|FAIL|FATAL)([^A-Za-z]|$)|%Error' "$log"; then
  echo "::error title=$dir::error/fail message found in simulation log"; status=1
fi
if ! grep -qE "$expect" "$log"; then
  echo "::error title=$dir::expected pattern '$expect' not found in simulation log"; status=1
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### Simulation: \`$dir\`"
    [ $status -eq 0 ] && echo "Result: ✅ pass" || echo "Result: ❌ fail"
    echo '```'; grep -E "$expect|ERROR|FAIL|FATAL|%Error" "$log" | tail -5 || true; echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit $status
