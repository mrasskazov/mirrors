#!/bin/bash -x

export LANG=C

[ -z "$MIRROR" ] && exit 1
[ -z "$STABLE_VERSION" ] && exit 1

TOP_DIR=$(cd $(dirname "$0") && pwd)
source $TOP_DIR/rsync_functions.sh

SYMLINK_FILE=$(get_symlink "files/$STABLE_VERSION")
STABLE_SYMLINK_FILE=$(get_symlink "$STABLE_VERSION")

RSYNCUSER=mirror-sync
RSYNCROOT=fwm
FILESROOT=fwm/files

mirrors_fail=""

echo "mirror:
    name: ${MIRROR}
    stable: ${STABLE_VERSION}" > ${MIRROR}.yaml.txt

for RSYNCHOST in $RSYNCHOSTS; do
    STABLE_EXISTS="$(rsync $RSYNCHOST::$RSYNCUSER/$FILESROOT/ \
        | awk '/^d.* '$STABLE_VERSION'$/ {print $NF}')"
    STABLE_EXISTS="${STABLE_EXISTS}$(rsync -l $RSYNCHOST::$RSYNCUSER/$FILESROOT/ \
        | awk '/^l.* '$STABLE_VERSION' .*/ {print $NF}')"
    if [ -n "$STABLE_EXISTS" ]; then
        rsync -rv --delete --include=$MIRROR '--exclude=*' \
            $(get_empty_dir)/ $RSYNCHOST::$RSYNCUSER/$RSYNCROOT/ \
            && rsync -vl $SYMLINK_FILE $RSYNCHOST::$RSYNCUSER/$RSYNCROOT/$MIRROR \
            && rsync -vl $STABLE_SYMLINK_FILE $RSYNCHOST::$RSYNCUSER/$FILESROOT/${STABLE_VERSION}-stable \
            && rsync -v ${MIRROR}.yaml.txt $RSYNCHOST::$RSYNCUSER/$RSYNCROOT/ \
            || mirrors_fail+=" $RSYNCHOST"
    else
        mirrors_fail+=" $RSYNCHOST"
    fi
done

if [[ -n "$mirrors_fail" ]]; then
  echo Some mirrors failed to update: $mirrors_fail
  rm $WORKSPACE/build_description.txt
  exit 1
else
  echo ${STABLE_VERSION}' is stable.<br> <a href="http://mirror.fuel-infra.org//'$FILESROOT'/'$STABLE_VERSION'">'usa_ext'</a> <a href="http://osci-mirror-msk.msk.mirantis.net/'$FILESROOT'/'$STABLE_VERSION'">'msk'</a> <a href="http://osci-mirror-srt.srt.mirantis.net/'$FILESROOT'/'$STABLE_VERSION'">'srt'</a> <a href="http://osci-mirror-kha.kha.mirantis.net/'$FILESROOT'/'$STABLE_VERSION'">'kha'</a>'
  echo ${STABLE_VERSION}' is stable.<br> <a href="http://mirror.fuel-infra.org//'$FILESROOT'/'$STABLE_VERSION'">'usa_ext'</a> <a href="http://osci-mirror-msk.msk.mirantis.net/'$FILESROOT'/'$STABLE_VERSION'">'msk'</a> <a href="http://osci-mirror-srt.srt.mirantis.net/'$FILESROOT'/'$STABLE_VERSION'">'srt'</a> <a href="http://osci-mirror-kha.kha.mirantis.net/'$FILESROOT'/'$STABLE_VERSION'">'kha'</a>' > $WORKSPACE/build_description.txt
fi
