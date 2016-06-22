#!/usr/bin/env zsh

source ${HOME}/.zshrc

print_usage() {
    echo "${COLOR_RED}Usage: nb ( open | start venvname | tunnel hostname )${COLOR_OFF}" 1>&2;
}

if [[ $# -ne 2 && $# -ne 1 ]]; then
    print_usage;
    return 1;
fi

if [[ $1 == "start" ]]; then
    if [[ $# -ne 2 ]]; then
        print_usage;
        return 1;
    fi

    workon $2;
    if [[ `uname` = "Darwin" ]]; then
        jupyter notebook --port=${REMOTE_IPYTHON_PORT};
    elif [[ `expr substr $(uname -s) 1 5` = "Linux" ]]; then
        (sleep 2 && notebook tunnel localhost) &  # async call for host to forward ports and open safari
        jupyter notebook --certfile=${HOME}/projects/dots/all/security/mycert.pem \
            --no-browser --port=${REMOTE_IPYTHON_PORT};
    fi
elif [[ $1 == "tunnel" ]]; then
    if [[ $# -ne 2 ]]; then
        print_usage;
        return 1;
    fi

    if [[ `uname` = "Darwin" ]]; then
        if [[ $2 == '--read-hostname-from-pipe' ]];then
            echo "${COLOR_CYAN}Reading hostname from pipe ${COLOR_OFF}";
            read hostname;
            echo "${COLOR_CYAN}Server hostname is ${hostname}${COLOR_OFF}";
        else
            hostname=$2;
        fi
        ssh -q -N -f -L localhost:${LOCAL_IPYTHON_PORT}:localhost:${REMOTE_IPYTHON_PORT} ${hostname};
        notebook open;
    elif [[ `expr substr $(uname -s) 1 5` = "Linux" ]]; then
        if [[ $2 -ne "localhost" ]]; then
            echo "${COLOR_RED}On linux machine only localhost hostname is allowed${COLOR_OFF}";
            return 1;
        fi
        echo "${COLOR_CYAN}Trying to open notebook on local machine${COLOR_OFF}";
        echo ${HOST} | nc localhost 2227;
    else
        echo "${COLOR_RED}Unknown host $(uname)${COLOR_OFF}";
    fi
elif [[ $1 == "open" ]]; then
    if [[ $# -ne 1 ]]; then
        print_usage;
        return 1;
    fi

    open -a safari https://localhost:${LOCAL_IPYTHON_PORT};
else
    print_usage;
    return 1;
fi
