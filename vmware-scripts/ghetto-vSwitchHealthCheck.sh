#!/bin/sh
##########
# Local ESXi shell script for checking the hosts's connectivity on a number of VLANs.
# This is basically intended as a poor man's version of the Health Check available with distributed vSwitches.
# 
# This script uses a CSV-style list to configure a temporary vmkernel interface with certain VLAN and IP settings, pinging a specified IP on that network with the given payload size to account for MTU configuration. 
# That should at least take care of initial network-side configuration errors when building a new infrastructure or adding new hosts.
# This script was tested successfully on ESXi 5.5 and should work on ESXi 5.1 as well. I’m not entirely sure about 5.0 but that should be ok too.
#
# The csv-file should look like this:
# ~ # cat /tmp/nets.csv
#    #vlan,vmkip,vmknetmask,target
#    20,10.1.20.99,255.255.255.0,10.1.20.1
#    30,10.1.30.99,255.255.255.0,10.1.30.1
#    40,10.1.40.88,255.255.255.0,10.1.40.1
#
# Github: https://github.com/alpacacode/Homebrewn-Scripts
# Reference: http://alpacapowered.wordpress.com/2014/05/26/script-poor-mans-vsphere-network-health-check-for-standard-vswitches/
########

########
# Make sure you first define your variables here.
vswitch=vSwitch2 # The vSwitch you want to test your VLANs on.
uplink=vmnic3 # The physical uplink you want to check. Make sure it's one of the uplinks configured for the vSwitch. You probably want to run the script multiple times on all uplinks of your vSwitch.
tempvmk=vmk9 # The name of the temporary vmkernel interface created for sending your test pings.
portgroup=testpg # The name of the temporary Port Group created to use for the tempvmk interface.
pingsize=56 # The payload size to use for the vmkpings. Increase it if you want to check jumbo-frame connectivity on the VLANs. Note that the ping payload size does not include the ICMP (8 Byte) and IP (20 Byte) headers, so to check for a layer 2 ethernet MTU of 9000 you must use a smaller payload size of 8972. To check a normal MTU of 1500 Byte you need to set a size of 1472.
file=/tmp/nets.csv # Path to a CSV-file containing the network related infos. Each line represents a CSV-style set of the following: VLAN, IP to assign to $tempvmk, Netmask for $tempvmk, Target IP you want to ping on this network.
########


# Creates a temporary Port Group and vmkernel interface, also makes sure the Port Group only uses the specified vmnic $uplink as it's active uplink.
esxcli network vswitch standard portgroup add --portgroup-name $portgroup --vswitch-name $vswitch
esxcli network vswitch standard portgroup policy failover set --portgroup-name $portgroup --active-uplinks $uplink --load-balancing explicit
esxcli network ip interface add --portgroup-name $portgroup --interface-name $tempvmk

# Loops through the list of networks.
grep -v '^#' $file | while read network
do
  # Fill in the individual variables from the line.
  i=1
  for var in "vlan" "ip" "netmask" "target"
  do
    export $var=$(echo yes | awk -v network=$network '{print network;}' | grep -Eo '[^,]+' | awk "NR == $i")
    i=$(expr $i + 1)
  done

  echo -e "\n--------\nTrying VLAN: $vlan\tIP: $ip\tNetmask: $netmask\tTarget-IP: $target\n"
  # Assign the VLAN ID to $portgroup.
  esxcli network vswitch standard portgroup set --portgroup-name $portgroup --vlan-id $vlan
  # Assign the IP and Netmask settings to $tempvmk
  esxcli network ip interface ipv4 set -t static --interface-name $tempvmk --ipv4 $ip --netmask $netmask
  
  sleep 3
  # Ping the target IP three times via $tempvmk
  vmkping -4 -d -c 3 -s $pingsize -I $tempvmk $target | 
  if grep -q " 0% packet loss"
  then
    echo "Successfully pinged target IP $target for VLAN $vlan on uplink $uplink."
  else 
    echo "Error! Couldn't ping target IP $target for VLAN $vlan on uplink $uplink."
  fi
done

# Remove temporarily created Port Group and vmkernel interface.
esxcli network ip interface remove --interface-name $tempvmk
esxcli network vswitch standard portgroup remove --portgroup-name $portgroup --vswitch-name $vswitch