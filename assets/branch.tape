# Regenerate from the repo root: vhs assets/branch.tape
# Uses demo mode only: fictional data, no Linear account, no network calls to Linear.
# Captions and the key display come from assets/demo-init.lua.

Output assets/branch.gif

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
Type "NVIM_APPNAME=linear-demo DEMO=branch nvim -u assets/demo-init.lua"
Enter
Sleep 2s
Show

# 1. Intro
Sleep 2.5s

# 2. Open by id
Type " io"
Sleep 1.5s
Type "acme-105"
Sleep 1.5s

# 3. Open it
Enter
Sleep 3.5s

# 4. Issue of the current branch
Type " ib"
Sleep 4s

Hide
Type ":qa!"
Enter
