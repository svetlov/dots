#!/bin/zsh -e

if [[ "${@: -1}" == "${ARCADIA_ROOT}" ]]; then

    ARCADIA_ROOT_FILES_LIST_CACHED_FILE=${HOME}/.cache/arcadia_files_list.txt

    unset get_arcadia_files_of_interest

    get_arcadia_files_of_interest() {
        local directories=("contrib/libs/intel" "contrib/libs/tf" "contrib/libs/tf-1.14" "contrib/libs/nvidia" "contrib/libs/eigen" "cv" "extsearch" "ml" "mapreduce" "library" "kernel" "quality/neural_net" "statbox/nile" "statbox/bindings" "statbox/qb2" "statbox/qb2_core" "util" "yql/library" "junk/splinter");

        for directory in ${directories}; do
            if [[ -d "${ARCADIA_ROOT}/${directory}" ]]; then
                fd -t f --color=never . ${ARCADIA_ROOT}/${directory}
            fi
        done

        for directory in ${directories}; do
            if [[ -d "${ARCADIA_ROOT_GENERATED}/${directory}" ]]; then
                fd -t f --color=never . ${ARCADIA_ROOT_GENERATED}/${directory}
            fi
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

    # ag --ignore .git -g . $HOME/experiments

    cat $ARCADIA_ROOT_FILES_LIST_CACHED_FILE
else
    fd -t f --color=never . ${@: -1}
fi
