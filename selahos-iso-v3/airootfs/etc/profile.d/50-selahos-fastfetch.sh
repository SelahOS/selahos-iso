# /etc/bash.bashrc.d/50-selahos-fastfetch.sh
# Auto-display SelahOS fastfetch on interactive shell login.
# Per Laura/Dane fastfetch bundle (May 6, 2026).

# Only run for interactive shells, only on first shell of session
if [[ $- == *i* ]] && [[ -z "$SELAHOS_FASTFETCH_SHOWN" ]] && [[ -z "$SSH_CONNECTION" ]]; then
    if command -v fastfetch >/dev/null 2>&1; then
        export SELAHOS_FASTFETCH_SHOWN=1
        fastfetch 2>/dev/null
    fi
fi
