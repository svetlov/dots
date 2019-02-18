# ZSH Theme - Preview: http://gyazo.com/8becc8a7ed5ab54a0262a470555c3eed.png
PAD="................................................................................................................"
MAXPROMPTLEN=120;

if [[ $UID -eq 0 ]]; then
    local user_symbol='#'
else
    local user_symbol='$'
fi

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

function git_dirty {
    [[ $(git status --porcelain 2> /dev/null | wc -l) -ne 0 ]] && echo "$fg_bold[yellow]:✗"
}

function git_branch_prompt() {
    branches=$(git branch 2> /dev/null) || return
    branch=$(echo $branches | grep \* | cut -d ' ' -f2)
    print " $fg_bold[blue]($fg_bold[magenta]$branch$(git_dirty)$fg_bold[blue])$reset_color"
}

function arc_dirty {
    [[ $(arc status --short 2> /dev/null | wc -l) -ne 0 ]] && echo "$fg_bold[yellow]:✗"
}

function arc_branch_prompt() {
    branches=$(arc branch 2> /dev/null) || return
    branch=$(echo $branches | grep \* | cut -d ' ' -f2)
    print " $fg_bold[blue]($fg_bold[magenta]$branch$(arc_dirty)$fg_bold[blue])$reset_color"
}

function venv_prompt() {
    venv_name=$(basename $VIRTUAL_ENV 2> /dev/null) || return;
    print " ($venv_name)";
}

function return_code_prompt() {
    rc="$1";
    local_fulltime="[$(date +%H:%M:%S)]";
    if [ $rc -ne 0 ]; then
        print " $fg_bold[red]$local_fulltime ↵ $fg_bold[blue]($fg_bold[red]${rc}$fg_bold[blue])$reset_color";
    else
        print " $fg_bold[green]$local_fulltime ↵ $reset_color";
    fi
}


local time='[%D{%H:%M}]'
local fulltime='[%D{%H:%M:%S}]'
BEFORE_PROMPT="%{$fg[yellow]%}╰─${time} %{$fg_bold[cyan]%}%c%{$reset_color%} %B${user_symbol}%b "
AFTER_PROMPT="%{$fg[yellow]%}╰─${fulltime} %{$fg_bold[cyan]%}%c%{$reset_color%} %B${user_symbol}%b "


precmd() {
  local rc="$?";

  LEFT="$(hostname_prompt):$(pwd_prompt)$(git_branch_prompt)$(arc_branch_prompt)$(venv_prompt)$(return_code_prompt ${rc}) ";
  LEFTACSII=$(echo $LEFT | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g");
  LEFTWIDTH="${#LEFTACSII}";
  RIGHT="";


  if [[ "${#TMUX}" -ne 0 ]]; then
      PANEWIDTH="$(tmux display -p '#{pane_width}')";
  else
      PANEWIDTH="$COLUMNS";
  fi

  PROMPTLEN=$(( $PANEWIDTH > $MAXPROMPTLEN ? $MAXPROMPTLEN : $PANEWIDTH ))

  PADWIDTH=$(($PROMPTLEN - $LEFTWIDTH))
  PADWIDTH=$(( $PADWIDTH < 0 ? 0 : $PADWIDTH ))

  # echo "$PANEWIDTH ${#LEFT} ${#LEFTACSII} ${PADWIDTH} ${#RIGHT} ${#RIGHTASCII}" >&2;
  print "${LEFT}${PAD:0:${PADWIDTH}}${RIGHT}"

  PROMPT=$BEFORE_PROMPT
}

reset-prompt-and-accept-line() {
    PROMPT=$AFTER_PROMPT
    zle reset-prompt
    zle accept-line
}

zle -N reset-prompt-and-accept-line
bindkey '^m' reset-prompt-and-accept-line


TMOUT=60
TRAPALRM() {
    zle reset-prompt
}
