#!/bin/zsh -e

ARCADIA_ROOT_FILES_LIST_CACHED_FILE=${HOME}/.cache/arcadia_files_list.txt

unset get_arcadia_files_of_interest

get_arcadia_files_of_interest() {
    local directories=("catboost" "contrib" "cv" "extsearch" "ml" "mapreduce" "library" "kernel" "quality" "sandbox" "search" "statbox" "strm" "util" "web" "yql" "ysite" "yweb" "junk/splinter");

    for directory in ${directories}; do
        fd -t f --color=never . ${ARCADIA_ROOT}/${directory}
    done

    for directory in ${directories}; do
        fd -t f --color=never . ${ARCADIA_ROOT_GENERATED}/${directory}
    done
}


if [[ ! -f ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE} ]]; then
    get_arcadia_files_of_interest > ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE}
else
    local current_time=`date +%s`;
    local modification_time=`date -r ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE} +%s`
    local time_diff=$current_time-$modification_time
    if [[ $time_diff -gt 86400 ]]; then
        rm -f ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE};
        get_arcadia_files_of_interest > ${ARCADIA_ROOT_FILES_LIST_CACHED_FILE}
    fi
fi

ag --ignore .git -g . $HOME/experiments

cat $ARCADIA_ROOT_FILES_LIST_CACHED_FILE
