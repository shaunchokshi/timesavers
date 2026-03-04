#!/bin/bash
# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "##################################################################"
echo -e "##########${YELLOW} To see the ${PURPLE} NTP request and response packets${NC}"
echo -e "##########${GREEN} open another terminal session and run:${NC}"
echo -e "##########${RED} 'chronyc makestep'${NC}"
echo -e "##################################################################"
tcpdump -n -vv -i any udp port 123
