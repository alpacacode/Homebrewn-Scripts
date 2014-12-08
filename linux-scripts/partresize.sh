#!/bin/bash
##########
# Script to resize a LVM Partition after extending the underlying disk device. Can be used on physical or virtual machines alike.
# Tested with CentOS6, RHEL6, CentOS7, RHEL7. This script is only intended for MBR partitioned disks and not for GPT.
#
# The script will first resize the partition by changing the partition end sector of the selected partition, and then after a reboot resize the filesystem.
# By default it rescans the SCSI bus to check a change in disk size if the disk was hot-extended, which is easy with VMs, and only then proceeds.
# If the extended disk size is recognized by the OS already, you can force resizing with the -f flag.
#
# It is recommended you backup the boot sector of your disk before as a safety measure with something like the following:
# # dd if=/dev/sda of=sda_mbr_backup.mbr bs=512 count=1 
# # sfdisk -d /dev/sda > sda_mbr_backup.bak
#
# Github: https://github.com/alpacacode/Homebrewn-Scripts
########

usage() {
  echo "Usage:
$0 [-p <LVM physical volume>] [-l <LVM logical volume>] [-f]
 
Options:
 -p physical LVM volume device to extend (check pvdisplay)
 -l logical LVM volume to extend (check lvdisplay)
 -f force extending without a disk rescan. Use this if the OS has detected the enlarged disk already, otherwise we first check whether the underlying disk is larger after a SCSI rescan
    
Example:
./lvmresize.sh -p /dev/sda2 -l /dev/VolGroup/lv_root -f" 1>&2
  exit 1
} 

extenddisk_parted() {
  # Use parted because fdisk behavior can vary between OSes and scripting fdisk is non-deterministic.
  echo -e "\nThis will now extend partition number $partitionnum on disk $disk using start sector $startsector.\n"
  read -r -p "Are you sure? [y/N] " response
  response=${response,,} # tolower 
  if [[ $response =~ ^(yes|y)$ ]]
  then
    parted $disk --script unit s print
    parted $disk --script rm $partitionnum
    # The filesystem used here is irrelevant because we will set the partition to LVM next.
    parted $disk --script "mkpart primary ext2 ${startsector}s -1s"
    parted $disk --script set $partitionnum lvm on
    parted $disk --script unit s print

    # The 2nd script to expand the filesystem will be automatically executed on the next reboot.
    echo "#!/bin/bash
#Extend Physical Volume first
pvresize $p

#Extend LVM, using 100% of the free allocation units and resize filesystem
lvextend --extents +100%FREE $l --resizefs
chmod -x \$0" > /root/fsresize.sh
    chmod +x /root/fsresize.sh
    # Use a temporary systemd service or a rc.local script for extending the filesystem during next reboot, depending on what the OS is running.
    if(pidof systemd)
    then
      resizefs_systemd
    else
      resizefs_rclocal
    fi
    
    echo -e "Done. The system will reboot automatically in 15 seconds and resize the filesystem during reboot.\n"
    sleep 15
    # Reboot is necessary in most cases for the kernel to read the new partition table.
    reboot
  else
    echo -e "Aborted by user.\n"
    exit 1
  fi
}

resizefs_rclocal() {
  # Resize the filesystem using a script in rc.local if the OS run with sysvinit.
  echo "#Cleanup rc.local again
sed -i -e \"/\/root\/fsresize\.sh/d\" /etc/rc.d/rc.local" >> /root/fsresize.sh
  
  echo "/root/fsresize.sh" >> /etc/rc.d/rc.local
}

resizefs_systemd() {
  # Resize the filesystem using a script called by a temporary systemd service file if the OS runs with systemd.
  echo "#Cleanup systemd autostart script again.
systemctl disable fsresize.service
rm -f /etc/systemd/system/fsresize.service" >> /root/fsresize.sh
  
  echo "[Unit]
Description=Filesystem resize script for LVM volume $l

[Service]
ExecStart=/root/fsresize.sh

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/fsresize.service
  systemctl enable fsresize.service
}

# Get options passed to the script.
while getopts ":p:l:f" o; do
  case "${o}" in
    p)
      p=${OPTARG}
      ;;
    l)
      l=${OPTARG}
      ;;
    f)
      f=1
      ;;
    *)
      usage
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${p}" ] || [ -z "${l}" ]
then
  usage
fi

# Check if a valid LVM physical volume was supplied by verifying the pvdisplay exit code ($?).
pvdisplay $p > /dev/null
if [ $? != 0 ] || ( ! (file $p | grep -q "block special"))
then
  echo -e "Error: $p does not look like a block device or LVM physical volume.\n"
  usage
fi

# Check if a valid LVM logical volume was supplied by verifying the lvdisplay exit code ($?).
lvdisplay $l > /dev/null
if [ $? != 0 ]
then
  echo -e "Error: $l does not look like a LVM logical volume.\n"
  usage
fi

# Fill variables for later use.
disk=$(echo $p | rev | cut -c 2- | rev)
diskshort=$(echo $disk | grep -Po '[^\/]+$')
partitionnum=$(echo $p | grep -Po '\d$')
startsector=$(fdisk -u -l $disk | grep $p | awk '{print $2}')
if ! (fdisk -u -l $disk | grep $disk | tail -1 | grep $p | grep -q "Linux LVM")
then
  echo -e "Error: $p is not the last LVM volume on disk $disk. Cannot expand.\n"
  usage
fi

if [ "$f" != 1 ]
then
  oldsize=$(cat /sys/block/${diskshort}/size)
  # Rescan the SCSI bus to detect the grown disk.
  ls /sys/class/scsi_device/*/device/rescan | while read path; do echo 1 > $path; done
  ls /sys/class/scsi_host/host*/scan | while read path; do echo "- - -" > $path; done
  newsize=$(cat /sys/block/${diskshort}/size)

  # Check if the disk is larger now and proceed with the partition expansion if it is. 
  if [ $oldsize -lt $newsize ]
  then
    echo -e "Underlying disk $disk is larger now.\n"
    extenddisk_parted
  else
    echo -e "Disk Size not changed after rescan, already rescanned previously? Force extension with -f. Quitting.\n"
  fi
# When -f (force) flag is set, proceed to extend the disk without checking if it has grown.
else
    extenddisk_parted
fi
