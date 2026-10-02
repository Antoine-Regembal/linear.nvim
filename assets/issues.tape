# Regenerate from the repo root: vhs assets/issues.tape
# Uses demo mode only: fictional data, no Linear account, no network calls to Linear.
# Captions and the key display come from assets/demo-init.lua.

Output assets/issues.gif

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
Type "NVIM_APPNAME=linear-demo DEMO=issues nvim -u assets/demo-init.lua"
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

# 4. Close, then only the active cycle
Escape
Sleep 1.5s
Type " ic"
Sleep 3.5s
Down
Sleep 2.5s

Hide
Type ":qa!"
Enter
