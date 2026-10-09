# ── история ─────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt share_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks

# ── общее ───────────────────────────────────────────────
setopt auto_cd interactive_comments no_beep
export EDITOR=nvim VISUAL=nvim MANPAGER="nvim +Man!"
export PATH="$HOME/.local/bin:$PATH"

bindkey -e
bindkey '^[[H' beginning-of-line  '^[[F' end-of-line  '^[[3~' delete-char
bindkey '^[[1;5C' forward-word    '^[[1;5D' backward-word
bindkey '^H' backward-kill-word   # ctrl+backspace

# ── автодополнение ──────────────────────────────────────
fpath=(/usr/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit -d ~/.cache/zcompdump
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{8}%d%f'
zmodload zsh/complist
bindkey -M menuselect '^[[Z' reverse-menu-complete

# ── промпт: ~/dir main* ❯ ──────────────────────────────
autoload -Uz vcs_info add-zsh-hook
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' formats ' %F{8}%b%u%c%f'
zstyle ':vcs_info:git:*' actionformats ' %F{8}%b|%a%u%c%f'
add-zsh-hook precmd vcs_info
setopt prompt_subst
PROMPT='%F{white}%~%f${vcs_info_msg_0_} %(?.%F{8}.%F{red})❯%f '
RPROMPT='%(?..%F{red}%?%f)'

# ── алиасы ──────────────────────────────────────────────
alias ll='ls -l --git --time-style=relative'
alias la='ll -a'
alias lt='eza --tree --level=2 --icons=auto'
#alias cat='bat --plain --paging=never'
alias v='nvim'
alias g='git'
alias ..='cd ..'
alias ...='cd ../..'
alias ff='fastfetch'

# yazi: после выхода остаёмся в последней открытой папке
y() {
    local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# ── инструменты ─────────────────────────────────────────
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
# цвета fzf — по теме из Настроек Quickshell
[ -f ~/.config/zsh/qs-theme.zsh ] && source ~/.config/zsh/qs-theme.zsh
export BAT_THEME=ansi

(( $+commands[fzf] ))    && source <(fzf --zsh)       # ctrl+r история, ctrl+t файлы, alt+c папки
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"  # cd помнит папки

# ── плагины (последними) ────────────────────────────────
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#4a4a4a'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
for p in zsh-autosuggestions/zsh-autosuggestions.zsh zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    [ -f /usr/share/zsh/plugins/$p ] && source /usr/share/zsh/plugins/$p
done
