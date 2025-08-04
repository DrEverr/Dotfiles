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

# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then # GNU `ls`
	colorflag="--color"
	export LS_COLORS='no=00:fi=00:di=01;31:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:'
else # macOS `ls`
	colorflag="-G"
	export LSCOLORS='BxBxhxDxfxhxhxhxhxcxcx'
fi

# ↔️ Aliases
alias reload="source ~/.zshrc"
alias path='echo -e ${PATH//:/\\n}'
alias grep='grep --color=auto'
alias ls="command ls ${colorflag}"
alias ll="ls -lF ${colorflag}"
alias la="ls -lAF ${colorflag}"
alias dl="cd ~/Downloads"
alias dt="cd ~/Desktop"
alias tb="cd ~/Development/typeberry/"
alias g="git"
alias ga="git commit -a"

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."

# 🧽 Clean screen on finished loading
clear

