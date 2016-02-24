#!/bin/sh
##########
# Script to verify that packets to a destination are being routed on a path with a specific hop via traceroute.
# Example usage scenarios for this script include detecting failover of HSRP/VRRP clusters, changes in the routing topology through dynamic routing protocols along the way, and other use cases.
#
# If the expected hop does not appear on the path, a mail notification can be sent.
#
# Github: https://github.com/alpacacode/Homebrewn-Scripts
########

function usage() {
  echo "Usage:
$0 -d <Destination IP> -h <Hop IP> [-m <mail adress to notify>]

Options:
 -d Destination IP for the traceroute
 -h IP of the network hop that should appear during the traceroute
 -m Mail address that should be notified in case the specified hop does not appear during the traceroute
 If no mail address is specified, output will be printed to the terminal.
 The traceroute uses ICMP mode and as such needs to be run as root in most environments.
 This script handles IPv4 addresses only.

Example:
./traceroute_check.sh -d 8.8.8.8 -h 10.1.2.3 -m admin@example.org
" 1>&2
  exit 1
}

# Handle Options
while getopts ":d:h:m:" o; do
  case "${o}" in
    d)
      Destination=${OPTARG}
      ;;
    h)
      Hop=${OPTARG}
      ;;
    m)
      Mail=${OPTARG}
      ;;
    *)
      usage
      ;;
  esac
done
shift $((OPTIND-1))

# Verify valid IPv4 addresses were specified
function valid_ip()
{
  local  ip=$1
  local  stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
  then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    stat=$?
  fi
  return $stat
}

function send_mail()
{
  echo -e "$2" | mail -s "$1" -r traceroute@$HOSTNAME $Mail
}

# Verify IPs
if ! (valid_ip $Hop) || ! (valid_ip $Destination)
then
  echo -e "Error: Specified destination or hop do not look like a valid IPv4 address.\n"
  usage
fi

Date=$(date)
# ICMP Traceroute Timeout=3s, Probe-Delay=200ms
Traceroute=$(traceroute -In -w 5 -z 200 $Destination 2>&1)
# If the traceroute command encounters an error
if [ $? != 0 ]
then
  if [ ! -z "$Mail" -a "$Mail" != " " ]
  then
    send_mail "Traceroute Error" "Error while executing the traceroute command:\n$Date\nExit-Code:$?\n\n$Traceroute"
  else
    echo -e "Error while executing the traceroute command:\n$Date\nExit-Code:$?\n\n$Traceroute"
  fi
  exit 1
fi

# If the specified hop does not appear in the traceroute
if ! grep -Pq "\s$Hop\s" <<< $Traceroute
then
  if [ ! -z "$Mail" -a "$Mail" != " " ]
  then
    send_mail "Traceroute route changed" "Traffic to Destination $Destination is currently not being routed through the specified hop $Hop.\nThe routing path might have changed:\n$Date\n\n$Traceroute"
  else
    echo -e "Traffic to Destination $Destination is currently not being routed through the specified hop $Hop.\nThe routing path might have changed:\n$Date\n\n$Traceroute"
  fi
fi
