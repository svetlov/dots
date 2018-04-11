# ZSH Theme - Preview: http://gyazo.com/8becc8a7ed5ab54a0262a470555c3eed.png
PAD="................................................................................................................"
MAXPADLEN="${#PAD}"

if [[ $UID -eq 0 ]]; then
    local user_symbol='#'
else
    local user_symbol='$'
fi

local time='[%D{%H:%M:%S}]'
PROMPT="%{$fg[yellow]%}╰─${time} %{$fg_bold[cyan]%}%c%{$reset_color%} %B${user_symbol}%b "

function hg_prompt_info() {
    branch=$(hg branch 2> /dev/null) || return
    echo "$ZSH_THEME_HG_PROMPT_PREFIX$(hg_get_branch_name)$ZSH_THEME_HG_PROMPT_CLEAN"
}
function hostname_prompt() {
    print "$fg[yellow]$(hostname -s)$reset_color"
}

function pwd_prompt() {
    print "$fg_bold[cyan]$(pwd)$reset_color"
}

function git_status_prompt() {
    branches=$(git branch 2> /dev/null) || return
    branch=$(echo $branches | grep \* | cut -d ' ' -f2)
    print "$fg_bold[blue]($fg_bold[magenta]$branch$fg_bold[blue])$reset_color "
}

function return_code_prompt() {
    rc="$1";
    datetime="[$(date +%H:%M:%S)]";
    if [ $rc -ne 0 ]; then
        print "$fg_bold[red] $datetime↵ $fg_bold[blue]($fg_bold[red]${rc}$fg_bold[blue])$reset_color";
    else
        print "$fg_bold[green]$datetime↵$reset_color";
    fi
}

precmd() {
  local rc="$?";

  RIGHT=" ";
  LEFT="$(hostname_prompt) $(pwd_prompt) $(git_status_prompt)$(return_code_prompt ${rc})  ";

  LEFTACSII=$(echo $LEFT | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g");
  RIGHTASCII=$(echo $RIGHT | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g");

  PADWIDTH=$(($COLUMNS-${#LEFTACSII}-${#RIGHTASCII}))
  PADWIDTH=$(( $PADWIDTH > $MAXPADLEN ? $MAXPADLEN : $PADWIDTH ))
  # echo "$COLUMNS ${#LEFT} ${#LEFTACSII} ${PADWIDTH} ${#RIGHT} ${#RIGHTASCII}" >&2;
  print "${LEFT}${PAD:0:${PADWIDTH}}${RIGHT}"
}

TMOUT=1

TRAPALRM() {
    zle reset-prompt
}
