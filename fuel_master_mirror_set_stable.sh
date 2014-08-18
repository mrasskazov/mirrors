#!/bin/bash -x

export LANG=C

[ -z "$MIRROR" ] && exit 1
[ -z "$STABLE_VERSION" ] && exit 1

TOP_DIR=$(cd $(dirname "$0") && pwd)
source $TOP_DIR/rsync_functions.sh

SYMLINK_FILE=$(get_symlink "files/$STABLE_VERSION")

RSYNCUSER=ostf-mirror
RSYNCROOT=fwm
FILESROOT=fwm/files

mirrors_fail=""

for RSYNCHOST in $RSYNCHOSTS; do
    STABLE_EXISTS="$(rsync $RSYNCHOST::$RSYNCUSER/$FILESROOT/ \
        | awk '/^d.* '$STABLE_VERSION'$/ {print $NF}')"
    STABLE_EXISTS="${STABLE_EXISTS}$(rsync -l $RSYNCHOST::$RSYNCUSER/$FILESROOT/ \
        | awk '/^l.* '$STABLE_VERSION' .*/ {print $NF}')"
    if [ -n "$STABLE_EXISTS" ]; then
        rsync -rv --delete --include=$MIRROR '--exclude=*' \
            $(get_empty_dir)/ $RSYNCHOST::$RSYNCUSER/$RSYNCROOT/ \
            && rsync -vl $SYMLINK_FILE $RSYNCHOST::$RSYNCUSER/$RSYNCROOT/$MIRROR \
            || mirrors_fail+=" $RSYNCHOST"
    else
        mirrors_fail+=" $RSYNCHOST"
    fi
done

if [[ -n "$mirrors_fail" ]]; then
  echo Some mirrors failed to update: $mirrors_fail
  exit 1
fi
