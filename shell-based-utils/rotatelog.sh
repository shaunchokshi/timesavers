logdir=/home/shaun/scripts/logs
filename=connectivity-checks.log
logfile="${logdir}/${filename}"
minimumsize=10000
actualsize=$(wc -c <"$logfile")
if [ $actualsize -ge $minimumsize ]; then
	mv $logfile $logdir/connectivity-checks-$(date -u "+%F_%T_%Z").log
else
	sleep 1
fi
