# Regenerate from the repo root: vhs assets/navigate.tape
# Uses demo mode only: fictional data, no Linear account, no network calls to Linear.
# Captions and the key display come from assets/demo-init.lua.

Output assets/navigate.gif

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
Type "NVIM_APPNAME=linear-demo DEMO=navigate nvim -u assets/demo-init.lua '+Linear open ACME-102'"
Enter
Sleep 2s
Show

# 1. ACME-102 is open
Sleep 3s

# 2. Linked issues picker: parent, then blocked by
Type "gr"
Sleep 2.5s
Down
Sleep 2.5s

# 3. Follow the blocked-by link to ACME-104
Enter
Sleep 3.5s

# 4. Back to ACME-102
Backspace
Sleep 3s

# 5. Parent issue
Type "gp"
Sleep 4s

Hide
Type ":qa!"
Enter
