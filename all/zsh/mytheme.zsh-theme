local ret_status="%(?:%{$fg_bold[green]%}➜:%{$fg_bold[red]%}➜%s)"

function hg_prompt_info() {
    branch=$(hg branch 2> /dev/null) || return
    echo "$ZSH_THEME_HG_PROMPT_PREFIX$(hg_get_branch_name)$ZSH_THEME_HG_PROMPT_CLEAN"
}

PROMPT='%{$fg[yellow]%}%m%{$reset_color%} %{$fg_bold[yellow]%}${ANACONDA}${ret_status}%{$fg_bold[green]%}%p %{$fg[cyan]%}%c %{$fg_bold[blue]%}$(git_prompt_info)$(hg_prompt_info)%{$fg_bold[blue]%} % %{$reset_color%}'

ZSH_THEME_GIT_PROMPT_PREFIX="(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"

ZSH_THEME_HG_PROMPT_PREFIX="(%{$fg[red]%}"
ZSH_THEME_HG_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_HG_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗%{$reset_color%}"
ZSH_THEME_HG_PROMPT_CLEAN="%{$fg[blue]%})"
