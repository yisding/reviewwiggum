if [ -n "$RW_BASE_BRANCH" ]; then
  BASE_BRANCH="$RW_BASE_BRANCH"
elif command -v gh >/dev/null 2>&1; then
  BASE_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
fi
BASE_BRANCH="${BASE_BRANCH:-main}"
echo "Using base branch: $BASE_BRANCH"

MAX_ITERATIONS=5
iteration=0

while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
  iteration=$((iteration + 1))
  echo "=== Review iteration $iteration ==="

  head_before=$(git rev-parse HEAD)

  if command -v codex >/dev/null 2>&1; then
    codex review --base "$BASE_BRANCH" > REVIEW.txt 2>&1
  else
    claude --permission-mode auto -p "/review" > REVIEW.txt 2>&1
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

