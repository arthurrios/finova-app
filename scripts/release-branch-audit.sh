#!/bin/bash
# Release branch audit: list fix commits on older release branches that the newest one lacks.
#
# The 1.6 branches were cut without 2af396c, a fix(ci) commit that only lived on 1.5.x. The result
# was iOS 1.6.1 crashing at launch for every App Store user. This lists every `fix` commit on an
# older release branch whose change is not in the newest release branch, so nothing is left
# behind silently.
#
# A commit counts as present in the target when any of these is true:
#   - it is an ancestor of the target;
#   - the target has a commit with the same patch (git cherry);
#   - the target has a commit with the same subject line (a cherry-pick that needed conflict fixes);
#   - a target commit says "(cherry picked from commit <sha>)".
# Commits reviewed and deliberately not carried forward go in ci/release-audit-reviewed.txt.
#
# Usage: scripts/release-branch-audit.sh [--target <ref>] [--remote origin] [--all]
#   --target  branch to check (default: the highest release/vX.Y.Z on the remote)
#   --all     scan every older release branch, not only the previous minor line and the
#             target's own earlier patches
# Exit 1 when unreviewed missing fixes exist.

set -euo pipefail

REMOTE=origin
TARGET=""
SCAN_ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --remote) REMOTE="$2"; shift 2 ;;
        --all) SCAN_ALL=1; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1"; exit 2 ;;
    esac
done

REPO="$(git rev-parse --show-toplevel)"
REVIEWED="$REPO/ci/release-audit-reviewed.txt"

# Release branches named exactly release/vX.Y.Z, sorted by version.
BRANCHES=$(git for-each-ref --format='%(refname:strip=4)' "refs/remotes/$REMOTE/release/" \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V || true)
[ -n "$BRANCHES" ] || { echo "No release/vX.Y.Z branches on $REMOTE. Run git fetch first."; exit 2; }

if [ -z "$TARGET" ]; then
    TARGET="$REMOTE/release/$(echo "$BRANCHES" | tail -n 1)"
fi
TARGET_VERSION=$(echo "$TARGET" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1 || true)
[ -n "$TARGET_VERSION" ] || { echo "Cannot read a version from target $TARGET"; exit 2; }
IFS=. read -r T_MAJOR T_MINOR _ <<< "${TARGET_VERSION#v}"

# Which older branches to scan.
SOURCES=()
for b in $BRANCHES; do
    [ "$b" = "$TARGET_VERSION" ] && continue
    # Only versions below the target.
    [ "$(printf '%s\n%s\n' "$b" "$TARGET_VERSION" | sort -V | head -n 1)" = "$b" ] || continue
    IFS=. read -r MAJOR MINOR _ <<< "${b#v}"
    if [ "$SCAN_ALL" = "1" ] || { [ "$MAJOR" = "$T_MAJOR" ] && [ $((T_MINOR - MINOR)) -le 1 ]; }; then
        SOURCES+=("$REMOTE/release/$b")
    fi
done

echo "Target: $TARGET"
echo "Scanning: ${SOURCES[*]:-(none)}"
echo

# What the target already has, by subject and by cherry-pick note.
TARGET_SUBJECTS=$(git log --format='%s' "$TARGET")
TARGET_PICKED=$(git log --format='%b' "$TARGET" | grep -oE 'cherry picked from commit [0-9a-f]+' | awk '{print $5}' || true)
REVIEWED_SHAS=""
if [ -f "$REVIEWED" ]; then
    REVIEWED_SHAS=$(sed 's/#.*//' "$REVIEWED" | awk 'NF {print $1}')
fi

is_reviewed() {
    local sha="$1" r
    for r in $REVIEWED_SHAS; do
        case "$sha" in "$r"*) return 0 ;; esac
    done
    return 1
}

SEEN=""   # plain string, so this runs on macOS bash 3.2 too
MISSING=()
for src in "${SOURCES[@]}"; do
    # "+" lines: commits in src whose patch is not in TARGET.
    while read -r mark sha; do
        [ "$mark" = "+" ] || continue
        case "$SEEN" in *" $sha "*) continue ;; esac
        SEEN="$SEEN $sha "
        subject=$(git log -1 --format='%s' "$sha")
        # Conventional "fix" commits only: fix:, fix(scope):, fix!:
        echo "$subject" | grep -qE '^fix(\([^)]*\))?!?:' || continue
        grep -qxF -- "$subject" <<< "$TARGET_SUBJECTS" && continue
        grep -q "^${sha}" <<< "$TARGET_PICKED" && continue
        is_reviewed "$sha" && continue
        MISSING+=("$(git log -1 --format='%h %ad %s' --date=short "$sha")  [${src#"$REMOTE/"}]")
    done < <(git cherry "$TARGET" "$src")
done

if [ ${#MISSING[@]} -eq 0 ]; then
    echo "OK: every fix commit on the scanned branches is in $TARGET."
    exit 0
fi

echo "${#MISSING[@]} fix commit(s) on older release branches are NOT in $TARGET:"
printf '  %s\n' "${MISSING[@]}"
echo
echo "For each one, either cherry-pick it into the newest release branch, or, if the newest"
echo "branch already solves it another way, add its SHA and a reason to ci/release-audit-reviewed.txt."

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Release branch audit"
        echo
        echo "${#MISSING[@]} fix commit(s) on older release branches are not in \`$TARGET\`:"
        echo
        printf -- '- `%s`\n' "${MISSING[@]}"
    } >> "$GITHUB_STEP_SUMMARY"
fi
exit 1
