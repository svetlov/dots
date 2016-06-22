#!/usr/bin/env zsh

source ${HOME}/.zshrc;
echo "sourced";

if [[ `uname` = "Darwin" ]]; then
    mkdir -p ${HOME}/tmp/pbopen/;

    timestamp=`date +"%Y-%m-%d %H:%M:%S"`;
    cat "${1:-/dev/stdin}" > "${HOME}/tmp/pbopen/${timestamp}";
    echo "Trying to open ${COLOR_CYAN}${HOME}/tmp/pbopen/${timestamp}${COLOR_OFF}";
    open "${HOME}/tmp/pbopen/${timestamp}";
elif [[ `expr substr $(uname -s) 1 5` = "Linux" ]]; then
    cat $1 | nc localhost 2226;
else
    echo "${COLOR_RED}Unknown host $(uname)${COLOR_OFF}";
fi
