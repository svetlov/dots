#!/bin/zsh

ARCADIA_ROOT_FILES_LIST_CACHED_FILE=${HOME}/.cache/arcadia_files_list.txt


if [[ ! -f ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE} ]]; then
    fd . ${ARCADIA_ROOT} > ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE}
else
    local current_time=`date +%s`;
    local modification_time=`date -r ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE} +%s`
    local time_diff=$current_time-$modification_time
    if [[ $time_diff -gt 86400 ]]; then
        fd . ${ARCADIA_ROOT} > ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE}
    fi
fi

ag --hidden --ignore .git \
    -g . $HOME/experiments \
    --ignore '*.jpg' \
    --ignore '*.png' \
    --ignore '*.mp4' \
    --ignore '*.mpeg' \
    --ignore '*.index' \
    --ignore '*.meta' \
    --ignore '*.tar' \
    --ignore '*.pkl' \
    --ignore '*.net'

cat $ARCADIA_ROOT_FILES_LIST_CACHED_FILE
