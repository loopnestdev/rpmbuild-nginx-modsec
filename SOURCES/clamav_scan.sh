#!/bin/bash
#standard output is used as the return code for the operation. 0 is failure and 1 is success

set -e

export LOG_FILE=/var/log/clamav_scan.log
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S")

if [ $# -eq 0 ]; then
   echo "{\"transaction_timestamp\":\"$timestamp\",\"result\":\"scanav skipped, no file\"}" >> $LOG_FILE
   echo "1"
   exit 1;
fi


if ! [ -s "$1" ]; then
    echo "{\"transaction_timestamp\":\"$timestamp\",\"result\":\"scanav skipped, file $1 size is zero\"}" >> $LOG_FILE
    echo "1"
    exit 1;
fi

check_rc=0

nc -zv {% if ansible_eth1 is defined and ansible_eth1.ipv4 is defined %}{{ansible_eth1.ipv4.address}}{% else %}{{ansible_default_ipv4.address}}{% endif %} 8438 >/dev/null 2>&1|| check_rc=1
#IPv4=`ifconfig eth1 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
if [ $check_rc == '0' ]; then
    RC=`/usr/bin/curl -s --noproxy '*' -X POST -o /dev/null -w '%{http_code}' http://{% if ansible_eth1 is defined and ansible_eth1.ipv4 is defined %}{{ansible_eth1.ipv4.address}}{% else %}{{ansible_default_ipv4.address}}{% endif %}:8438/clammit/scan -F file=@$1`
else
    RC="000"
fi

# Check the output of above command
# ERROR CODE:
#    000: Clammit container is DOWN
#    200: File is CLEAN
#    418: File has a virus
#    500: File scan FAILED, check the file


if [ $RC == "418" ]; then
    echo "{\"transaction_timestamp\":\"$timestamp\",\"result\":\"file $1 has virus\"}" >> $LOG_FILE
    echo "0 file $1 has virus"
    exit 0;
elif [ $RC == "200" ]; then
    echo "{\"transaction_timestamp\":\"$timestamp\",\"result\":\"file $1 is clean\"}" >> $LOG_FILE
    echo "1 file $1 is clean"
    exit 1;
elif [ $RC == "500" ]; then
    echo "{\"transaction_timestamp\":\"$timestamp\",\"result\":\"file $1 scan failed. Please check file\"}" >> $LOG_FILE
    echo "0 file $1 scan failed. Please check file"
    exit 0;
elif [ $RC == "000" ]; then
    echo "{\"transaction_timestamp\":\"$timestamp\",\"result\":\"file $1 scan failed. Likely clammit down\"}" >> $LOG_FILE
    echo "0 file $1 scan failed. Likely clammit down"
    exit 0;
else
    echo "0"
    exit 0;
fi

#echo "1"
exit 0;