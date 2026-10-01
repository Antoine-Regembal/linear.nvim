# Regenerate the README GIF from the repo root: vhs assets/demo.tape
# Uses demo mode only: fictional data, no Linear account, no network calls to Linear.
# Captions and the key display come from assets/demo-init.lua.

Output assets/demo.gif

Require nvim

Set Shell "bash"
Set FontSize 15
Set Width 1400
Set Height 860
Set Padding 16
Set Theme "TokyoNight"
Set TypingSpeed 120ms

# Install plugins off camera
Hide
Type "NVIM_APPNAME=linear-demo nvim --headless -u assets/demo-init.lua '+Lazy! sync' +qa && clear"
Enter
Sleep 30s
Type "NVIM_APPNAME=linear-demo nvim -u assets/demo-init.lua"
Enter
Sleep 2s
Show

# 1. Intro
Sleep 2.5s

# 2. Picker sorted by sprint
Type " ii"
Sleep 3.5s

# 3. Full issue in the preview, then back to the pinned branch issue
Down
Sleep 2s
Down
Sleep 2s
Up@400ms 2
Sleep 2s

# 4. Open ACME-102
Enter
Sleep 3.5s

# 5. Linked issues picker: parent, then blocked by
Type "gr"
Sleep 2.5s
Down
Sleep 2.5s

# 6. Follow the blocked-by link to ACME-104
Enter
Sleep 3.5s

# 7. Back to ACME-102
Backspace
Sleep 3s

# 8. Parent issue
Type "gp"
Sleep 4s

Hide
Type ":qa!"
Enter
