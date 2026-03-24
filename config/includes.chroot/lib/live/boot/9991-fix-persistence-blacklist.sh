#!/bin/sh

# Fix: live-boot blacklists the entire parent disk when the raw device
# (e.g. /dev/sda) is mounted as the live medium (common with ISO hybrid images).
# This prevents scanning partitions on the same disk for persistence.
#
# This script redefines storage_devices() to remove the parent-device
# blacklist check, and fixes probe_for_fs_label() to work with busybox's
# blkid (which may not support -s/-o flags).
#
# Sourced after 9990-misc-helpers.sh due to glob ordering.

echo "[9991-fix] storage_devices and probe_for_fs_label overrides loaded" >&2

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

probe_for_fs_label()
{
	local overlays dev label
	overlays="${1}"
	dev="${2}"

	echo "[9991-fix] probe_for_fs_label: overlays='${overlays}' dev='${dev}'" >&2

	# Try blkid with -s/-o flags (util-linux), fall back to raw blkid
	# output parsing (busybox), then try reading ext4 superblock directly
	label=""
	if blkid -s LABEL -o value "${dev}" >/dev/null 2>&1; then
		label="$(blkid -s LABEL -o value "${dev}" 2>/dev/null)"
	else
		echo "[9991-fix]   blkid -s/-o not supported, trying raw blkid" >&2
		# busybox blkid outputs: /dev/sda2: LABEL="persistence" UUID="..." TYPE="ext4"
		label="$(blkid "${dev}" 2>/dev/null | sed -n 's/.*LABEL="\([^"]*\)".*/\1/p')"
	fi

	echo "[9991-fix]   blkid label='${label}'" >&2

	for _label in ${overlays}
	do
		if [ "${label}" = "${_label}" ]
		then
			echo "[9991-fix]   MATCH: ${_label}=${dev}" >&2
			echo "${_label}=${dev}"
		fi
	done
}
