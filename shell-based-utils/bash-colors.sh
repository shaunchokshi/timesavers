#!/bin/sh
printf "\e[0;30mBlack \e[1;30mbold Black \e[0;90mhigh intensity Black\n"
printf "\e[0;31mRed \e[1;31mbold Red \e[0;91mhigh intensity Red\n"
printf "\e[0;32mGreen \e[1;32mbold Green \e[0;92mhigh intensity Green\n"
printf "\e[0;33mYellow \e[1;33mbold Yellow \e[0;93mhigh intensity Yellow\n"
printf "\e[0;34mBlue \e[1;34mbold Blue \e[0;94mhigh intensity Blue\n"
printf "\e[0;35mPurple \e[1;35mbold Purple \e[0;95mhigh intensity Purple\n"
printf "\e[0;36mCyan \e[1;36mbold Cyan \e[0;96mhigh intensity Cyan\n"
printf "\e[0;37mWhite \e[1;37mbold White \e[0;97mhigh intensity White\n"
echo " \n"


echo -e "\e[1mbold\e[0m"
echo -e "\e[3mitalic\e[0m"
echo -e "\e[3m\e[1mbold italic\e[0m"
echo -e "\e[4munderline\e[0m"
echo -e "\e[9mstrikethrough\e[0m"
echo -e "\e[31mHello World\e[0m"
echo -e "\x1B[31mHello World\e[0m"
echo " \n"

printf "\e[0;30mBlack\n"
printf "\e[0;31mRed\n"
printf "\e[0;32mGreen\n"
printf "\e[0;33mYellow\n"
printf "\e[0;34mBlue\n"
printf "\e[0;35mPurple\n"
printf "\e[0;36mCyan\n"
printf "\e[0;37mWhite\n"
echo " \n"

printf "\e[1;30mbold Black\n"
printf "\e[1;31mbold Red\n"
printf "\e[1;32mbold Green\n"
printf "\e[1;33mbold Yellow\n"
printf "\e[1;34mbold Blue\n"
printf "\e[1;35mbold Purple\n"
printf "\e[1;36mbold Cyan\n"
printf "\e[1;37mbold White\n"
echo " \n"

printf "\e[0;90mhigh intensity Black\n"
printf "\e[0;91mhigh intensity Red\n"
printf "\e[0;92mhigh intensity Green\n"
printf "\e[0;93mhigh intensity Yellow\n"
printf "\e[0;94mhigh intensity Blue\n"
printf "\e[0;95mhigh intensity Purple\n"
printf "\e[0;96mhigh intensity Cyan\n"
printf "\e[0;97mhigh intensity White\n"

echo " \n"

  bold='\x1b[1m'
  italic='\x1b[3m'
  bolditalic='\x1b[3m\x1b[1m'
  underline='\x1b[4m'
  dblUnderline='\x1b[21m'
  dim='\x1b[2m'
  invert='\x1b[7m'
  black='\x1b[30m'
  blackbg='\x1b[40m'
  red='\x1b[31m'
  redbg='\x1b[41m'
  orange='\x1b[38;5;208m'
  green='\x1b[32m'
  greenbg='\x1b[42m'
  yellow='\x1b[33m'
  yellowbg='\x1b[43m'
  blue='\x1b[34m'
  bluebg='\x1b[44m'
  purple='\x1b[35m'
  purplebg='\x1b[45m'
  magenta='\x1b[35m'
  cyan='\x1b[36m'
  cyanbg='\x1b[46m'
  white='\x1b[37m'
  whitebg='\x1b[47m'
  primaryFont='\x1b[10m'
  strike='\x1b[9m'
  reset='\x1b[0m'

echo " \n"

echo bold='\x1b[1m'
echo italic='\x1b[3m'
echo bolditalic='\x1b[3m\x1b[1m'
echo underline='\x1b[4m'
echo dblUnderline='\x1b[21m'
echo dim='\x1b[2m'
echo invert='\x1b[7m'
echo black='\x1b[30m'
echo blackbg='\x1b[40m'
echo red='\x1b[31m'
echo redbg='\x1b[41m'
echo orange='\x1b[38;5;208m'
echo green='\x1b[32m'
echo greenbg='\x1b[42m'
echo yellow='\x1b[33m'
echo yellowbg='\x1b[43m'
echo blue='\x1b[34m'
echo bluebg='\x1b[44m'
echo purple='\x1b[35m'
echo purplebg='\x1b[45m'
echo magenta='\x1b[35m'
echo cyan='\x1b[36m'
echo cyanbg='\x1b[46m'
echo white='\x1b[37m'
echo whitebg='\x1b[47m'
echo primaryFont='\x1b[10m'
echo strike='\x1b[9m'
echo reset='\x1b[0m'
echo " \n"
echo '\x1b[0m' && printf '\x1b[0m reset \n' 
echo '\x1b[1m' && printf '\x1b[1m bold \n' 
echo '\x1b[3m' && printf '\x1b[3m italic \n' 
echo '\x1b[3m\x1b[1m' && printf '\x1b[3m\x1b[1m bolditalic \n' 
echo '\x1b[4m' && printf '\x1b[4m underline \n' 
echo '\x1b[21m' && printf '\x1b[21m dblUnderline \n' 
echo '\x1b[2m' && printf '\x1b[2m dim \n' 
echo '\x1b[7m' && printf '\x1b[7m invert \n' 
echo '\x1b[30m' && printf '\x1b[30m black \n' 
echo '\x1b[40m' && printf '\x1b[40m blackbg \n' 
echo '\x1b[31m' && printf '\x1b[31m red \n' 
echo '\x1b[41m' && printf '\x1b[41m redbg \n' 
echo '\x1b[38;5;208m' && printf '\x1b[38;5;208m orange \n' 
echo '\x1b[32m' && printf '\x1b[32m green \n' 
echo '\x1b[42m' && printf '\x1b[42m greenbg \n' 
echo '\x1b[33m' && printf '\x1b[33m yellow \n' 
echo '\x1b[43m' && printf '\x1b[43m yellowbg \n' 
echo '\x1b[34m' && printf '\x1b[34m blue \n' 
echo '\x1b[44m' && printf '\x1b[44m bluebg \n' 
echo '\x1b[35m' && printf '\x1b[35m purple \n' 
echo '\x1b[45m' && printf '\x1b[45m purplebg \n' 
echo '\x1b[35m' && printf '\x1b[35m magenta \n' 
echo '\x1b[36m' && printf '\x1b[36m cyan \n' 
echo '\x1b[46m' && printf '\x1b[46m cyanbg \n' 
echo '\x1b[37m' && printf '\x1b[37m white \n' 
echo '\x1b[47m' && printf '\x1b[47m whitebg \n' 
echo '\x1b[10m' && printf '\x1b[10m primaryFont \n' 
echo '\x1b[9m' && printf '\x1b[9m strike \n' 


for x in {0..5}; do echo --- && for z in 0 10 60 70; do for y in {30..37}; do y=$((y + z)) && printf '\e[%d;%dm%-12s\e[0m' "$x" "$y" "$(printf ' \\e[%d;%dm] ' "$x" "$y")" && printf ' '; done && printf '\n'; done; done
