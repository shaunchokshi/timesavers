#!/bin/bash


cntx="orgs"
read -e -p "Context of repo ownership [orgs] or [users]:" cntx

if [ -z "$1" ]; then
    name="Nicolai-Electronics"
    read -e -i $name -p "Name (of user or org):" name
else
    name=$1
fi

if [ -z "$2" ]; then
    max=2
    read -e -p "Maximum number of repos list pages to traverse (at 100 repos per page):" max
else
    max=$2
fi
page=1


echo $name
echo $max
echo $cntx
echo $page

until (( $page -lt $max ))
do
    curl "https://api.github.com/$cntx/$name/repos?page=$page&per_page=100" | grep -e 'clone_url*' | cut -d \" -f 4 | xargs -L1 git clone
    $page=$page+1
done

exit 0
