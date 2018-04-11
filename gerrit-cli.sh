#!/bin/bash -e

export PS4='+ [$(basename ${BASH_SOURCE})] [${LINENO}] '
SCRIPT_NAME=$(basename $0)

ERROR_CODE_CONFIG_NOT_FOUND=1
ERROR_CODE_SSH_KEY_NOT_MATCH=2
ERROR_CODE_COMMAND_NOT_SUPPORTED=3
ERROR_CODE_BRANCH_CREATION_FAILURE=4
ERROR_CODE_EXCLUSIVE_OPTIONS_PROVIDED=5
ERROR_CODE_GERRIT_USER_NOT_FOUND=6
ERROR_CODE_PROJECT_NOT_FOUND=7
ERROR_CODE_INSUFFICIENT_PERMISSION=8
ERROR_CODE_INVALID_CACHE_NAME_FOUND=9

declare -A CMD_USAGE_MAPPING
declare -A CMD_OPTION_MAPPING
declare -A CMD_FUNCTION_MAPPING

declare -a GERRIT_HOSTS
declare -a GERRIT_USERS
declare -a GERRIT_PORTS
GERRIT_CLI=

CONFIG_FILE="$HOME/.gerrit/config.json"

function log_i() {
    echo -e "Info : $*"
}

function log_e() {
    echo -e "Error: $*"
}

function __check_config() {
    local _SERVER_COUNT=
    local _JSON=
    local _RET_VALUE=

    _RET_VALUE=0

    if [ ! -f "$CONFIG_FILE" ]; then
        _RET_VALUE=$ERROR_CODE_CONFIG_NOT_FOUND
    else
        _SERVER_COUNT=$(cat "$CONFIG_FILE" | jq -r ".server_pool | length")
        for I in $(seq 0 $((_SERVER_COUNT - 1))); do
            _JSON=$(cat "$CONFIG_FILE" | jq ".server_pool | .[$I]")
            GERRIT_HOSTS[$I]=$(echo "$_JSON" | jq -r ".host")
            GERRIT_PORTS[$I]=$(echo "$_JSON" | jq -r ".port")
            GERRIT_USERS[$I]=$(echo "$_JSON" | jq -r ".user")
        done
    fi

    return $_RET_VALUE
}

function __ascertain_server() {
    local _GERRIT_HOST=
    local _GERRIT_PORT=
    local _GERRIT_USER=
    local _INDEX=
    local _CHOICE=
    local _RET_VALUE=

    _RET_VALUE=0

    if [ ${#GERRIT_HOSTS[@]} -eq 1 ]; then
        _GERRIT_HOST=${GERRIT_HOSTS[0]}
        _GERRIT_PORT=${GERRIT_PORTS[0]}
        _GERRIT_USER=${GERRIT_USERS[0]}
    else
        echo "As several Gerrit servers are provided, please choose one:"
        _INDEX=0
        for I in $(seq 1 ${#GERRIT_HOSTS[@]}); do
            _INDEX=$((I - 1))
            echo "$I. ${GERRIT_HOSTS[$_INDEX]}"
        done
        echo
        while true; do
            read -p "Your choice (the index number): " _CHOICE
            if ! echo "$_CHOICE" | grep -qE "[0-9]+"; then
                echo "Unacceptable choice: '$_CHOICE'"
                echo
                continue
            fi

            if [ "$_CHOICE" -ge 1 ] && \
                [ "$_CHOICE" -le "${#GERRIT_HOSTS[@]}" ]; then
                echo
                break
            else
                echo "Unacceptable choice: '$_CHOICE'"
                echo
            fi
        done

        _CHOICE=$((_CHOICE - 1))
        _GERRIT_HOST=${GERRIT_HOSTS[$_CHOICE]}
        _GERRIT_PORT=${GERRIT_PORTS[$_CHOICE]}
        _GERRIT_USER=${GERRIT_USERS[$_CHOICE]}
    fi

    ssh -p $_GERRIT_PORT $_GERRIT_USER@$_GERRIT_HOST 2> /dev/null || \
    if [[ "$?" -ne "127" ]]; then
        log_e "SSH private key not matched with user: $_GERRIT_USER"
        log_e "Please check your config file: $CONFIG_FILE"
        _RET_VALUE=$ERROR_CODE_SSH_KEY_NOT_MATCH
    else
        GERRIT_CLI="ssh -p $_GERRIT_PORT $_GERRIT_USER@$_GERRIT_HOST gerrit"
    fi

    return $_RET_VALUE
}

function __print_usage_of_create_branch() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. $SCRIPT_NAME create-branch -p <PROJECT> -b <BRANCH> -r <REVISION>
    2. $SCRIPT_NAME create-branch -f <BATCH_FILE>

DESCRIPTION
    Creates new branches for projects with given revision.

    The 1st format
        Creates a new branch <BRANCH> basing on given revision <REVISION> for
        specified project <PROJECT>.

    The 2nd format
        Creates new branches by batch basing on given file <BATCH_FILE>.
        Formats for file <BATCH_FILE>:
            - Each line must contain three fields which represent <PROJECT>,
              <BRANCH> and <REVISION>
            - Uses a whitespace to separate fields in each line
        Essentially, it uses the 1st format to create branches after extracting
        these fields.
OPTIONS
    -p|--project <PROJECT>
        Specify project's name.

    -b|--branch <BRANCH>
        Specify new branch's name.

    -r|--revision <REVISION>
        Specify an initial revision for the new branch. Could be a branch name
        or a SHA-1 value.

    -f|--file <BATCH_FILE>
        A file which contains required information to create new branches.

EXAMPLES
    1. Creates a branch called 'dev' from branch 'master' for project
       'devops/ci'.
       $ $SCRIPT_NAME create-branch -p devops/ci -b dev -r master

    2. Creates new branches using batch file named 'batch.file'
       $ $SCRIPT_NAME create-branch -f batch.file
EOU

    return $_RET_VALUE
}

function __create_branch() {
    local _SUB_CMD=
    local _PROJECT=
    local _BRANCH=
    local _REVISION=
    local _BATCH_FILE=
    local _CLI_CMD=
    local _REV_MAPPING=
    local _LEN_MAX_P=
    local _LEN_MAX_B=
    local _RET_VALUE=

    declare -A _REV_MAPPING

    _SUB_CMD="create-branch"
    _RET_VALUE=0

    if [[ $# -eq 0 ]]; then
        eval "${CMD_USAGE_MAPPING[$_SUB_CMD]}"
        return $_RET_VALUE
    fi

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                _PROJECT=$2
                ;;
            -b|--branch)
                _BRANCH=$2
                ;;
            -r|--revision)
                _REVISION=$2
                ;;
            -f|--file)
                _BATCH_FILE=$2
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done

    __ascertain_server || return $?

    if [[ ! -e "$_BATCH_FILE" ]]; then
        _CLI_CMD="$GERRIT_CLI $_SUB_CMD $_PROJECT $_BRANCH $_REVISION"
        log_i "branch creation combo: ($_PROJECT, $_BRANCH, $_REVISION)"

        if eval "$_CLI_CMD"; then
            log_i "new branch created: $_BRANCH"
        else
            log_e "fail to create new branch: $_BRANCH"
            _RET_VALUE=$ERROR_CODE_BRANCH_CREATION_FAILURE
        fi
    else
        # Length of word "Project": 7
        # Length of word "Branch": 6
        _LEN_MAX_P=7
        _LEN_MAX_B=6
        while read _PROJECT _BRANCH _REVISION; do
            log_i "branch creation info: ($_PROJECT, $_BRANCH, $_REVISION)"

            if [ "${#_PROJECT}" -gt "$_LEN_MAX_P" ]; then
                _LEN_MAX_P=${#_PROJECT}
            fi

            if [ "${#_BRANCH}" -gt "$_LEN_MAX_B" ]; then
                _LEN_MAX_B=${#_BRANCH}
            fi

            # As ssh reads from standard input, it eats all remaining lines,
            # there are two ways to avoid this issue:
            # 1. redirects standard input to null bucket for ssh
            # 2. uses option -n for ssh
            _CLI_CMD="$GERRIT_CLI $_SUB_CMD $_PROJECT $_BRANCH $_REVISION"
            if eval "$_CLI_CMD" < /dev/null; then
                _REV_MAPPING["${_PROJECT}${_BRANCH}"]="$_REVISION"
                log_i "new branch created: $_BRANCH"
            else
                _REV_MAPPING["${_PROJECT}${_BRANCH}"]="????"
                log_e "fail to create new branch: $_BRANCH"
                _RET_VALUE=$ERROR_CODE_BRANCH_CREATION_FAILURE
            fi

            echo
        done < "$_BATCH_FILE"

        printf "%$((_LEN_MAX_P + _LEN_MAX_B + 4 + 40))s\n" "-" | sed "s| |-|g"
        printf "%-${_LEN_MAX_P}s  %-${_LEN_MAX_B}s  %-s\n" \
                "Project" "Branch" "Revision"
        printf "%$((_LEN_MAX_P + _LEN_MAX_B + 4 + 40))s\n" "-" | sed "s| |-|g"
        while read _PROJECT _BRANCH _REVISION; do
            printf "%-${_LEN_MAX_P}s  %-${_LEN_MAX_B}s  %-s\n" \
                    "$_PROJECT" \
                    "$_BRANCH" \
                    "${_REV_MAPPING[${_PROJECT}${_BRANCH}]}"
        done < "$_BATCH_FILE"
        printf "%$((_LEN_MAX_P + _LEN_MAX_B + 4 + 40))s\n" "-" | sed "s| |-|g"
    fi

    return $_RET_VALUE
}

function __print_usage_of_ls_user_refs() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. $SCRIPT_NAME ls-user-refs -p <PROJECT> -u <USER> [-b] [-t]

DESCRIPTION
    Display all refs (branches and tags) that the specified user can access.

    Options -b|--branch-only and -t|--tag-only are exclusive.

OPTIONS
    -p|--project <PROJECT>
        Specify project's name.

    -u|--user <USER>
        Specify a user's name.

    -b|--branch-only
        Only show branches under reference refs/heads.

    -t|--tag-only
        Only show tags under reference refs/tags.

    -h|--help
        Show this usage document.

EXAMPLES
    1. List all visible refs for user 'blankl' in project 'release/jenkins'
       $ $SCRIPT_NAME ls-users-refs -p release/jenkins -u blankl

    2. List all visible tags for user 'blankl' in project 'release/jenkins'
       $ $SCRIPT_NAME ls-users-refs -p release/jenkins -u blankl -t
EOU

    return $_RET_VALUE
}

function __ls_user_refs() {
    local _SUB_CMD=
    local _ARGS=
    local _PROJECT=
    local _USER=
    local _BRANCH_ONLY=
    local _TAG_ONLY=
    local _CLI_CMD=
    local _TMPFILE=
    local _RET_VALUE=

    _SUB_CMD="ls-user-refs"
    _BRANCH_ONLY="false"
    _TAG_ONLY="false"
    _RET_VALUE=0

    if [[ $# -eq 0 ]]; then
        eval "${CMD_USAGE_MAPPING[$_SUB_CMD]}"
        return $_RET_VALUE
    fi

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                _PROJECT=$2
                ;;
            -u|--user)
                _USER=$2
                ;;
            -b|--branch-only)
                _BRANCH_ONLY="true"
                ;;
            -t|--tag-only)
                _TAG_ONLY="true"
                ;;
            -h|--help)
                eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                return $_RET_VALUE
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done

    __ascertain_server || return $?

    if eval "$_BRANCH_ONLY" && eval "$_TAG_ONLY"; then
        _RET_VALUE=$ERROR_CODE_EXCLUSIVE_OPTIONS_PROVIDED
        log_e "options -b|--branch-only and -t|--tag-only are exclusive."
    else
        _TMPFILE=$(tempfile -s ".refs")
        _CLI_CMD="$GERRIT_CLI $_SUB_CMD -p $_PROJECT -u $_USER > $_TMPFILE"
        if eval "$_CLI_CMD"; then
            if grep -q "$_USER" "$_TMPFILE"; then
                _RET_VALUE=$ERROR_CODE_GERRIT_USER_NOT_FOUND
                xargs -a "$_TMPFILE" echo "fatal:"
            else
                if eval "$_BRANCH_ONLY"; then
                    cat "$_TMPFILE" | grep "refs/heads/.*" | sort
                elif eval "$_TAG_ONLY"; then
                    cat "$_TMPFILE" | grep "refs/tags/.*" | sort
                else
                    cat "$_TMPFILE" | grep -E "refs/(heads|tags)/.*" | sort
                fi
            fi
        else
            _RET_VALUE=$ERROR_CODE_PROJECT_NOT_FOUND
            cat "$_TMPFILE"
        fi

        if [ ! -s "$_TMPFILE" ]; then
            log_i "user '$_USER' has no permission on project '$_PROJECT'"
        fi

        rm -f "$_TMPFILE"
    fi

    return $_RET_VALUE
}

function __print_usage_of_show_connections() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. $SCRIPT_NAME show-connections [-n]

DESCRIPTION
    Presents a table of the active SSH connections, the users who are
    currently connected to the internal server and performing an activity.

    The table contains five columns:
    1) Session
       An unique session identifier of the connection on the server.
    2) Start
       The time (local to the server) the connection started.
    3) Idle
       The time since the last data transfer on this connection.
    4) User
       The username of the account that is authenticated on this connection.
    5) Remote Host
       The hostname or IP address of client on this connection.
OPTIONS
    -n|--numeric
        Show numberic account ID instead of username.
        Show client hostnames as IP addresses instead of DNS hostnames.

    -h|--help
        Show this usage document.

EXAMPLES
    1. List all active connections
       $ $SCRIPT_NAME show-connections
EOU

    return $_RET_VALUE
}

function __show_connections() {
    local _SUB_CMD=
    local _NUMERIC_MODE=
    local _CLI_CMD=
    local _RET_VALUE=

    _SUB_CMD="show-connections"
    _NUMERIC_MODE="false"
    _RET_VALUE=0

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--ip)
                _NUMERIC_MODE="true"
                ;;
            -h|--help)
                eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                return $_RET_VALUE
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done

    __ascertain_server || return $?

    _CLI_CMD="$GERRIT_CLI $_SUB_CMD -w"
    if eval "$_NUMERIC_MODE"; then
        _CLI_CMD="$_CLI_CMD -n"
    fi

    if ! eval "$_CLI_CMD"; then
        _RET_VALUE=$ERROR_CODE_INSUFFICIENT_PERMISSION
    fi

    return $_RET_VALUE
}

function __print_usage_of_close_connection() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. $SCRIPT_NAME close-connection [--wait] SESSION_ID...

DESCRIPTION
    Closes the specified SSH connections by their session IDs.
    Multiple session IDs must be separated by whitespaces.
    By default, the operation of closing connections is done asynchronously.
    Use option --wait to wait for connections to close.
    An error message will be displayed if no connection with the specified
    session ID is found.

OPTIONS
    --wait
        Wait for connection to close before existing.

    -h|--help
        Show this usage document.

EXAMPLES
    1. Close connections whose session IDs are d1d5cb63 and 92beac6e
       $ $SCRIPT_NAME close-connection --wait d1d5cb63 92beac6e
EOU

    return $_RET_VALUE
}

function __close_connection() {
    local _SUB_CMD=
    local _ASYNC_MODE=
    local _SESSION_IDS=
    local _CLI_CMD=
    local _RET_VALUE=

    _SUB_CMD="close-connection"
    _ASYNC_MODE="true"
    _RET_VALUE=0

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --wait)
                _ASYNC_MODE="false"
                ;;
            -h|--help)
                eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                return $_RET_VALUE
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done
    _SESSION_IDS="$@"

    __ascertain_server || return $?

    _CLI_CMD="$GERRIT_CLI $_SUB_CMD"
    if ! eval "$_ASYNC_MODE"; then
        _CLI_CMD="$_CLI_CMD --wait"
    fi

    for I in $(echo "$_SESSION_IDS"); do
        log_i "close SSH connection: $I"
        eval "echo $_CLI_CMD $I" || true
        echo
    done

    return $_RET_VALUE
}

function __print_usage_of_show_queue() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. $SCRIPT_NAME show-queue

DESCRIPTION
    Presents a table of all activities the Gerrit daemon is performing
    currently.
    The table contains three columns.
    1) Task
       A unique identifier of a task
    2) State
       - If a task is running, it's blank.
       - If a task has completed but has not yet been reaped, it's 'done'.
       - If a task has been killed but has not yet halted or removed, it's 'killed'.
       - If a task is ready to execute but is waiting for an idle thread, it's 'waiting'.
       - Otherwise, it's the time (local to the server) that a task will begin execution.
    3) Command
       Short text description of a task.

OPTIONS
    -h|--help
        Show this usage document.

EXAMPLES
    1. Show all activities
       $ $SCRIPT_NAME show-queue
EOU

    return $_RET_VALUE
}

function __show_queue() {
    local _SUB_CMD=
    local _CLI_CMD=
    local _RES_FILE=
    local _RET_VALUE=

    _SUB_CMD="show-queue"
    _RET_VALUE=0

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                return $_RET_VALUE
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done

    __ascertain_server || return $?

    _CLI_CMD="$GERRIT_CLI $_SUB_CMD -w"
    _RES_FILE=$(mktemp -p "/tmp" --suffix ".tasks" "queue.XXX")
    if eval "$_ASYNC_MODE" > "$_RES_FILE"; then
        if [ -s "$_RES_FILE" ]; then
            cat "$_RES_FILE"
        else
            log_i "the background work queue is empty"
        fi
    else
        _RET_VALUE=$ERROR_CODE_INSUFFICIENT_PERMISSION
    fi
    rm -f "$_RES_FILE"

    return $_RET_VALUE
}

function __print_usage_of_kill() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. $SCRIPT_NAME kill <TASK_ID> ...

DESCRIPTION
    Cancels a scheduled task from the background work queue.

OPTIONS
    -h|--help
        Show this usage document.

EXAMPLES
    1. Kill tasks whose IDs are d1d5cb63 and 92beac6e
       $ $SCRIPT_NAME kill d1d5cb63 92beac6e
EOU

    return $_RET_VALUE
}

function __kill() {
    local _SUB_CMD=
    local _TASK_IDS=
    local _CLI_CMD=
    local _RES_FILE=
    local _RET_VALUE=

    _SUB_CMD="kill"
    _RET_VALUE=0

    if [[ $# -eq 0 ]]; then
        eval "${CMD_USAGE_MAPPING[$_SUB_CMD]}"
        return $_RET_VALUE
    fi

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                return $_RET_VALUE
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done
    _TASK_IDS="$@"

    __ascertain_server || return $?

    _CLI_CMD="${GERRIT_CLI%" gerrit"} $_SUB_CMD"
    _RES_FILE=$(mktemp -p "/tmp" --suffix ".task" "kill.XXX")
    export -f log_e
    for I in $(echo "$_TASK_IDS"); do
        log_i "close task: $I"

        eval "$_CLI_CMD $I" > "$_RES_FILE" 2>&1
        if [ -s "$_RES_FILE" ]; then
            cat "$_RES_FILE" | xargs -d "\n" -I {} bash -c 'log_e "$@"' _ {}
        fi

        echo
    done
    rm -rf "$_RES_FILE"

    return $_RET_VALUE
}

function __print_usage_of_flush_caches() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. $SCRIPT_NAME flush-caches [-l|--list]
    2. $SCRIPT_NAME flush-caches [-a|--all]
    3. $SCRIPT_NAME flush-caches [-c|--cache <CACHE_NAME>]

DESCRIPTION
    Clears in-memory caches, forcing Gerrit to reconsult the ground truth when
    it needs the information again.

    The 1st format
        Shows a list of names of all caches.

    The 2nd format
        Flushes all known caches except cache "web_sessions".

    The 3rd format
        Flushes a specified cache called <CACHE_NAME>.

OPTIONS
    -a|--all
        Specify it to flush all known caches.

    -l|--list
        Specify it to show a list of of all known caches.

    -c|--cache <CACHE_NAME>
        Specify the name of a cache.

    -h|--help
        Show this usage document.

EXAMPLES
    1. List all caches
       $ $SCRIPT_NAME flush-caches --list

    2. Flush cache "web_sessions", forcing all users to sign-in again
       $ $SCRIPT_NAME flush-caches --cache web_sessions

    3. Flush all in-memory caches, forcing them to recompute
       $ $SCRIPT_NAME flush-caches --all
EOU

    return $_RET_VALUE
}

function __flush_caches() {
    local _SUB_CMD=
    local _ACTION=
    local _CACHE=
    local _CLI_CMD=
    local _RES_FILE=
    local _RET_VALUE=

    _SUB_CMD="flush-caches"
    _RET_VALUE=0

    if [[ $# -eq 0 ]]; then
        eval "${CMD_USAGE_MAPPING[$_SUB_CMD]}"
        return $_RET_VALUE
    fi

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                _ACTION="flush"
                _CACHE=""
                ;;
            -l|--list)
                _ACTION="show"
                ;;
            -c|--cache)
                _ACTION="flush"
                _CACHE="$2"
                ;;
            -h|--help)
                eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                return $_RET_VALUE
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done

    __ascertain_server || return $?

    _CLI_CMD="$GERRIT_CLI $_SUB_CMD"
    case "$_ACTION" in
        show)
            _CLI_CMD="$_CLI_CMD --list"
            eval "$_CLI_CMD"
            ;;
        flush)
            if [ -z "$_CACHE" ]; then
                _CLI_CMD="$_CLI_CMD --all"
            else
                _RES_FILE=$(mktemp -p "/tmp" --suffix ".list" "cache.XXX")
                eval "$_CLI_CMD --list" > "$_RES_FILE" 2>&1
                if grep -q "^$_CACHE$" "$_RES_FILE"; then
                    _CLI_CMD="$_CLI_CMD --cache $_CACHE"
                else
                    log_e "invalid cache name: $_CACHE"
                    _RET_VALUE=$ERROR_CODE_INVALID_CACHE_NAME_FOUND
                fi
                rm -f "$_RES_FILE"
            fi

            if [ "$_RET_VALUE" -eq 0 ]; then
                if eval "$_CLI_CMD"; then
                    log_i "cache flushed successfully"
                fi
            fi
            ;;
    esac

    return $_RET_VALUE
}

function __print_usage_of_show_caches() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    $SCRIPT_NAME show-caches [-g|--gc] [-j|--show-jvm] [-t|--show-threads]

DESCRIPTION
    Displays statistics about the size and hit ratio of in-memory caches.

OPTIONS
    -g|--gc
        Specify it to request Java garbage collection before displaying
        information about the Java memory heap.

    -j|--show-jvm
        Specify it to list the name and version of the Java virtual machine,
        host OS, and other details about the environment that Gerrit server is
        running in.

    -t|--show-threads
        Specify it to show the detailed counts for Gerrit specific threads.

    -h|--help
        Show this usage document.

EXAMPLES
    1. Display all caches along with JVM information and thread counts
       $ $SCRIPT_NAME show-caches --show-jvm --show-threads
EOU

    return $_RET_VALUE
}

function __show_caches() {
    local _SUB_CMD=
    local _SUB_CMD_OPTIONS=
    local _CLI_CMD=
    local _RES_FILE=
    local _RET_VALUE=

    _SUB_CMD="show-caches"
    _RET_VALUE=0

    if [[ $# -eq 0 ]]; then
        eval "${CMD_USAGE_MAPPING[$_SUB_CMD]}"
        return $_RET_VALUE
    fi

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--gc)
                _SUB_CMD_OPTIONS="$_SUB_CMD_OPTIONS --gc"
                ;;
            -j|--show-jvm)
                _SUB_CMD_OPTIONS="$_SUB_CMD_OPTIONS --show-jvm"
                ;;
            -t|--show-thread)
                _SUB_CMD_OPTIONS="$_SUB_CMD_OPTIONS --show-threads"
                ;;
            -h|--help)
                eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                return $_RET_VALUE
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done

    __ascertain_server || return $?

    _CLI_CMD="$GERRIT_CLI $_SUB_CMD $_SUB_CMD_OPTIONS"
    if ! eval "$_CLI_CMD"; then
        _RET_VALUE=$ERROR_CODE_INSUFFICIENT_PERMISSION
    fi

    return $_RET_VALUE
}

function __init_command_context() {
    # Maps sub-command to its usage
    CMD_USAGE_MAPPING["create-branch"]="__print_usage_of_create_branch"
    CMD_USAGE_MAPPING["ls-user-refs"]="__print_usage_of_ls_user_refs"
    CMD_USAGE_MAPPING["show-connections"]="__print_usage_of_show_connections"
    CMD_USAGE_MAPPING["close-connection"]="__print_usage_of_close_connection"
    CMD_USAGE_MAPPING["show-queue"]="__print_usage_of_show_queue"
    CMD_USAGE_MAPPING["kill"]="__print_usage_of_kill"
    CMD_USAGE_MAPPING["flush-caches"]="__print_usage_of_flush_caches"
    CMD_USAGE_MAPPING["show-caches"]="__print_usage_of_show_caches"

    # Maps sub-command to its options
    CMD_OPTION_MAPPING["create-branch"]="-o p:b:r:f:\
        -l project:,branch:,revision:,file:"
    CMD_OPTION_MAPPING["ls-user-refs"]="-o p:u:bth\
        -l project:,user:,branch-only,tag-only,help"
    CMD_OPTION_MAPPING["show-connections"]="-o nh\
        -l numeric,help"
    CMD_OPTION_MAPPING["close-connection"]="-o h\
        -l wait,help"
    CMD_OPTION_MAPPING["show-queue"]="-o h\
        -l help"
    CMD_OPTION_MAPPING["kill"]="-o h\
        -l help"
    CMD_OPTION_MAPPING["flush-caches"]="-o alc:h\
        -l all,list,cache:,help"
    CMD_OPTION_MAPPING["show-caches"]="-o jtgh\
        -l show-jvm,show-threads,gc,help"

    # Maps sub-command to the implementation of its function
    CMD_FUNCTION_MAPPING["create-branch"]="__create_branch"
    CMD_FUNCTION_MAPPING["ls-user-refs"]="__ls_user_refs"
    CMD_FUNCTION_MAPPING["show-connections"]="__show_connections"
    CMD_FUNCTION_MAPPING["close-connection"]="__close_connection"
    CMD_FUNCTION_MAPPING["show-queue"]="__show_queue"
    CMD_FUNCTION_MAPPING["kill"]="__kill"
    CMD_FUNCTION_MAPPING["flush-caches"]="__flush_caches"
    CMD_FUNCTION_MAPPING["show-caches"]="__show_caches"
}

function __print_cli_usage() {
    cat << EOU
Usage: $SCRIPT_NAME <SUB_COMMAND> [<args>]

These are sub-commands wrapped in the script. Each one has a corresponding
Gerrit command whose official document can be found wihin a Gerrit release.
1. create-branch
   Creates a new branch for a project.
2. ls-user-refs
   Lists all refs (branches and tags) accessible for a specified user.
3. show-connections
   Display active SSH connections of all clients.
4. close-connection
   Close the specified SSH connections.
5. show-queue
   Display all activities of the background work queue.
6. kill
   Cancel or abort a background task
7. flush-caches
   Flush server caches from memory
8. show-caches
   Display statistics about the size and hit ratio of in-memory caches.

To show usage of a <SUB_COMMAND>, use following command:
   $SCRIPT_NAME help <SUB_COMMAND>
   $SCRIPT_NAME <SUB_COMMAND> --help
EOU
}

function __run_cli() {
    local _SUB_CMD=
    local _FOUND=
    local _RET_VALUE=

    _FOUND="false"
    _RET_VALUE=0

    #set -x
    _SUB_CMD="$1"
    if [[ -z "$_SUB_CMD" ]]; then
        __print_cli_usage
    elif [[ "$_SUB_CMD" == "--help" ]]; then
        __print_cli_usage
    else
        for I in ${!CMD_OPTION_MAPPING[@]}; do
            if [[ "$_SUB_CMD" = $I ]]; then
                _FOUND="true"
                break
            fi
        done

        if eval "$_FOUND"; then
            if __check_config; then
                shift
                eval ${CMD_FUNCTION_MAPPING["$_SUB_CMD"]} $*
            else
                _RET_VALUE=$?
            fi
        else
            if [[ "$_SUB_CMD" == "help" ]]; then
                shift
                _SUB_CMD="$1"

                _FOUND="false"
                for I in ${!CMD_OPTION_MAPPING[@]}; do
                    if [[ "$_SUB_CMD" = $I ]]; then
                        _FOUND="true"
                        break
                    fi
                done

                if eval "$_FOUND"; then
                    eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                else
                    if [[ -z "$_SUB_CMD" ]]; then
                        __print_cli_usage
                    else
                        _RET_VALUE=$ERROR_CODE_COMMAND_NOT_SUPPORTED
                        log_e "unsupported sub-command: '$_SUB_CMD'"
                    fi
                fi
            else
                _RET_VALUE=$ERROR_CODE_COMMAND_NOT_SUPPORTED
                log_e "unsupported sub-command: '$_SUB_CMD'"
            fi
        fi
    fi

    return $_RET_VALUE
}

############# ENTRY POINT #############
__init_command_context
__run_cli $*

# vim: set shiftwidth=4 tabstop=4 expandtab
