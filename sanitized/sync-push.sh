#!/bin/bash

DTG=$(date -Iseconds)
HOST=$(hostname)
SUCCESS_LOG=.SCRIPTLOGS/sync.push.log
ERROR_LOG=ERROR-sync-error.log
RSYNC_OPTIONS="-avhur --mkpath --exclude={'*.swp','/plugins'}"
sync_dirs () {
        rsync $RSYNC_OPTIONS $HOME'/.secrets/' $SYNC_SEC_PATH'/.secrets/'  &&
#        rsync $RSYNC_OPTIONS $HOME'/.zsh-custom/' $SYNC_SEC_PATH'/.zsh-custom/'  &&
#        rsync $RSYNC_OPTIONS $SYNC_SEC_PATH'/.zsh-custom/' $HOME'/.zsh-custom/'  &&
        find $HOME/.secrets -type f -exec chmod 600 {} + &&
        find $HOME/.secrets -iname "*.sh" -exec chmod 700 {} + &&
        find $HOME/.secrets -iname "shopt" -exec chmod 755 {} + &&
        find $HOME/.secrets -iname "*wrapper" -exec chmod 755 {} + &&
        echo "${DTG} sync.sec completed on ${HOST}" | tee $HOME/$SUCCESS_LOG
}


if [ -e /Volumes/shaun/.secrets ]; then
        SYNC_SEC_PATH=/Volumes/shaun &&
        echo "This is on  ${HOST}, sync.sec PUSHING TO -> $SYNC_SEC_PATH" | tee $HOME/$SUCCESS_LOG &&
        sync_dirs

elif [ -e /mnt/shaun-pve113/.secrets ]; then
        SYNC_SEC_PATH=/mnt/shaun-pve113 &&
        echo "This is on   🦅 ${HOST}, sync.sec PUSHING TO -> $SYNC_SEC_PATH" | tee $HOME/$SUCCESS_LOG &&
        sync_dirs
else
        echo "${DTG} FAILED conditions for sync.sec on ${HOST}" | tee $HOME/$ERROR_LOG
fi
