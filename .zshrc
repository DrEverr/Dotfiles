# 🖊️ Set window title
precmd() {
  print -Pn "\e]2;%~\a"
}

# 📂 PATH - local binaries
export PATH="$PATH:$HOME/local/nvim/bin"

# 🎨 Start Oh My Posh
eval "$(oh-my-posh init zsh)"

# ⚙️ Autocomplete - start
autoload -Uz compinit
compinit

# 🧠 Better completition:
# - Case-insensitive
# - Colors
# - Cached
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion::complete:*' use-cache on
# ⁉️ You need to create folder ~/.zsh/cache
zstyle ':completion::complete:*' cache-path ~/.zsh/cache

# 🔁 Search history with Ctrl+R
bindkey '^R' history-incremental-search-backward

# 🧠 Smart history with ↑ ↓
autoload -Uz up-line-or-beginning-search
autoload -Uz down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search   # arrow up
bindkey "^[[B" down-line-or-beginning-search # arrow down

# ⏩ Reload $PATH
zstyle ':completion:*' rehash true

# 📜 History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# 🧽 Clean screen on finished loading
clear

