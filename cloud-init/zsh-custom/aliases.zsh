alias count-files="ls -f1 | wc -l" # does not include hidden files
alias count-dirs="ls -D1 | wc -l" # does not include hidden dirs
alias count-all="ls -A1 | wc -l" # all files and folder incl. hidden does not include the "." and ".."
alias count-dotfiles="ls -Af1 | wc -l" # count all files incl. hidden
alias count-dotdirs="ls -AD1 | wc -l" # count all dirs incl. hidden


# various pwgen-like utilities
alias pwgen-words='secpwgen -p "$@"' # usage: pwgen-words [number of words to be generated]
alias pwgen-shortwords='secpwgen -s "$@"' # usage: pwgen-shortwords [number of words to be generated]
alias pwgen-base64='secpwgen -r "$@"' # usage: pwgen-base64 [number of bits to encode in BASE64 string]
alias pwgen-kore='secpwgen -k "$@"' # usage: pwgen-kore [number of bits to encode as syllabic phrase]
alias pwgen-alphanumeric='secpwgen -Aadh "$@"' # usage: pwgen-alphanumeric [number of Alphanumeric characters to be generated]
alias pwgen-symbols='secpwgen -Aadhs "$@"' # usage: pwgen-symbols [number of Alphanumeric characters and special characters to be generated]

# ugrep-replace.sh alias for text replacement
alias replace-text='$HOME/devspace/myprojects/timesavers/shell-based-utils/ugrep-replace.sh'



alias openssl-check='openssl x509 -noout -text -in '

alias hg='history | grep '

alias ports='netstat -tulpn'

# Replace ls with eza
alias l='eza -alh --color=always --group-directories-first --icons=always'
alias l.='eza -ald --color=always --group-directories-first --icons=always .*'
alias lD='eza -glD --color=always --group-directories-first --icons=always'
alias lDD='eza -glDa --color=always --group-directories-first --icons=always'
alias lS='eza -gl -ssize --color=always --group-directories-first --icons=always'
alias lT='eza -gl -snewest --color=always --group-directories-first --icons=always'
alias la='eza -a --color=always --group-directories-first --icons=always'
alias ldot='eza -gld --color=always --group-directories-first --icons=always .*'
alias ll='eza -l --color=always --group-directories-first --icons=always'
alias ls='eza -al --color=always --group-directories-first --icons=always'
alias lsa='ls -lah --color=always --group-directories-first --icons=always'
alias lsd='eza -gd --color=always --group-directories-first --icons=always'
alias lsdl='eza -gdl --color=always --group-directories-first --icons=always'
alias lt='eza -aT --color=always --group-directories-first --icons=always'

 alias ohmyzsh="nano ~/.oh-my-zsh"
 alias apt-update="sudo apt update"
 alias apt-upgrade="sudo apt full-upgrade"
 alias iperf=iperf3
alias ip='ip -c'
alias nmcli='nmcli --ask --colors yes --escape yes'
export GPG_TTY=$(tty)



# Replace some more things with better alternatives
if [[ -x /usr/bin/bat ]]; then
  alias cat='bat --style header --style snip --style changes --style header -pp'
fi

alias tarnow='tar -acf '
alias untar='tar -zxvf '
alias wget='wget -c '
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='ugrep --color=auto'
alias fgrep='ugrep -F --color=auto'
alias egrep='ugrep -E --color=auto'


# Get the error messages from journalctl
alias jctl="journalctl -p 3 -xb"

alias zshrc='${=EDITOR} ${ZDOTDIR:-$HOME}/.zshrc' # Quick access to the .zshrc file
alias grep='grep --color'
alias sgrep='grep -R -n -H -C 5 --exclude-dir={.git,.svn,CVS} '

alias t='tail -f'

# Command line head / tail shortcuts
alias -g H='| head'
alias -g T='| tail'
alias -g G='| grep'
alias -g L="| less"
alias -g M="| most"
alias -g LL="2>&1 | less"
alias -g CA="2>&1 | cat -A"
alias -g NE="2> /dev/null"
alias -g NUL="> /dev/null 2>&1"
alias -g P="2>&1| pygmentize -l pytb"

alias dud='du -d 1 -h'
(( $+commands[duf] )) || alias duf='du -sh ./*'
(( $+commands[fd] )) || alias fd='find . -type d -name'
alias ff='find . -type f -name'

alias h='history'
alias hgrep="fc -El 0 | grep"
alias help='man'
alias p='ps -f'
alias sortnr='sort -n -r'
alias unexport='unset'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

