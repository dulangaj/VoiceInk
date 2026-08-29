#!/bin/zsh
#
# Picks the candidate closest to a query, for when literal matching has failed.
#
# Usage: printf 'label\tvalue\n' ... | fuzzy-match.sh "query"
#
# Scoring is on the label, letters and digits only, so spacing and punctuation
# never matter. The winner's value goes to stdout; no confident match exits 1.

set -euo pipefail

python3 -c '
import difflib, re, sys

# Below this, a wrong app is likelier than a right one, so say nothing.
CONFIDENCE = 0.62

def squash(text):
    return re.sub(r"[^a-z0-9]", "", text.lower())

query = squash(sys.argv[1])
if not query:
    sys.exit(1)

best, best_score = None, 0.0
for line in sys.stdin:
    label, _, value = line.rstrip("\n").partition("\t")
    if not label:
        continue
    score = difflib.SequenceMatcher(None, query, squash(label)).ratio()
    if score > best_score:
        best, best_score = value or label, score

if best is None or best_score < CONFIDENCE:
    sys.exit(1)
print(best)
' "$1"
