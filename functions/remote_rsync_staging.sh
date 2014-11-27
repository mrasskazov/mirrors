#!/bin/bash -xe

export LANG=C

TOP_DIR=$(cd $(dirname "$0") && pwd)
source $TOP_DIR/remote_rsync_staging_config.sh
source $TOP_DIR/functions/locking.sh

STAGING_SAVE_LAST_DAYS=${STAGING_SAVE_LAST_DAYS:-61}
STAGING_POSTFIX=${STAGING_POSTFIX:-"staging"}

STAGING_VERSION_STAMP=${STAGING_VERSION_STAMP:-$(date "+%Y-%m-%d-%H%M%S")}
STAGING_VERSION_STAMP_REGEXP=${STAGING_VERSION_STAMP_REGEXP:-'[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}'}

RSYNC_STAGING_EXTRA_PARAMS=${RSYNC_STAGING_EXTRA_PARAMS:-""}

RSYNC_MIRROR_HOST=${RSYNC_MIRROR_HOST:-''}
RSYNC_MIRROR_USER=${RSYNC_MIRROR_USER:-'mirror-sync'}
RSYNC_MIRROR_ROOTDIR=${RSYNC_MIRROR_ROOTDIR:-'fwm'}
RSYNC_MIRROR_FILESDIR=${RSYNC_MIRROR_FILESDIR:-'files'}
STAGING_POSTFIX=${STAGING_POSTFIX:-'staging'}

if [ "$(echo "${STAGING_VERSION_STAMP}" | grep -E "^${STAGING_VERSION_STAMP_REGEXP}$")" != "${STAGING_VERSION_STAMP}" ]; then
    exit_with_error "Wrong STAGING_VERSION_STAMP_REGEXP = '${STAGING_VERSION_STAMP_REGEXP}' defined"
fi
WARN_DATE=$(date "+%Y%m%d" -d "$STAGING_SAVE_LAST_DAYS days ago")

######################################################
function rsync_check_url () {
    [ -z "$RSYNC_MIRROR_HOST" ] && exit_with_error "rsync_set_url error: RSYNC_MIRROR_HOST is empty"
}

function rsync_set_host () {
    export RSYNC_MIRROR_HOST=${1:-$RSYNC_MIRROR_HOST}
    rsync_check_url
}

function rsync_get_url () {
    rsync_check_url
    echo "$RSYNC_MIRROR_HOST::$RSYNC_MIRROR_USER"
}

function rsync_get_root_dir () {
    rsync_check_url
    echo "$(rsync_get_url)/$RSYNC_MIRROR_ROOTDIR"
}

function rsync_get_files_dir () {
    rsync_check_url
    echo "$(rsync_get_root_dir)/$RSYNC_MIRROR_FILESDIR"
}

function rsync_get_http_url(){
    echo -e "http://$RSYNC_MIRROR_HOST/$RSYNC_MIRROR_ROOTDIR/$RSYNC_MIRROR_FILESDIR/$TGT_LINK_NAME-$STAGING_VERSION_STAMP"
}

function rsync_get_html_link(){
    #Parameters: HOST_SHORT_NAME
    local HOST_SHORT_NAME=$1
    echo -e "<a href='$(rsync_get_http_url)'>$HOST_SHORT_NAME</a>"
}

######################################################

function get_empty_dir() {
    export EMPTY_DIR=${EMPTY_DIR:-$(mktemp -d)}
    echo $EMPTY_DIR
}

function get_symlink() {
    local TARGET=$1
    local LINKNAME=$(mktemp -u)
    ln -s --force $TARGET $LINKNAME && echo $LINKNAME
}

######################################################
function rsync_delete_file() {
    rsync_check_url
    local FILENAME=$(basename $1)
    local FILEPATH=$(dirname $1)
    rsync -rv --delete --include=$FILENAME '--exclude=*' \
        $(get_empty_dir)/ $(rsync_get_files_dir)/$FILEPATH/
}

function rsync_delete_dir() {
    rsync_check_url
    local DIRNAME=$1
    rsync --delete -a $(get_empty_dir)/ $(rsync_get_files_dir)/$DIRNAME/ \
        && rsync_delete_file $DIRNAME
}

function rsync_list() {
    rsync_check_url
    local DIR=$1
    rsync -l $(rsync_get_url)/$DIR/ | grep -v '\.$'
}

function list_links() {
    rsync_check_url
    rsync_list $1 | grep '^l' | awk '{print $(NF-2)" "$NF}'
}

function list_dirs() {
    rsync_check_url
    rsync_list $1 | grep '^d' | awk '{print $NF}'
}

function list_files() {
    rsync_check_url
    rsync_list $1 | grep -vE '^d|^l' | awk '{print $NF}'
}

######################################################
function rsync_clear_old_versions() {
    # Clear mirrors older then $STAGING_SAVE_LAST_DAYS and w/o symlinks on self
    rsync_check_url
    local TGT_LINK_NAME=$1
    local DIRS=$(list_dirs $RSYNC_MIRROR_FILESDIR | grep -E "^${TGT_LINK_NAME}-${STAGING_VERSION_STAMP_REGEXP}")
    for d in $DIRS; do
        local ddate=$(echo $d | awk -F '[-]' '{print $(NF-3)$(NF-2)$(NF-1)}')
        [ "$ddate" -gt "$WARN_DATE" ] && continue
        local LINKS=$(list_links $RSYNC_MIRROR_FILESDIR | grep $d ; list_links $RSYNC_MIRROR_ROOTDIR | grep "$(basename $RSYNC_MIRROR_FILESDIR)/$d")
        if [ "$LINKS" = "" ]; then
            rsync_delete_dir $d
            continue
        fi
        echo "skip because symlinks $LINKS points to $d"
    done
}

######################################################
function rsync_fatal() {
    rsync_check_url
    local STAGING_DIR_NAME="$1"
    rsync_delete_dir $STAGING_DIR_NAME
    exit_with_error "$@"
}

function rsync_success() {
    # pararmaters: TGT_LINK_NAME STAGING_DIR_NAME
    rsync_check_url
    local TGT_LINK_NAME="$1"
    local STAGING_DIR_NAME="$2"
    rsync_delete_file $TGT_LINK_NAME-$STAGING_POSTFIX \
        && rsync -l $(get_symlink $STAGING_DIR_NAME) $(rsync_get_files_dir)/$TGT_LINK_NAME-$STAGING_POSTFIX \
        && rsync_clear_old_versions $TGT_LINK_NAME
}

######################################################
function rsync_staging_transfer() {
    # Parameters: SOURCE_DIR RSYNC_HOST_NAME TARGET_LINK_NAME
    local SOURCE_DIR=$1
    [ -n "$2" ] && rsync_set_host $2
    local TGT_LINK_NAME=$3
    local STAGING_DIR_NAME="$TGT_LINK_NAME-$STAGING_VERSION_STAMP"

    OPTIONS="--archive --verbose --force --ignore-errors --delete-excluded --no-owner --no-group
          ${RSYNC_STAGING_EXTRA_PARAMS} --delete
          --link-dest=/$RSYNC_MIRROR_ROOTDIR/$RSYNC_MIRROR_FILESDIR/$TGT_LINK_NAME-$STAGING_POSTFIX"

    job_lock ${RSYNC_MIRROR_HOST}-${STAGING_DIR_NAME}-syncing.lock set
    rsync $OPTIONS $SOURCE_DIR/ $(rsync_get_files_dir)/$STAGING_DIR_NAME \
        && rsync_success $TGT_LINK_NAME \
        || rsync_fatal "sync failed"
}
