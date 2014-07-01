#!/bin/bash

export LANG=C
export SYNCTYPE=rsync

export SAVE_LAST_DAYS=${2:-10}

export DATE=$(date "+%Y-%m-%d-%H%M%S")
export WARN_DATE=$(date "+%Y%m%d" -d "$SAVE_LAST_DAYS days ago")

export DST=${DST:-/media/mirrors/mirrors}
export DST_TMP=$DST/files/$SRC_MIRR-processing-$DATE
export REPO=$SRC_MIRR-$DATE
export DST_DIR=$DST/files/$REPO
export LATEST=$DST/files/$SRC_MIRR-latest


function past_download() {
    return 0
}

function job_lock() {
    LOCKFILE=/tmp/${SRC_MIRR}_updates
    if [ "$1" = "set" ]; then
        if [ -f $LOCKFILE ]; then
            echo "Updates via rsync already running."
            exit 0
        fi
        echo "$SRC" > $LOCKFILE
    elif [ "$1" = "unset" ]; then
        rm -f $LOCKFILE
    fi
}

function fatal() {
  echo "$@"
  rm -f /tmp/${SRC_MIRR}_updates
  rm -rf $DST_TMP
  exit 1
}

function success() {
    cd $DST \
    && mv $DST_TMP $DST_DIR \
    && rm -f $LATEST \
    && ln -s $DST_DIR $LATEST \
    && past_download \
    && echo 'Synced to: <a href="http://mirrors-local-msk.msk.mirantis.net/files/'$REPO'">'$REPO'</a>'
}

function clear_old_versions() {
    # Clear mirrors older then $SAVE_LAST_DAYS and w/o symlinks on self
    DIRS=$(find -H $DST/files/ -maxdepth 1 -type d -name $SRC_MIRR\* -mtime +$SAVE_LAST_DAYS | sort -nr)
    for d in $DIRS; do
        ddate=$(echo $d | awk -F '[-]' '{print $2$3$4}')
        [ "$ddate" -gt "$WARN_DATE" ] && continue
        fd=$(readlink -f $d)
        LINKS=$(find -H $DST/files/ -maxdepth 1 -type l -xtype d -lname $fd; find -H $DST -maxdepth 1 -type l -xtype d -lname $fd)
        if [ "$LINKS" = "" ]; then
            rm -rf $fd
            continue
        fi
        echo "skip because symlinks $LINKS points to $fd"
    done
}

function via_rsync() {
    rsync --verbose \
          --archive \
          --delete \
          --numeric-ids \
          --acls \
          --xattrs \
          --link-dest=$LATEST \
          --sparse \
          $EXCLUDE \
          $SRC \
          $DST_TMP \
    && success \
    || fatal "rsync failed"
}

function via_wget() {
    cp -rl $(readlink -f $LATEST) $DST_TMP
         #--timestamping \
         #--no-verbose \
    wget --mirror \
         --no-parent \
         --convert-links \
         --progress=dot:mega \
         $EXCLUDE \
         --no-host-directories \
         --directory-prefix=$DST_TMP \
         -i $LOCKFILE \
    && success \
    || fatal "wget failed"
}
