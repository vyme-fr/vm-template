#!/bin/bash

NONE="\033[m"
WHITE="\033[1;37m"
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[34m"
CYAN="\033[36m"
LIGHT_GREEN="\033[1;32m"
LIGHT_RED="\033[1;31m"

curl --max-time 1 https://cdn.vyme.net/00-motd.txt 2>/dev/null

if grep -qi "alpine" /etc/os-release; then
    . /etc/os-release
    DISTRIB_DESCRIPTION="$PRETTY_NAME"

    re='(.*\()(.*)(\).*)'
    if [[ $DISTRIB_DESCRIPTION =~ $re ]]; then
        DISTRIB_DESCRIPTION=$(printf "%s%s%s%s%s" "${BASH_REMATCH[1]}" "${YELLOW}" "${BASH_REMATCH[2]}" "${NONE}" "${BASH_REMATCH[3]}")
    fi

    printf "$WHITE$DISTRIB_DESCRIPTION (kernel $(uname -r))$NONE\n"

    memfree=$(grep MemFree /proc/meminfo | awk '{print $2}')
    memtotal=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    memfree_mb=$(echo "scale=2; $memfree/1024" | bc)
    memtotal_mb=$(echo "scale=2; $memtotal/1024" | bc)

    uptime_formatted=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')

    addrip=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)

    read one five fifteen rest < /proc/loadavg

    printf " Load avg : $one (1min) / $five (5min) / $fifteen (15min)\n"
    printf " IP : $addrip\n"
    printf " RAM : $memfree_mb MB free / $memtotal_mb MB\n"
    printf " Uptime : $uptime_formatted\n"
    printf "\n"

else
    if [ -r /etc/motd.d/lsb-release ]; then
        . /etc/motd.d/lsb-release
    elif [ -x /usr/bin/lsb_release ]; then
        DISTRIB_DESCRIPTION=$(lsb_release -s -d)
    else
        DISTRIB_DESCRIPTION="Distribution inconnue"
    fi

    re='(.*\()(.*)(\).*)'
    if [[ $DISTRIB_DESCRIPTION =~ $re ]]; then
        DISTRIB_DESCRIPTION=$(printf "%s%s%s%s%s" "${BASH_REMATCH[1]}" "${YELLOW}" "${BASH_REMATCH[2]}" "${NONE}" "${BASH_REMATCH[3]}")
    fi

    printf "$WHITE$DISTRIB_DESCRIPTION (kernel $(uname -r))$NONE\n"

    memfree=$(grep MemFree /proc/meminfo | awk '{print $2}')
    memtotal=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    memfree_mb=$(echo "scale=2; $memfree/1024" | bc)
    memtotal_mb=$(echo "scale=2; $memtotal/1024" | bc)
    uptime=$(uptime -p)
    addrip=$(hostname -I | cut -d " " -f1)

    read one five fifteen rest < /proc/loadavg

    printf " Load avg : $one (1min) / $five (5min) / $fifteen (15min)\n"
    printf " IP : $addrip\n"
    printf " RAM : $memfree_mb MB free / $memtotal_mb MB\n"
    printf " Uptime : $uptime\n"
    printf "\n"
fi
