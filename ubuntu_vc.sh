#!/bin/bash -x

fatal() {
  echo "$@"
  /bin/rm -f /tmp/${SRC_OS}_updates
  exit 1
}

export SRC_OS=ubuntu
export SRC="rsync://mirrors.msk.mirantis.net/mirrors/${SRC_OS}/"

#export EXCLUDE="--exclude \"Packages*\" --exclude \"Sources*\" --exclude \"Release*\""

export DATE=$(date "+%Y-%m-%d-%H%M%S")

export DST=/media/mirrors/mirrors
export DST_TMP=$DST/files/$SRC_OS-processing-$DATE
export DST_DIR=$DST/files/$SRC_OS-$DATE

if [ -f /tmp/${SRC_OS}_updates ]; then
    echo "Updates via rsync already running."
    exit 0
fi

touch /tmp/${SRC_OS}_updates

(rsync --verbose \
      --quiet \
      --archive \
      --progress \
      --delete \
      --numeric-ids \
      --acls \
      --xattrs \
      --link-dest=../../$SRC_OS \
      --sparse \
      $EXCLUDE \
      $SRC \
      $DST_TMP \
&& cd $DST \
&& mv $DST_TMP $DST_DIR \
&& rm -f $DST/$SRC_OS \
&& ln -s $DST_DIR $DST/$SRC_OS \
&& /bin/rm -f /tmp/${SRC_OS}_updates) \
|| \
fatal "rsync failed"

#&& date -u > $DST_DIR/project/trace/$(hostname -f) \
