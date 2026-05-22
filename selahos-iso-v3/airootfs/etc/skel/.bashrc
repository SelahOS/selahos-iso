# SelahOS .bashrc
# Pause. Reflect. Create.

# Source global definitions
[ -f /etc/bashrc ] && . /etc/bashrc

# History
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoredups:ignorespace

# Aliases
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias update='sudo pacman -Syu'
alias selah-recover='sudo selah-recover'

# Run fastfetch on new terminal (only interactive, not SSH)
if [[ $- == *i* ]] && command -v fastfetch &>/dev/null; then
    fastfetch
fi

# SelahBridge helper
alias wine-apps='ls ~/.wine/drive_c/Program\ Files/ 2>/dev/null || echo "No Wine apps installed"'
