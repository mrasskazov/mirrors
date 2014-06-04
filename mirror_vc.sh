#!/bin/bash -xv

fatal() {
  echo "$@"
  /bin/rm -f /tmp/${SRC_MIRR}_updates
  /bin/rm -rf $DST_TMP
  exit 1
}

export SRC_MIRR=${1:-Unknown}
export SAVE_LAST_DAYS=${2:-10}


case "$SRC_MIRR" in
    "ubuntu")
        SYNCTYPE=rsync
        export SRC="rsync://mirrors.msk.mirantis.net/mirrors/${SRC_MIRR}/"
        function additional() {
            date -u > $DST_DIR/project/trace/$(hostname -f)
        }
        #export EXCLUDE="--exclude \"Packages*\" --exclude \"Sources*\" --exclude \"Release*\""
        ;;
    "centos")
        SYNCTYPE=rsync
        export SRC="rsync://mirrors.msk.mirantis.net/mirrors/${SRC_MIRR}/"
        function additional() {
            return 0
        }
        #export EXCLUDE="--exclude \"local*\" --exclude \"isos\""
        ;;
    "docker")
        SYNCTYPE=rsync
        export SRC="rsync://mirror.yandex.ru/mirrors/${SRC_MIRR}/"
        function additional() {
            return 0
        }
        export EXCLUDE='--exclude .temp --exclude .lastsync --exclude .mirror.yandex.ru'
        ;;
    "jenkins")
        SYNCTYPE=wget
        export SRC="http://pkg.jenkins-ci.org/debian-stable/"
        function additional() {
            return 0
        }
        #export EXCLUDE=''
        ;;
    *)
        fatal "Wrong source mirror '$SRC_MIRR'"
esac

export DATE=$(date "+%Y-%m-%d-%H%M%S")
export WARN_DATE=$(date "+%Y%m%d" -d "$SAVE_LAST_DAYS days ago")

export DST=${DST:-/media/mirrors/mirrors}
export DST_TMP=$DST/files/$SRC_MIRR-processing-$DATE
export REPO=$SRC_MIRR-$DATE
export DST_DIR=$DST/files/$REPO
export LATEST=$DST/files/$SRC_MIRR-latest


success() {
    cd $DST \
    && mv $DST_TMP $DST_DIR \
    && rm -f $LATEST \
    && ln -s $DST_DIR $LATEST \
    && additional \
    && echo 'Synced to: <a href="http://mirrors-local-msk.msk.mirantis.net/files/'$REPO'">'$REPO'</a>'
}

via_rsync() {
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

via_wget() {
    cp -rl $(readlink -f $LATEST) $DST_TMP
         #--timestamping \
    wget --mirror \
         --no-parent \
         --convert-links \
         --no-verbose \
         $EXCLUDE \
         --no-host-directories \
         --directory-prefix=$DST_TMP \
         $SRC \
    && success \
    || fatal "wget failed"
}


if [ -f /tmp/${SRC_MIRR}_updates ]; then
    echo "Updates via rsync already running."
    exit 0
fi

touch /tmp/${SRC_MIRR}_updates
via_$SYNCTYPE
rm -f /tmp/${SRC_MIRR}_updates


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
