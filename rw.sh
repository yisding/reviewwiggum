MAX_ITERATIONS=5
iteration=0

while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
  iteration=$((iteration + 1))
  echo "=== Review iteration $iteration ==="

  head_before=$(git rev-parse HEAD)

  codex review --base main > REVIEW.txt 2>&1
  claude --permission-mode acceptEdits -p "Look at the review comments in REVIEW.txt. Fix them if they make sense. If you made changes, commit them with an explanation of what you did, but don't include the REVIEW.txt in the commit."

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

