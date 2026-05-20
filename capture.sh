#!/bin/bash
# Thought Capture — triggered by macOS Shortcuts
# Gets selected text, shows input dialog, sends to server

SERVER="http://127.0.0.1:19876"

# Get frontmost app name
APP_NAME=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "Unknown")

# Get window title
WINDOW_TITLE=$(osascript -e 'tell application "System Events" to get name of first window of (first application process whose frontmost is true)' 2>/dev/null || echo "")

# Save old clipboard
OLD_CLIP=$(pbpaste 2>/dev/null)

# Copy selected text via Cmd+C
osascript -e 'tell application "System Events" to keystroke "c" using command down' 2>/dev/null
sleep 0.2
NEW_CLIP=$(pbpaste 2>/dev/null)

# Only use as selected text if clipboard actually changed
SELECTED=""
if [ "$NEW_CLIP" != "$OLD_CLIP" ]; then
    SELECTED="$NEW_CLIP"
fi

# Build prompt — escape quotes for AppleScript
ESCAPED_APP=$(echo "$APP_NAME" | sed 's/"/\\"/g')
if [ -n "$SELECTED" ]; then
    SHORT=$(echo "$SELECTED" | head -c 80 | tr '\n' ' ' | sed 's/"/\\"/g')
    PROMPT_MSG="${ESCAPED_APP} — \"${SHORT}\""
else
    ESCAPED_TITLE=$(echo "$WINDOW_TITLE" | sed 's/"/\\"/g')
    PROMPT_MSG="${ESCAPED_APP} — ${ESCAPED_TITLE}"
fi

# Show input dialog
THOUGHT=$(osascript <<EOF
try
    set userInput to display dialog "$PROMPT_MSG" default answer "" buttons {"Cancel", "Save"} default button "Save" with title "Thought Capture" giving up after 120
    if button returned of userInput is "Save" then
        return text returned of userInput
    end if
on error
    return ""
end try
EOF
)

# Exit if empty or cancelled
if [ -z "$THOUGHT" ]; then
    # Restore clipboard
    echo -n "$OLD_CLIP" | pbcopy 2>/dev/null
    exit 0
fi

# Build JSON payload safely using python
PAYLOAD=$(/opt/homebrew/bin/python3 -c "
import json, sys
print(json.dumps({
    'input': sys.argv[1],
    'selectedText': sys.argv[2] if sys.argv[2] else None,
    'url': f'app://{sys.argv[3]}',
    'title': sys.argv[4] or sys.argv[3],
    'pageDescription': '',
    'source': 'global',
    'app': sys.argv[3],
}))
" "$THOUGHT" "$SELECTED" "$APP_NAME" "$WINDOW_TITLE")

# Send to server
RESULT=$(curl -s -X POST "$SERVER/handle" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    --connect-timeout 3 \
    --max-time 10 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
    MSG=$(/opt/homebrew/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('message','saved'))" <<< "$RESULT" 2>/dev/null)
    SAVED=$(/opt/homebrew/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('savedTo',''))" <<< "$RESULT" 2>/dev/null)
    osascript -e "display notification \"${MSG} → ${SAVED}\" with title \"Thought Capture\"" 2>/dev/null
else
    osascript -e 'display notification "Server offline" with title "Thought Capture"' 2>/dev/null
fi

# Restore clipboard
echo -n "$OLD_CLIP" | pbcopy 2>/dev/null
