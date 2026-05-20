#!/usr/bin/env bash
trap 'echo "Interrupted"; exit 130' INT

if [ -n "$RW_BASE_BRANCH" ]; then
  BASE_BRANCH="$RW_BASE_BRANCH"
elif command -v gh >/dev/null 2>&1; then
  BASE_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
fi
BASE_BRANCH="${BASE_BRANCH:-main}"
echo "Using base branch: $BASE_BRANCH"

MAX_ITERATIONS="${RW_MAX_ITERATIONS:-5}"
MODE="${RW_MODE:-fix}"
iteration=0

# Codex emits a large amount of progress/thinking output before the actual
# review. Keep only the final "Full review comments:" section so the file
# stays small. Match strictly: a blank line, a line that is exactly
# "Full review comments:", and a blank line after it.
trim_codex_output() {
  file="$1"
  last_line=$(awk '
    NR >= 3 && pp == "" && p == "Full review comments:" && $0 == "" { match_line = NR - 1 }
    { pp = p; p = $0 }
    END { if (match_line) print match_line }
  ' "$file")
  if [ -n "$last_line" ]; then
    tail -n +"$last_line" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
}

if [ "$MODE" = "review" ]; then
  FOLDER_NAME=$(basename "$PWD")
  # Use a per-repo subdirectory so sibling repos whose names share a hyphenated
  # prefix (e.g. `api` vs `api-server`) can't clobber each other's review files
  # via prefix-glob matching.
  REVIEW_DIR="../REVIEW/$FOLDER_NAME"
  mkdir -p "$REVIEW_DIR"
  # Clear out leftover iteration files from previous runs of this folder so
  # higher-numbered stale files don't get consolidated into REVIEW.txt. Match
  # any fully-numeric <N>.txt (not just 1..MAX_ITERATIONS) so reducing
  # RW_MAX_ITERATIONS between runs still purges older higher-numbered files,
  # while unrelated *.txt the user keeps in $REVIEW_DIR is preserved.
  for f in "$REVIEW_DIR"/*.txt; do
    [ -e "$f" ] || continue
    stem=$(basename "$f" .txt)
    case "$stem" in
      ''|*[!0-9]*) ;;
      *) rm -f "$f" ;;
    esac
  done
  echo "Review-only mode. Outputs -> $REVIEW_DIR/N.txt"

  while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
    iteration=$((iteration + 1))
    echo "=== Review iteration $iteration ==="

    OUTPUT_FILE="$REVIEW_DIR/${iteration}.txt"

    # Alternate: Claude on odd iterations, Codex on even.
    # Fall back to Claude if codex isn't installed.
    if [ $((iteration % 2)) -eq 1 ] || ! command -v codex >/dev/null 2>&1; then
      echo "Running Claude review -> $OUTPUT_FILE"
      claude --permission-mode auto -p "/review" > "$OUTPUT_FILE" 2>&1
    else
      echo "Running Codex review -> $OUTPUT_FILE"
      codex review --base "$BASE_BRANCH" > "$OUTPUT_FILE" 2>&1
      trim_codex_output "$OUTPUT_FILE"
    fi
  done

  echo "Consolidating reviews into REVIEW.txt"
  # Consolidate directly from $REVIEW_DIR (the per-repo subdirectory this
  # script owns under ../REVIEW). The previous design mirrored files into a
  # local ./REVIEW directory first, which required deleting any pre-existing
  # numeric <N>.txt to avoid stale entries — risking data loss if the user
  # already kept numeric .txt files there. Reading the originals in place
  # avoids touching ./REVIEW at all.
  claude --permission-mode auto -p "Read every review file in the directory $REVIEW_DIR (a path relative to the current working directory) and consolidate them into a single, well-organized code review. Group related comments, deduplicate overlapping feedback from different reviewers, make sure the comments make sense, and write the consolidated code review to ./REVIEW.txt."

  exit 0
fi

while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
  iteration=$((iteration + 1))
  echo "=== Review iteration $iteration ==="

  head_before=$(git rev-parse HEAD)

  if [ "$USE_AGENT" = "claude" ] || ! command -v codex >/dev/null 2>&1; then
    claude --permission-mode auto -p "/review" > REVIEW.txt 2>&1
  else
    codex review --base "$BASE_BRANCH" > REVIEW.txt 2>&1
    trim_codex_output REVIEW.txt
  fi
  claude --allowed-tools "Bash(git:*) Edit" -p "Look at the review comments in REVIEW.txt. Fix them if they make sense. If you made changes, commit them with an explanation of what you did, but don't include the REVIEW.txt in the commit."

  head_after=$(git rev-parse HEAD)

  if [ "$head_before" = "$head_after" ]; then
    echo "No changes made — no more actionable comments. Done."
    break
  fi

  echo "Changes committed, re-reviewing..."
done

if [ "$iteration" -eq "$MAX_ITERATIONS" ]; then
  echo "Reached max iterations ($MAX_ITERATIONS). Stopping."
fi

