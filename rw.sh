codex review --base main > REVIEW.txt 2>&1 
claude --permission-mode acceptEdits -p "Look at the review comments in REVIEW.txt. Fix them if they make sense. If you made changes, commit them with an explanation of what you did, but don't include the REVIEW.txt"

