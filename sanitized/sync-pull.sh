#!/bin/bash

DTG=$(date -Iseconds)
HOST=$(hostname)
SUCCESS_LOG=${HOME}/.SCRIPTLOGS/sync.pull.log
ERROR_LOG=${HOME}/ERROR-sync-error.log
RSYNC_OPTIONS="-avhur --mkpath --exclude={'*.swp','/plugins'}"
LOCALDIR=$HOME/syncdir
sync_dirs () {
        rsync $RSYNC_OPTIONS $REMOTEDIR $LOCALDIR  &&
        ### you can additional directories to sync however you want - e.g.,
        ### rsync $RSYNC_OPTIONS /different/remote/dir $HOME/different-local-dir &&
        echo "${DTG} sync (PULL) completed on ${HOST}" | tee $SUCCESS_LOG
}


if [ -e /Volumes/some/remote/dir ]; then ## checking to see if remote directory exists and check OS
        REMOTEDIR=/Volumes/[mounted remote dir] && ## confirmed we're on a Mac
        echo "This is on  ${HOST}, sync.sec PULLING FROM <- $REMOTEDIR" | tee $SUCCESS_LOG &&
        sync_dirs

elif [ -e /mnt/some/remote/dir ]; then  ## now checking if host is linux instead
        REMOTEDIR=/mnt/some/remote/dir &&  ## confirmed linux
        echo "This is on   🦅 ${HOST}, sync.sec PULLING FROM <- $REMOTEDIR" | tee $SUCCESS_LOG &&
        sync_dirs
else
        echo "${DTG} FAILED conditions for sync (PULL) on ${HOST}" | tee $ERROR_LOG
fi
