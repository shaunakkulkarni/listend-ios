#!/usr/bin/env bash
#
# Guards the iOS 26-safe FoundationModels path.
#
# The shipping app target must only use plain FoundationModels text responses
# with local parsing and validation. Referencing the newer structured
# generation convenience APIs anywhere in the binary has crashed iOS 26
# TestFlight builds at launch with unresolved symbols, even behind #available
# checks. This scan fails if any of those symbols reappear in app or test
# Swift source.
#
# Usage: scripts/check-foundationmodels-symbols.sh   (run from the repo root)

set -u

cd "$(dirname "$0")/.." || exit 2

if ! command -v rg >/dev/null 2>&1; then
    echo "error: ripgrep (rg) is required for this check" >&2
    exit 2
fi

PATTERN='FOUNDATION_MODELS_GUIDED_GENERATION|@Generable|@Guide|Generable|respond\(to:.*generating|streamResponse\(to:.*generating|DynamicGenerationSchema|GenerationSchema|promptRepresentation|GeneratedContent|guided schema'

rg -n "$PATTERN" \
    Listend/Listend Listend/ListendTests \
    -g '*.swift'
status=$?

if [ "$status" -eq 0 ]; then
    echo "" >&2
    echo "FAIL: unsafe FoundationModels guided-generation references found (see above)." >&2
    echo "The iOS 26 shipping target must stay on plain text responses + local parsing." >&2
    exit 1
elif [ "$status" -eq 1 ]; then
    echo "OK: no unsafe FoundationModels guided-generation references in Swift source."
    exit 0
else
    echo "error: rg failed with status $status" >&2
    exit "$status"
fi
