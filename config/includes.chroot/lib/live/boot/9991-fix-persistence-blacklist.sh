#!/bin/sh

# Fix: live-boot blacklists the entire parent disk when the raw device
# (e.g. /dev/sda) is mounted as the live medium (common with ISO hybrid images).
# This prevents scanning partitions on the same disk for persistence.
#
# This script redefines storage_devices() to remove the parent-device
# blacklist check. Individual partitions are still checked against the
# blacklist, so the raw device /dev/sda is skipped but /dev/sda2
# (persistence) is found.
#
# Sourced after 9990-misc-helpers.sh due to glob ordering.

echo "[9991-fix] storage_devices override loaded" >&2

storage_devices()
{
	black_listed_devices="${1}"
	white_listed_devices="${2}"

	echo "[9991-fix] storage_devices called, blacklist='${black_listed_devices}' whitelist='${white_listed_devices}'" >&2

	for sysblock in $(echo /sys/block/* | tr ' ' '\n' | grep -vE "loop|ram|fd")
	do
		fulldevname=$(sys2dev "${sysblock}")

		echo "[9991-fix] scanning block device: ${fulldevname} (${sysblock})" >&2

		# Only apply whitelist filtering at device level
		# Do NOT skip the entire disk based on blacklist — let
		# individual subdevices be filtered instead
		if [ -n "${white_listed_devices}" ] && \
			! is_in_space_sep_list ${fulldevname} ${white_listed_devices}
		then
			echo "[9991-fix]   SKIPPED by whitelist" >&2
			continue
		fi

		for dev in $(subdevices "${sysblock}")
		do
			devname=$(sys2dev "${dev}")

			if is_in_space_sep_list ${devname} ${black_listed_devices}
			then
				echo "[9991-fix]   subdev ${devname} BLACKLISTED, skipping" >&2
				continue
			else
				echo "[9991-fix]   subdev ${devname} OK, returning" >&2
				echo "${devname}"
			fi
		done
	done
}
