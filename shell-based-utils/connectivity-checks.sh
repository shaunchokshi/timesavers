#!/bin/bash
LOGFILE="/home/shaun/scripts/logs/connectivity-checks.log"
TMPFILE="/tmp/connectivity-checks"
DATE1=`date -u "+%F,%T,%Z"`
SELFIP=`curl -s -4 ifconfig.me`
touch $LOGFILE

nmap 45.79.162.106 -PN -p 2522 | grep -E "open|closed|filtered" >> $TMPFILE

if grep $TMPFILE -e "open" > /dev/null; then
	echo "${DATE1} Wg-Linode @ 45.79.162.196 reachable on 2522/tcp" | tee -a $LOGFILE
	rm $TMPFILE
else
	echo "${DATE1} Wg-Linode not reachable on 2522/tcp --- check if ${SELFIP} is allowed in Linode firewall" | tee -a $LOGFILE
	rm $TMPFILE
fi

TIME=`ping -c 1 1.1.1.1 |  awk 'FNR == 2 { print $(NF-1) }' | cut -d'=' -f2`

sleep 15

DATE2=`date -u "+%F,%T,%Z"`
up=`ping -c 1 1.1.1.1 `
if [ -z "${up}" ]; then
    	printf "${DATE2}: 1.1.1.1 not responding to ping \n"  | tee -a $LOGFILE
    else
    	printf "${DATE2}: 1.1.1.1 ping time is ${TIME}ms \n"  | tee -a $LOGFILE
fi

