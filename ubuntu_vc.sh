#!/bin/bash -x

fatal() {
  echo "$@"
  /bin/rm -f /tmp/${SRC_OS}_updates
  /bin/rm -rf $DST_TMP
  exit 1
}

export SRC_OS=ubuntu
export SRC="rsync://mirrors.msk.mirantis.net/mirrors/${SRC_OS}/"

#export EXCLUDE="--exclude \"Packages*\" --exclude \"Sources*\" --exclude \"Release*\""

export DATE=$(date "+%Y-%m-%d-%H%M%S")

export DST=/media/mirrors/mirrors
export DST_TMP=$DST/files/$SRC_OS-processing-$DATE
export REPO=$SRC_OS-$DATE
export DST_DIR=$DST/files/$REPO
export LATEST=$DST/files/$SRC_OS-latest

if [ -f /tmp/${SRC_OS}_updates ]; then
    echo "Updates via rsync already running."
    exit 0
fi

touch /tmp/${SRC_OS}_updates

(rsync --verbose \
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
&& cd $DST \
&& mv $DST_TMP $DST_DIR \
&& rm -f $LATEST \
&& ln -s $DST_DIR $LATEST \
&& date -u > $DST_DIR/project/trace/$(hostname -f) \
&& /bin/rm -f /tmp/${SRC_OS}_updates \
&& echo 'Synced to: <a href="http://mirrors-local-msk.msk.mirantis.net/files/'$REPO'">'$REPO'</a>') \
|| \
fatal "rsync failed"

