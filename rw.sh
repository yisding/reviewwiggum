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

if [ "$MODE" = "review" ]; then
  FOLDER_NAME=$(basename "$PWD")
  REVIEW_DIR="../REVIEW"
  mkdir -p "$REVIEW_DIR"
  echo "Review-only mode. Outputs -> $REVIEW_DIR/${FOLDER_NAME}-N.txt"

  while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
    iteration=$((iteration + 1))
    echo "=== Review iteration $iteration ==="

    OUTPUT_FILE="$REVIEW_DIR/${FOLDER_NAME}-${iteration}.txt"

    # Alternate: Claude on odd iterations, Codex on even.
    # Fall back to Claude if codex isn't installed.
    if [ $((iteration % 2)) -eq 1 ] || ! command -v codex >/dev/null 2>&1; then
      echo "Running Claude review -> $OUTPUT_FILE"
      claude --permission-mode auto -p "/review" > "$OUTPUT_FILE" 2>&1
    else
      echo "Running Codex review -> $OUTPUT_FILE"
      codex review --base "$BASE_BRANCH" > "$OUTPUT_FILE" 2>&1
    fi
  done

  echo "Copying this folder's review files from $REVIEW_DIR into ./REVIEW"
  rm -rf ./REVIEW
  mkdir -p ./REVIEW
  cp "$REVIEW_DIR/${FOLDER_NAME}"-*.txt ./REVIEW/

  echo "Consolidating reviews into REVIEW.txt"
  claude --permission-mode auto -p "Read every review file in the REVIEW/ directory and consolidate them into a single, well-organized code review. Group related comments, deduplicate overlapping feedback from different reviewers, make sure the comments make sense, and write the consolidated code review to REVIEW.txt."

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

