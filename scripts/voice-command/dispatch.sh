#!/bin/zsh
#
# Routes a spoken command to a verb handler in verbs/.
#
# Input: $VOICEINK_TRANSCRIPT, else $1, else stdin.
# A command is "<verb> <argument>", e.g. "open slack".
#
# To add a verb, drop an executable verbs/<verb>.sh that takes the argument as
# $1. Spoken synonyms go in verbs/aliases as "spoken=verb" lines.

set -euo pipefail

HERE="${0:A:h}"
VERBS="$HERE/verbs"

notify() {
    osascript -e "display notification \"$1\" with title \"Voice Command\"" >/dev/null 2>&1 || true
    print -r -- "$1" >&2
}

transcript="${VOICEINK_TRANSCRIPT:-${1:-}}"
[[ -n $transcript ]] || transcript="$(cat)"

# Speech arrives capitalised and punctuated; reduce it to bare lowercase words.
phrase="${transcript:l}"
phrase="${phrase//[^a-z0-9 ]/ }"
phrase="${${phrase//  / }## }"
phrase="${phrase%% }"

# Wake words and politeness are noise in front of the verb.
while [[ $phrase == (hey|ok|okay|please|um|uh|voice|computer)\ * ]]; do
    phrase="${phrase#* }"
done

[[ -n $phrase ]] || { notify "Nothing to run."; exit 1; }

verb="${phrase%% *}"
argument="${phrase#$verb}"
argument="${argument## }"

# An alias maps a spoken word onto a handler that already exists.
if [[ ! -x $VERBS/$verb.sh && -f $VERBS/aliases ]]; then
    resolved="$(sed -n "s/^$verb=//p" "$VERBS/aliases" | head -1)"
    [[ -n $resolved ]] && verb="$resolved"
fi

if [[ ! -x $VERBS/$verb.sh ]]; then
    notify "Don't know how to \"$verb\"."
    exit 1
fi

exec "$VERBS/$verb.sh" "$argument"
