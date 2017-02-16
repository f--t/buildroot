#!/bin/sh

source /etc/device_config

file=/sys/kernel/config/usb_gadget/composite_gadget/functions/mass_storage.0/lun.0/file
bootimage=/mnt/boot.frm
conf=/mnt/config.txt
img=/opt/vfat.img

ini_parser() {
 FILE=$1
 SECTION=$2
 eval `sed -e 's/[[:space:]]*\=[[:space:]]*/=/g' \
    -e 's/[#;\`].*$//' \
    -e 's/[[:space:]]*$//' \
    -e 's/^[[:space:]]*//' \
    -e "s/^\(.*\)=\([^\"']*\)$/\1=\"\2\"/" \
   < $FILE \
    | sed -n -e "/^\[$SECTION\]/,/^\s*\[/{/^[^;].*\=.*/p;}"`
}

reset() {
	echo "REBOOT/RESET using Watchdog timeout"
	flash_indication_off
	sync
	device_reboot reset
	sleep 10
}

dfu() {
	echo "Entering DFU mode using SW Reset"
	flash_indication_off
	sync
	device_reboot sf
}

flash_indication_on() {
	echo timer > /sys/class/leds/led0:green/trigger
	echo 40 > /sys/class/leds/led0:green/delay_off
	echo 40 > /sys/class/leds/led0:green/delay_on
}

flash_indication_off() {
	echo heartbeat > /sys/class/leds/led0:green/trigger
}

make_diagnostic_report () {
	FILE=$1
	cat  /opt/VERSIONS /etc/os-release /var/log/messages /proc/cpuinfo /proc/interrupts /proc/iomem /proc/meminfo /proc/cmdline /sys/kernel/debug/clk/clk_summary > ${FILE}
	grep -r "" /sys/kernel/debug/regmap/ >> ${FILE} 2>&1
	iio_info >> ${FILE} 2>&1
	ifconfig -a >> ${FILE} 2>&1
	mount >> ${FILE} 2>&1
	top -b -n1  >> ${FILE} 2>&1
	unix2dos ${FILE}
}

process_ini() {
	FILE=$1
	md5sum $FILE > /opt/config.md5
	ini_parser $FILE "NETWORK"

	rm -f /mnt/SUCCESS_ENV_UPDATE /mnt/FAILED_INVALID_UBOOT_ENV

	if [ -n "$ipaddr" ] && [ -n "$ipaddr_host" ] && [ -n "$netmask" ]
	then

		IPADDR=`fw_printenv -n ipaddr`
		IPADDR_HOST=`fw_printenv -n ipaddr_host`
		NETMASK=`fw_printenv -n netmask`

		if [ "$IPADDR" != $ipaddr ] || [ "$IPADDR_HOST" != $ipaddr_host ] || [ "$NETMASK" != $netmask ]
		then
			fw_printenv qspiboot
			if [ $? -eq 0 ]; then
				flash_indication_on
				echo "ipaddr $ipaddr" > /opt/fw_set.tmp
				echo "ipaddr_host  $ipaddr_host" >> /opt/fw_set.tmp
				echo "netmask  $netmask" >> /opt/fw_set.tmp
				fw_setenv -s /opt/fw_set.tmp
				rm /opt/fw_set.tmp
				flash_indication_off
				touch /mnt/SUCCESS_ENV_UPDATE
			else
				touch /mnt/FAILED_INVALID_UBOOT_ENV
			fi
		fi
	fi

	ini_parser $FILE "WLAN"

	if [ -n "$ipaddr_wlan" ] && [ -n "$ssid_wlan" ] && [ -n "$pwd_wlan" ]
	then

		WLAN_SSID=`fw_printenv -n ssid_wlan 2> /dev/null`
		WLAN_PWD=`fw_printenv -n pwd_wlan 2> /dev/null`
		WLAN_IPADDR=`fw_printenv -n ipaddr_wlan 2> /dev/null`

		if [ "$WLAN_SSID" != $ssid_wlan ] || [ "$WLAN_PWD" != $pwd_wlan ] || [ "$WLAN_IPADDR" != $ipaddr_wlan ]
		then
			fw_printenv qspiboot
			if [ $? -eq 0 ]; then
				flash_indication_on
				echo "ssid_wlan $ssid_wlan" > /opt/fw_set.tmp
				echo "ipaddr_wlan  $ipaddr_wlan" >> /opt/fw_set.tmp
				echo "pwd_wlan  $pwd_wlan" >> /opt/fw_set.tmp
				fw_setenv -s /opt/fw_set.tmp
				rm /opt/fw_set.tmp
				flash_indication_off
				touch /mnt/SUCCESS_ENV_UPDATE
			else
				touch /mnt/FAILED_INVALID_UBOOT_ENV
			fi
		fi
	fi


	ini_parser $FILE "ACTIONS"

	if [ "$reset" == "1" ]
	then
		reset
	fi

	if [ "$dfu" == "1" ]
	then
		dfu
	fi

	if [ "$diagnostic_report" == "1" ]
	then
		make_diagnostic_report /mnt/diagnostic_report
	fi

}

handle_boot_frm () {
	FILE=$1
	rm -f /mnt/BOOT_SUCCESS /mnt/BOOT_FAILED /mnt/FAILED_MTD_PARTITION_ERROR /mnt/FAILED_BOOT_CHSUM_ERROR
	cat /proc/mtd > /opt/mtd
	dd if=/dev/null of=/opt/mtd bs=1 count=0 seek=1024

	md5=`tail -c 33 ${FILE}`
	head -c -33 ${FILE} > /opt/boot_and_env_and_mtdinfo.bin

	tail -c 1024 /opt/boot_and_env_and_mtdinfo.bin > /opt/mtd-info.txt
	head -c -1024 /opt/boot_and_env_and_mtdinfo.bin > /opt/boot_and_env.bin

	tail -c 131072 /opt/boot_and_env.bin > /opt/u-boot-env.bin
	head -c -131072 /opt/boot_and_env.bin > /opt/boot.bin

	frm=`md5sum /opt/boot_and_env_and_mtdinfo.bin | cut -d ' ' -f 1`

	if [ "$frm" = "$md5" ]
	then
		diff -w /opt/mtd /opt/mtd-info.txt
		if [ $? -eq 0 ]; then
			flash_indication_on
			dd if=/opt/boot.bin of=/dev/mtdblock0 bs=64k && dd if=/opt/u-boot-env.bin of=/dev/mtdblock1 bs=64k && do_reset=1 && touch /mnt/BOOT_SUCCESS || touch /mnt/BOOT_FAILED
			flash_indication_off
		else
			cat /opt/mtd /opt/mtd-info.txt > /mnt/FAILED_MTD_PARTITION_ERROR
			do_reset=0
		fi
	else
		echo $md5 $frm >  /mnt/FAILED_BOOT_CHSUM_ERROR
		do_reset=0
	fi

	rm -f ${FILE} /opt/boot_and_env_and_mtdinfo.bin /opt/mtd-info.txt /opt/boot_and_env.bin /opt/u-boot-env.bin /opt/boot.bin /opt/mtd
}



handle_frimware_frm () {
	FILE=$1
	MAGIC=$2
	rm -f /mnt/SUCCESS /mnt/FAILED /mnt/FAILED_FIRMWARE_CHSUM_ERROR
	md5=`tail -c 33 ${FILE}`
	head -c -33 ${FILE} > /opt/firmware.frm
	FRM_SIZE=`cat /opt/firmware.frm | wc -c | xargs printf "%X\n"`
	frm=`md5sum /opt/firmware.frm | cut -d ' ' -f 1`
	if [ "$frm" = "$md5" ]
	then
		flash_indication_on
		grep -q ${MAGIC}  /opt/firmware.frm && dd if=/opt/firmware.frm of=/dev/mtdblock3 bs=64k && fw_setenv fit_size ${FRM_SIZE} && do_reset=1 && touch /mnt/SUCCESS || touch /mnt/FAILED
		flash_indication_off
	else
		echo $frm $md5 > /mnt/FAILED_FIRMWARE_CHSUM_ERROR
		do_reset=0
	fi

	rm -f ${FILE} /opt/firmware.frm
	sync
}

while [ 1 ]
do
 if [[ -r ${file} ]]
  then
    lun=`cat $file`
    if [ ${#lun} -eq 0 ]
    then
	losetup /dev/loop7 $img -o 512
	mount /dev/loop7 /mnt
	if [[ -s ${FIRMWARE} ]]
	then 
		handle_frimware_frm ${FIRMWARE} ${FRM_MAGIC}
	fi

	if [[ -s ${bootimage} ]]
	then
		handle_boot_frm ${bootimage}
	fi

	md5sum /opt/config.md5 && process_ini $conf

	if [[ $do_reset = 1 ]]
	then
		reset
	fi

	umount /mnt
	#losetup -d /dev/loop7
	echo $img > $file
	flash_indication_off
	sleep 1
    fi
fi

sleep 1

done

exit 1
