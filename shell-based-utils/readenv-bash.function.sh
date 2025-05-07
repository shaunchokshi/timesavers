#!/bin/bash 
# quick bash function to read .env file
# use it via:
# source readenv
# readenv
#
# or
#
# readenv <filename>
#
# modified from https://gist.github.com/mihow/9c7f559807069a03e302605691f85572
# fixed for whitespace issues, posix compliance (e.g. \t on mac means t)
#
# this is NOT a standalone script normally
# it can be used as a standalone script for some use cases
# when used standalone, it'll read in the ENV variables into a sub-process, not the calling process

readenv() {
  local filePath="${1:-.env}"

  if [ ! -f "$filePath" ]; then
    # as written with new line after then, it goes to "return 0" and silently finishes
    # if you want to see erros instead put some error / echo
    return 0
  fi

#  echo "Reading $filePath"
  while read -r line; do
    if [[ "$line" =~ ^\s*#.*$ || -z "$line" ]]; then
      continue
    fi

     # Split the line into key and value. Trim whitespace on either side.
    key=$(echo "$line" | cut -d '=' -f 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    value=$(echo "$line" | cut -d '=' -f 2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Leaving the below here... normally this works, but if you have something like
    # FOO="  string with leading and trailing  "
    # then the leading / trailing spaces are deleted. FOO="a word", FOO='a word', and FOO=a word all generally work
    # so leave the quotes
    # Remove single quotes, double quotes, and leading/trailing spaces from the value
    # value=$(echo "$value" | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Export the key and value as environment variables
    # echo "$key=$value"
    export "$key=$value"

  done < "$filePath"
}
