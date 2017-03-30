#!/usr/bin/env zsh

source ${HOME}/.zshrc;

if [[ ! -f "${1}" ]]; then
    echo "${COLOR_RED}No such file or directory: ${1} ${COLOR_OFF}";
    return 1;
fi

if [[ $is_darwin == true ]]; then
    mkdir -p ${HOME}/tmp/pbopen/;

    timestamp=`date +"%Y-%m-%d %H:%M:%S"`;
    cat "${1:-/dev/stdin}" > "${HOME}/tmp/pbopen/${timestamp}";
    echo "Trying to open ${COLOR_CYAN}${HOME}/tmp/pbopen/${timestamp}${COLOR_OFF}";
    open "${HOME}/tmp/pbopen/${timestamp}";
elif [[ $is_linux == true ]]; then
    cat ${1} | nc localhost 2226;
else
    echo "${COLOR_RED}Unknown host $(uname)${COLOR_OFF}";
    return 1;
fi
