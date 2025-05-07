#!/bin/bash

# This script checks the size of a log file and rotates it if it exceeds a certain size.
# It moves the log file to a new name with a timestamp and keeps the original file for further logging.
# Usage: you can use this code snippet in your scripts to manage log files.

# Check if the log directory exists, if not create it
logdir=/home/shaun/scripts/logs
filename=connectivity-checks.log
logfile="${logdir}/${filename}"
minimumsize=10000
actualsize=$(wc -c <"$logfile")
if [ $actualsize -ge $minimumsize ]; then
	mv $logfile $logdir/connectivity-checks-"$(date -u "+%F_%T_%Z")".log
else
	sleep 1
fi
