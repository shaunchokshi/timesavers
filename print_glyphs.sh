#!/bin/bash -

#printhelp() { echo "$0 FontFile"; exit 1; }
printerror() { local error=$fontfile; }


read -p "Enter path/to/fontfile: " -i "$HOME/" -e fontfile
if [ -f "$fontfile" ] ; then

fontfile=${fontfile}

#set default
width=70
#get user input
read -e -i "$width" -p "Enter width (how many columns to display): " width
width=${width}



list=$(fc-query --format='%{charset}\n' "$fontfile")

for range in $list
do IFS=- read start end <<<"$range"
    if [ "$end" ]
    then
        start=$((16#$start))
        end=$((16#$end))
        for((i=start;i<=end;i++)); do
            printf -v char '\\U%x' "$i"
            printf '%b' "$char"
        done
    else
        printf '%b' "\\U$start"
    fi
done | grep -oP '.{'"$width"'}'

else
echo 'File [' $fontfile '] not found'
exit 1
fi
