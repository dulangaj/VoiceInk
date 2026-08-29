#!/bin/zsh
#
# Checks that spoken phrases reach the right app, without launching anything.
#
# A stub "open" earlier in PATH reports the app instead of opening it, so this
# is safe to run repeatedly. Cases are "phrase => expected", where the expected
# value is a bundle name, or "-" for a phrase that should be refused.

set -uo pipefail

HERE="${0:A:h}"
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
printf '#!/bin/sh\nbasename "$2" .app\n' > "$STUB/open"
chmod +x "$STUB/open"

cases=(
    "Open Safari.=Safari"
    "open safari=Safari"
    "OPEN CHROME=Google Chrome"
    "Launch Google Chrome=Google Chrome"
    "open up terminal=Terminal"
    "Hey, open Finder=Finder"
    "open vs code=Visual Studio Code"
    "open activity monitor=Activity Monitor"
    "open phone mirroring=iPhone Mirroring"
    "open a phone mirroring=iPhone Mirroring"
    "open a phone phone mirroring=iPhone Mirroring"
    "open the calculator=Calculator"
    "open calender=Calendar"
    "open zzzznope=-"
    "frobnicate slack=-"
    "=-"
)

failures=0
for testcase in $cases; do
    phrase="${testcase%=*}"
    expected="${testcase##*=}"
    actual="$(PATH="$STUB:$PATH" VOICEINK_TRANSCRIPT="$phrase" "$HERE/dispatch.sh" 2>/dev/null </dev/null)" || actual="-"
    [[ -n $actual ]] || actual="-"

    if [[ $actual == $expected ]]; then
        print -r -- "ok       ${phrase:-(empty)} -> $actual"
    else
        print -r -- "FAIL     ${phrase:-(empty)} -> $actual (expected $expected)"
        (( failures += 1 ))
    fi
done

print -r -- ""
if (( failures )); then
    print -r -- "$failures failing"
    exit 1
fi
print -r -- "all ${#cases} passing"
