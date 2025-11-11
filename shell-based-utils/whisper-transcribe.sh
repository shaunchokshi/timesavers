#!/bin/bash



REDTEXT="\033[1;31m"
GREENTEXT="\033[1;32m"
NOCOLOR="\033[0m"
RED="31"
GREEN="32"
YELLOW="33"
BOLDGREEN="\e[1;${GREEN}m"
ITALICRED="\e[3;${RED}m"
BOLDRED="\e[1;${RED}m"
ENDCOLOR="\e[0m"
BOLDCYAN="\e[1;36m"
CYAN="\e[0;36m"
YELLOWTEXT="\e[0;33m"
BOLDYELLOW="\e[1;33m"
PURPLETEXT="\e[0;35m"
BOLDPURPLE="\e[1;35m"

# check for python venv and module 'openai-whisper'

package_exist(){
    package='openai-whisper'
    if pip freeze | grep $package=; then
        echo "$package found"
    else
        echo "$package not found"
    fi
}
workdir="$(pwd)"

venvpath="${workdir}/venv"

printf "${BOLDCYAN}This script requires the python module ${BOLDPURPLE}'openai-whisper'\n"
printf "${BOLDCYAN}First: ${BOLDPURPLE}Checking for python venv${ENDCOLOR}\n"
read -e -i "$venvpath" -p "Enter path for Python virtual environment: " venvpath

 if [ -f "$venvpath/bin/activate" ]; then
            source $venvpath/bin/activate
        else
            printf "${BOLDRED}no python virtual environment found at $venvpath ${ENDCOLOR}\n"
            printf "${BOLDYELLOW} checking for module 'openai-whisper' outside of venv ${ENDCOLOR}\n"
fi

package='openai-whisper'
    if ! pip freeze | grep $package=; then
        printf "${BOLDRED} $package NOT FOUND... exiting ${ENDCOLOR}\n"
        exit 1
else
        printf "${BOLDGREEN} $package found, continuing...${ENDCOLOR}\n"
# Set the input and output file extensions

read -e -i "$workdir" -p "Enter path for files' directory: " workdir



# Set the input and output file extensions
read -e -p "File extension (format) of files to transcribe: " input_ext

# set -evx  # stop on error, verbose, and print expanded commands
# set -ex # stop on error and print expanded commands
set -e #stop on error


printf "${BOLDPURPLE}This script assumes that the input file, audio only or"
printf " video with audio, contains audio in English${ENDCOLOR}\n"
printf "${YELLOWTEXT}If the input file contains audio in a"
printf "${YELLOWTEXT}different language, check 'whisper --help'"
printf "${YELLOWTEXT}and adjust the script or run the command manually, e.g.:${ENDCOLOR}\n"
printf "${CYANTEXT}whisper /path/to/file --model medium --language [language code]${ENDCOLOR}\n"
printf "${YELLOWTEXT}or for a faster transcript with lower but acceptable quality, run it as: ${ENDCOLOR}\n"
printf "${CYANTEXT}whisper /path/to/file --model small.[language code] ${ENDCOLOR}\n"
printf " \n"
transcribe_speed=normal
printf "${BOLDYELLOW}Do you want normal transcription speed or faster"
printf " (with slightly lower accuracy)?${ENDCOLOR}\n"
read -e -i "$transcribe_speed" -p "choose normal [default] or faster: " transcribe_speed

if [ $transcribe_speed = "normal" ]; then


cd "$workdir"
IFS=$'\n'

while true; do
read  -p "Work recursively or only in path directory? (Y/yes/N/no) " yn

    transcribe() {
        local input_file="$1"
        if [ -f "$input_file" ]; then
            local filename=$(basename -a "$input_file")
            whisper  "$filename" --model medium --language en
        else
            echo "File not found: $filename"
        fi
    }

    sequence() {
        for i in "${paths[@]}"; do
        transcribe "$i"
    done
    }

    fast_transcribe() {
        local input_file="$1"
        if [ -f "$input_file" ]; then
            local filename=$(basename -a "$input_file")
            whisper  "$filename" --model medium small.en
        else
            echo "File not found: $filename"
        fi
    }

    fast_sequence() {
        for i in "${paths[@]}"; do
        fast_transcribe "$i"
    done
    }

case $yn in

    yes) declare -a paths=($(find "${workdir}" -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working recursively through $workdir and sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this...${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            sequence;
        break;;
    no) declare -a paths=($(find "${workdir}" -maxdepth 1 -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working only in $workdir and ignoring sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this... ${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            sequence;
        exit;;
    y) declare -a paths=($(find "${workdir}" -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working recursively through $workdir and sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this...${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            sequence;
        break;;
    n) declare -a paths=($(find "${workdir}" -maxdepth 1 -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working only in $workdir and ignoring sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this... ${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            sequence;
        exit;;
    Y) declare -a paths=($(find "${workdir}" -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working recursively through $workdir and sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this...${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            sequence;
        break;;
    N) declare -a paths=($(find "${workdir}" -maxdepth 1 -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working only in $workdir and ignoring sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this... ${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            sequence;
        exit;;
    *) echo invalid response;;
esac

done

else


cd "$workdir"
IFS=$'\n'

while true; do
read  -p "Work recursively or only in path directory? (Y/yes/N/no) " yn

    fast_transcribe() {
        local input_file="$1"
        if [ -f "$input_file" ]; then
            local filename=$(basename -a "$input_file")
            whisper  "$filename" --model medium small.en
        else
            echo "File not found: $filename"
        fi
    }

    fast_sequence() {
        for i in "${paths[@]}"; do
        fast_transcribe "$i"
    done
    }

case $yn in

    yes) declare -a paths=($(find "${workdir}" -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working recursively through $workdir and sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this...${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            fast_sequence;
        break;;
    no) declare -a paths=($(find "${workdir}" -maxdepth 1 -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working only in $workdir and ignoring sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this... ${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            fast_sequence;
        exit;;
    y) declare -a paths=($(find "${workdir}" -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working recursively through $workdir and sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this...${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            fast_sequence;
        break;;
    n) declare -a paths=($(find "${workdir}" -maxdepth 1 -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working only in $workdir and ignoring sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this... ${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            fast_sequence;
        exit;;
    Y) declare -a paths=($(find "${workdir}" -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working recursively through $workdir and sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this...${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            fast_sequence;
        break;;
    N) declare -a paths=($(find "${workdir}" -maxdepth 1 -name "*.${input_ext}"));
            unset IFS;
            printf "${BOLDPURPLE}working only in $workdir and ignoring sub-directories${ENDCOLOR}\n";
            printf "${BOLDYELLOW}If there is no output in the terminal after this... ${ENDCOLOR}";
            printf "${BOLDYELLOW}then no matching files were found ${ENDCOLOR}";
            printf "${BOLDYELLOW}with extension ${BOLDPURPLE}${input_ext}${ENDCOLOR}\n";
            fast_sequence;
        exit;;
    *) echo invalid response;;
esac

done

fi
fi
