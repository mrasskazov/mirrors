#/bin/bash
fatal() {
  echo "$@"
  /bin/rm -f ~/rsync_updates
  exit 1
}

warn() {
  echo "$1"
}

# Find a source mirror near you which supports rsync on
# https://launchpad.net/ubuntu/+archivemirrors
# rsync://<iso-country-code>.rsync.archive.ubuntu.com/ubuntu should always work
#RSYNCSOURCE=rsync://ru.rsync.archive.ubuntu.com/ubuntu
RSYNCSOURCE=rsync://mirrors.msk.mirantis.net/mirrors/ubuntu
# Define where you want the mirror-data to be on your mirror
BASEDIR=/media/mirrors/mirrors/ubuntu/

if [ -f ~/rsync_updates ]; then
    echo "Updates via rsync already running."
    exit 0
fi

if [ ! -d ${BASEDIR} ]; then
  warn "${BASEDIR} does not exist yet, trying to create it..."
  mkdir -p ${BASEDIR} || fatal "Creation of ${BASEDIR} failed."
fi

touch ~/rsync_updates
rsync --progress --recursive --times --links --hard-links \
  --stats \
  --exclude "Packages*" --exclude "Sources*" \
  --exclude "Release*" \
  ${RSYNCSOURCE} ${BASEDIR} || fatal "First stage of sync failed."
rsync --progress --recursive --times --links --hard-links \
  --stats --delete \
  ${RSYNCSOURCE} ${BASEDIR} || fatal "Second stage of sync failed."
date -u > ${BASEDIR}/project/trace/$(hostname -f)
/bin/rm -f ~/rsync_updates
