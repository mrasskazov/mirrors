#!/bin/bash -xe

export LANG=C

# define this vars before use
RSYNCHOST=${RSYNCHOST:-""}
RSYNCUSER=${RSYNCUSER:-""}
RSYNCROOT=fwm
FILESROOT=fwm/files
SRCDIR=${SRCDIR:-""}

export DATE=$(date "+%Y-%m-%d-%H%M%S")
export SAVE_LAST_DAYS=${SAVE_LAST_DAYS:-61}
export WARN_DATE=$(date "+%Y%m%d" -d "$SAVE_LAST_DAYS days ago")


function get_empty_dir() {
    EMPTY_DIR=${EMPTY_DIR:-$(mktemp -d)}
    echo $EMPTY_DIR
}

function get_symlink() {
    local TARGET=$1
    local LINKNAME=$(mktemp -u)
    ln -s --force $TARGET $LINKNAME && echo $LINKNAME
}

######################################################
function rsync_delete_file() {
    local FILENAME=$(basename $1)
    local FILEPATH=$(dirname $1)
    rsync -rv --delete --include=$FILENAME '--exclude=*' \
        $(get_empty_dir)/ $RSYNCHOST::$RSYNCUSER/$FILESROOT/$FILEPATH/
}

function rsync_delete_dir() {
    local DIRNAME=$1
    rsync --delete -a $(get_empty_dir)/ $RSYNCHOST::$RSYNCUSER/$FILESROOT/$DIRNAME/ \
        && rsync_delete_file $DIRNAME
}

function rsync_list() {
    DIR=$1
    rsync -l $RSYNCHOST::$RSYNCUSER/$DIR/ | grep -v '\.$'
}

function list_links() {
    rsync_list $1 | grep '^l' | awk '{print $(NF-2)" "$NF}'
}

function list_dirs() {
    rsync_list $1 | grep '^d' | awk '{print $NF}'
}

function list_files() {
    rsync_list $1 | grep -vE '^d|^l' | awk '{print $NF}'
}

######################################################
function clear_old_versions() {
    # Clear mirrors older then $SAVE_LAST_DAYS and w/o symlinks on self
    DIRS=$(list_dirs $FILESROOT)
    for d in $DIRS; do
        #ddate=$(echo $d | awk -F '[-]' '{print $2$3$4}')
        ddate=$(echo $d | awk -F '[-]' '{print $(NF-3)$(NF-2)$(NF-1)}')
        [ "$ddate" -gt "$WARN_DATE" ] && continue
        LINKS=$(list_links $FILESROOT | grep $d ; list_links $RSYNCROOT | grep "$(basename $FILESROOT)/$d")
        if [ "$LINKS" = "" ]; then
            rsync_delete_dir $d
            continue
        fi
        echo "skip because symlinks $LINKS points to $d"
    done
}

######################################################
function job_lock() {
    local LOCKFILE=/tmp/$1
    shift
    fd=15
    eval "exec $fd>$LOCKFILE"
    case $1 in
        "set")
            flock -x -n $fd \
                || error_message "Process already running. Lockfile: $LOCKFILE"
            ;;
        "unset")
            flock -u $fd
            ;;
        "wait")
            TIMEOUT=${2:-3600}
            echo "Waiting of concurrent process (lockfile: $LOCKFILE, timeout = $TIMEOUT seconds) ..."
            flock -x -w $TIMEOUT $fd \
                && echo DONE \
                || error_message "Timeout error (lockfile: $LOCKFILE)"
            ;;
    esac
}

function fatal() {
    echo "$@"
    rsync_delete_dir $TGTDIR
    exit 1
}

function error_message() {
    echo "$@"
    exit 1
}

function success() {
    local LOCKNAME=$1
    shift
    rsync_delete_file $PROJECTNAME-staging \
        && rsync -l $(get_symlink $TGTDIR) $RSYNCHOST::$RSYNCUSER/$FILESROOT/$PROJECTNAME-staging \
        && echo 'Synced to: <a href="http://'$RSYNCHOST'/'$FILESROOT'/'$TGTDIR'">'$TGTDIR'</a>' \
        && clear_old_versions
}

######################################################
function rsync_transfer() {
    SRCDIR=$1
    RSYNCHOST=$2
    PROJECTNAME=${PROJECTNAME:-$mirror}
    export TGTDIR=${3:-"$PROJECTNAME-$DATE"}

    OPTIONS="--archive --verbose --force --ignore-errors --delete-excluded --no-owner --no-group
          ${RSYNC_EXTRA_PARAMS} --delete --link-dest=/$FILESROOT/$PROJECTNAME-staging"

    rsync $OPTIONS $SRCDIR/ $RSYNCHOST::$RSYNCUSER/$FILESROOT/$TGTDIR \
        && success $LOCKFILE \
        || fatal "sync failed"
}
