#!/usr/bin/env bash
# Synthesis sanity check with Yosys (generic gates, no PDK).
# Confirms the RTL is synthesizable, passes `check -assert`
# (no multiple drivers, combinational loops, etc.) and infers no latches.
#
# usage: synth.sh <project_dir> "<top1> [top2 ...]" [keep]
#   keep : put keep attributes on every wire. Needed for designs without output
#          ports (e.g. a CPU top with only clk/rst), which Yosys would otherwise
#          optimize down to zero cells.
#
# env:
#   YOSYS_FRONTEND=slang   (default) parse with the yosys-slang plugin (read_slang)
#   YOSYS_FRONTEND=verilog parse with Yosys's built-in read_verilog -sv
set -euo pipefail

dir=$1; tops=$2; keep=${3:-}
frontend=${YOSYS_FRONTEND:-slang}
build=${BUILD_DIR:-$(mktemp -d)}
mkdir -p "$build"

cd "$dir"
shopt -s nullglob
rtl=()
for f in *.v *.sv; do [[ $f == tb_* ]] || rtl+=("$f"); done

keep_cmd=""
[ "$keep" = "keep" ] && keep_cmd="setattr -set keep 1 w:*;"

status=0
for top in $tops; do
  log="$build/yosys_$top.log"
  stat="$build/stat_$top.txt"

  case "$frontend" in
    slang)   yosys_args=(-m slang); read_cmd="read_slang --top $top ${rtl[*]}" ;;
    verilog) yosys_args=();         read_cmd="read_verilog -sv ${rtl[*]}" ;;
    *) echo "unknown YOSYS_FRONTEND: $frontend"; exit 2 ;;
  esac

  set +e
  yosys "${yosys_args[@]}" -q -l "$log" -p "$read_cmd; hierarchy -check -top $top; proc; $keep_cmd synth -top $top; check -assert; tee -o $stat stat"
  rc=$?
  set -e

  if [ $rc -ne 0 ]; then
    grep -E 'ERROR|error:|Warning' "$log" | head -20 || true
    echo "::error title=$dir::Yosys synthesis failed for top '$top'"; status=1
    result="❌ fail"
  else
    cells=$(grep -E 'Number of cells' "$stat" | tail -1 | awk '{print $NF}' || true)
    # Inferred latches (incomplete if/case in combinational always blocks) do not
    # make synthesis fail, so look for latch cells in the synthesized netlist.
    latch_cells=$(grep -cE '\$_?(DLATCH|dlatch|adlatch|dlatchsr|DLATCHSR)' "$stat" || true)
    if [ "${latch_cells:-0}" -gt 0 ]; then
      echo "Inferred latches in '$top':"
      grep -E '\$_?(DLATCH|dlatch|adlatch|dlatchsr|DLATCHSR)' "$stat" | awk '{print "  " $1 " x" $2}' | sort -u
      # Signal names and source lines, as reported by the frontend / proc pass
      grep -iE 'latch' "$log" | grep -viE 'executing|extmapper|^ *[0-9.]+ |\$_?dlatch' | sort -u | head -20 | sed 's/^/  /' || true
      echo "::error title=$dir::latch inferred in '$top' (see job log for the signals)"
      status=1
      result="❌ latch inferred"
    else
      echo "$top: ${cells:-?} cells, no latches"
      result="✅ ${cells:-?} cells, no latches"
    fi
  fi

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "### Synthesis: \`$dir\` / \`$top\` — $result" >> "$GITHUB_STEP_SUMMARY"
  fi
done
exit $status
