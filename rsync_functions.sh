#!/bin/bash -xe

export LANG=C

# define this vars before use
RSYNCHOST=${RSYNCHOST:-""}
RSYNCUSER=${RSYNCUSER:-""}
RSYNCROOT=fwm
FILESROOT=fwm/files
SRCDIR=${SRCDIR:-""}

export DATE=$(date "+%Y-%m-%d-%H%M%S")
export SAVE_LAST_DAYS=${SAVE_LAST_DAYS:-31}
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
    if [ "$1" = "set" ]; then
        if [ -f $LOCKFILE ]; then
            echo "Updates via rsync already running ($LOCKFILE)."
            exit 1
        fi
        echo "$SRC" > $LOCKFILE
    elif [ "$1" = "unset" ]; then
        rm -f $LOCKFILE
    fi
}

function fatal() {
    local LOCKNAME=$1
    shift
    echo "$@"
    rsync_delete_dir $TGTDIR
    job_lock $LOCKNAME unset
    exit 1
}

function success() {
    local LOCKNAME=$1
    shift
    rsync_delete_file $PROJECTNAME-staging \
        && rsync -l $(get_symlink $TGTDIR) $RSYNCHOST::$RSYNCUSER/$FILESROOT/$PROJECTNAME-staging \
        && echo 'Synced to: <a href="http://'$RSYNCHOST'/'$FILESROOT'/'$TGTDIR'">'$TGTDIR'</a>' \
        && clear_old_versions \
        && job_lock $LOCKNAME unset
}

######################################################
function rsync_transfer() {
    SRCDIR=$1
    RSYNCHOST=${RSYNCHOST:-$2}
    PROJECTNAME=$(basename $SRCDIR)
    export TGTDIR=${3:-"$PROJECTNAME-$DATE"}

    OPTIONS="--verbose --force --ignore-errors --delete-excluded --exclude-from=$EXCLUDES
          --delete --link-dest=/$FILESROOT/$PROJECTNAME-staging -a"

    LOCKFILE=$PROJECTNAME.lock
    job_lock $LOCKFILE set
    rsync $OPTIONS $SRCDIR/ $RSYNCHOST::$RSYNCUSER/$FILESROOT/$TGTDIR \
        && success $LOCKFILE \
        || fatal $LOCKFILE "sync failed"
}
