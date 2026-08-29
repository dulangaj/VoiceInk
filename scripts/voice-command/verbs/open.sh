#!/bin/zsh
#
# "open slack" -> opens Slack.app
#
# Matches the spoken name against installed bundles: an exact name wins
# outright, otherwise the shortest name containing it.

set -euo pipefail

HERE="${0:A:h}"
query="${1:-}"

notify() {
    osascript -e "display notification \"$1\" with title \"Voice Command\"" >/dev/null 2>&1 || true
    print -r -- "$1" >&2
}

# "open up slack" is the same request as "open slack".
query="${query#up }"
[[ -n $query ]] || { notify "Open what?"; exit 1; }

# Compare on letters and digits alone, so spacing and punctuation never matter.
squash() { print -r -- "${${1:l}//[^a-z0-9]/}" }

# A spoken name that shares no letters with the bundle name needs a hint,
# e.g. "vs code=Visual Studio Code".
if [[ -f $HERE/open.aliases ]]; then
    aliased="$(sed -n "s/^$query=//p" "$HERE/open.aliases" | head -1)"
    [[ -n $aliased ]] && query="$aliased"
fi

target="$(squash "$query")"

candidates=(
    /Applications/*.app(N)
    /Applications/*/*.app(N)
    /System/Applications/*.app(N)
    /System/Applications/*/*.app(N)
    ~/Applications/*.app(N)
    ~/Applications/*/*.app(N)
)

# Spotlight covers bundles outside the usual folders; only worth the latency
# when the cheap globs came up empty.
#
# Among partial matches the shortest name wins: "chrome" should reach Google
# Chrome rather than Chrome Remote Desktop, which merely starts with the word.
match_in() {
    local best= best_len=0 path name
    for path in "$@"; do
        name="$(squash "${${path:t}%.app}")"
        if [[ $name == $target ]]; then
            print -r -- "$path"
            return 0
        elif [[ $name == *$target* ]] && { [[ -z $best ]] || (( ${#name} < best_len )) }; then
            best="$path"
            best_len=${#name}
        fi
    done
    [[ -n $best ]] || return 1
    print -r -- "$best"
}

app="$(match_in $candidates)" || app="$(match_in ${(f)"$(mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null)"})" || {
    notify "No app matching \"$query\"."
    exit 1
}

open -a "$app"
