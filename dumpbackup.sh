#!/bin/bash
#-----------------------------------------------------------------------
# dumpbackup.sh   ver 2.0.0  (2020/10/31)
#----------------------------------------------------------------------
# Copyright (C) 2020-  chidipy    http://chidi.jpn.com/  
#                                mailto:webmaster@chidi.jpn.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#-----------------------------------------------------------------------

# ==== SETTING AREA ====================================================

# backuplist default path
bklist_path_default="/path/to/dumpbackup.lst"

# backup image save default dir
bkupdir_defalut="/mnt/sysbkup"

# backup image prefix default name
bkupimg_prefix_default=$(hostname)

# if backup image save dir is nfs filesystem,define path
# if don't mount , empty
mountdir="//192.168.1.1/sysbkup"
mounteddir="/mnt/smb"
mountoption="-t cifs -o user=hogehoge,workgroup=WORKGROUP,password=H0gehoge"


# snapshot lv name
# if don't snapshot , empty
snaplvname="snaplv"
#snaplvname=""

# snapshot lv size"
snaplvsize="1G"

# snaoshot mount path - xfsdump bug workaround
mounteddir_snapshot="/mnt/snapshot"

# days to delete backup image
deldays_default=15

# logpath
execlog="/path/to/dumpbackup.log"

dummyecho=

# =======================================================================
LANG=C
export LANG

# ==== FUNCTION AREA ====================================================
function CheckMount {
	local l_mountdir=$1
	df | grep -E "^${l_mountdir}( +|$)" > /dev/null
	if (( $? > 0 ));then
		return 1
	else
		return 0
	fi
}

function ExecExternalCommand {
	local execpath=$1
	if [[ ! -z ${execpath} ]];then
		if [[ -x ${execpath} ]];then
			echo "===== $(date "+%Y%m%d %T") Exec external command start : ${execpath} ====" | tee -a ${execlog}
			${dummyecho} ${execpath} | tee -a ${execlog}
			if (( $? > 0 ));then
				echo "!!!! Failed to exec : ${execpath} !!!!" | tee -a ${execlog}
				return 1
			fi
			echo "===== $(date "+%Y%m%d %T") Exec external command end : ${execpath} ====" | tee -a ${execlog}
		else
			echo "!!!! Can not exec : ${execpath} !!!!" | tee -a ${execlog}
			return 1
		fi
	fi
}

function CleanSpapshot {
	local filesystem=$1
	local snaplvdev=$2
	local mounteddir_snapshot=$3

	# unmount snapshot - xfsdump bug
	if [[ "${filesystem}" == "xfs" ]];then
		df | grep -E "^${snaplvdev}( +|$)" > /dev/null
		if (( $? == 0));then
			${dummyecho} umount "${snaplvdev}" >> ${execlog} 2>&1
			if (( $? > 0 ));then
				echo "!!!! Failed to umount :${snaplvdev} !!!!" | tee -a ${execlog}
				return 1
			fi
		fi
		${dummyecho} rmdir "${mounteddir_snapshot}" >> ${execlog} 2>&1
	fi

	# delete snapshotlv
	${dummyecho} lvm lvremove -f ${snaplvdev}
	if (( $? > 0 ));then
		echo "!!!! Failed to lvremove snapshot :${snaplvdev} !!!!" | tee -a ${execlog}
		return 1
	fi
}


# ==== PROCESS AREA ====================================================

export PATH=${PATH}:/sbin:/usr/sbin

exit1flg=0
bkupdate=$( date "+%Y%m%d" )

# set bklist_path
if [[ ! -z "$1" ]];then
	bklist_path=$1
else
	bklist_path=${bklist_path_default}
fi

# set bkupimg_prefix
if [[ ! -z "$2" ]];then
	bkupimg_prefix=$2
else
	bkupimg_prefix=${bkupimg_prefix_default}
fi

# set deldays
if [[ ! -z "$3" ]];then
	deldays=$3
else
	deldays=${deldays_default}
fi

# check to write log
if [[ -f ${execlog} ]];then
	if [[ ! -w ${execlog} ]];then
		echo "Can't write log file : ${execlog}"
		exit 1
	fi
else
	execlogdir=${execlog%/*}
	if [[ ! -d ${execlogdir} || ! -w ${execlogdir} ]];then
		echo "Can't write log dir : ${execlogdir}"
		exit 1
	fi
fi

# check to read bklist
if [[ ! -r "${bklist_path}" ]];then
	echo "!!!! Can't read backup list : ${bklist_path} !!!!" | tee -a ${execlog}
	exit 1
fi


# check mount
alreadymountflg=1
if [[ ! -z "${mountdir}" ]];then
	CheckMount ${mountdir}
	if (( $? > 0 ));then
		# mount
		alreadymountflg=0
		mount ${mountoption} ${mountdir} ${mounteddir} >> ${execlog} 2>&1
		CheckMount ${mountdir}
		if (( $? > 0 ));then
			echo "!!!! Failed to mount :  ${mountdir} ${mounteddir} !!!!" | tee -a ${execlog}
			exit 1
		fi
	fi
fi


while read getline
do
	# list sample
	# /dev/rootvg/rootlv	xfs	rootvg-rootlv-root	/backup	gzip
	# /dev/sda1	ext4	boot	 /backup
	# <source device path><TAB><filesystem><TAB><backup image name><TAB><distination backup image save directory>[<TAB><compress command>[<TAB><preexec command path>[<TAB><postexec command path>]]]
	#    <source device path>                      :(Required)disk device or path(vfat only) that this script acquires a dump image.
	#    <filesystem>                              :(Required)filesystem name. xfs ext4 ext3 vfat
	#    <backup image name>                       :(Required)name that this script adds to a dump image.
	#    <distination backup image save directory> :(Required)directory that this script save a dump image.
	#    <compress command>                        :(Option)command to use so that this script compresses a dump image. if omit, no compress.
	#    <preexec command path>                    :(Option)command to carry out before this script acquires a dump image. if omit, no exec.
	#    <postexec command path>                   :(Option)command to carry out after this script acquires a dump image. if omit, no exec.

	echo "${getline}" | egrep -e "^ *#" > /dev/null
	if (( $? == 0 ));then
		#echo "comment line : ${getline}"
		continue
	fi

	if [[ -z ${getline} ]];then
		echo "empty line"
		continue
	fi

	# file system device
	fsdev=$( echo "${getline}" | cut -f1 )
	filesystem=$( echo "${getline}" | cut -f2 )
	bkupimgname=$( echo "${getline}" | cut -f3 )
	bkupdir=$( echo "${getline}" | cut -f4 )
	compress_cmd=$( echo "${getline}" | cut -f5 )
	preexec=$( echo "${getline}" | cut -f6 )
	postexec=$( echo "${getline}" | cut -f7 )
	# supplement bkupdir
	if [[ -z "${bkupdir}" ]];then
		bkupdir=${bkupdir_defalut}
	fi

	# check to write bkupdir
	if [[ ! -w "${bkupdir}" || ! -d "${bkupdir}" || -z "${bkupdir}" ]];then
		echo "!!!! Can't write to backup dir : ${bkupdir} !!!!" | tee -a ${execlog}
		exit1flg=1
		continue
	fi

	if [[ ${compress_cmd} = "gzip" ]];then
		cmpextfix="gz"
	elif [[ ${compress_cmd} = "bzip2" ]];then
		cmpextfix="bz2"
	elif [[ ${compress_cmd} = "compress" ]];then
		cmpextfix="Z"
	elif [[ -z ${compress_cmd} ]];then
		compress_cmd=""
		cmpextfix=""
	else
		#echo "no support compress command : ${compress_cmd}" | tee -a ${execlog}
		compress_cmd=""
		cmpextfix=""
	fi

	bkupfile_path="${bkupdir}/${bkupimg_prefix}_${bkupimgname}_${bkupdate}.dump"
	tarfile_path="${bkupdir}/${bkupimg_prefix}_${bkupimgname}_${bkupdate}.tar"
	if [[ ! -z "${compress_cmd}" ]];then
		bkupfile_path="${bkupfile_path}"."${cmpextfix}"
		tarfile_path="${tarfile_path}"."${cmpextfix}"
	fi

	# check device lvm or partition
	#echo ${fsdev} | grep -E "(^\/dev\/mapper\/|^\/dev\/.+\/.+)"
	lvflg=0
	which lvdisplay > /dev/null 2>&1
	if (( $? == 0 ));then
		lvdisplay ${fsdev} > /dev/null 2>&1
		if (( $? == 0 ));then
			lvflg=1
		fi
	fi
	
	if [[ ${lvflg} = 1 && ! -z ${snaplvname} ]];then
		
		# lvm

		# get snaplvdev
		echo ${fsdev} | grep -E "^\/dev\/mapper\/" > /dev/null 2>&1
		if (( $? == 0 ));then
			# /dev/mapper/hogevg-hogelv
			fsdev_tmp1=${fsdev%-*}
			vgname=${fsdev_tmp1##*/}
			snaplvdev="/dev/${vgname}/${snaplvname}"
		else
			# /dev/hogevg/hogelv
			snaplvdev=${fsdev%/*}/${snaplvname}
		fi
		
		# preexec
		ExecExternalCommand "${preexec}"
		if (( $? > 0 ));then
			exit1flg=1
			continue
		fi
		
		# sync
		sync;sync;sync

		# lv snapshot
		${dummyecho} lvm lvcreate -s -L "${snaplvsize}" -n "${snaplvname}" "${fsdev}"  >> ${execlog} 2>&1
		if (( $? > 0 ));then
			echo "!!!! Failed to lvcreate snapshot :${snaplvname} ${fsdev} !!!!" | tee -a ${execlog}
			exit 1
		fi

		# postexec
		ExecExternalCommand "${postexec}"
		if (( $? > 0 ));then
			CleanSpapshot "${filesystem}" "${snaplvdev}" "${mounteddir_snapshot}"
			exit1flg=1
			continue
		fi

		# mount snapshot - xfsdump bug workaround
		if [[ "${filesystem}" == "xfs" ]];then
			if [[ ! -d "${mounteddir_snapshot}" ]];then
				${dummyecho} mkdir "${mounteddir_snapshot}" >> ${execlog} 2>&1
			fi
			${dummyecho} mount -t xfs -o ro,nouuid "${snaplvdev}" "${mounteddir_snapshot}" >> ${execlog} 2>&1
			if (( $? > 0 ));then
				CleanSpapshot "${filesystem}" "${snaplvdev}" "${mounteddir_snapshot}"
				exit 1
			fi
		fi

		# dump
		sync;sync;sync
		echo "===== $(date "+%Y%m%d %T") dump start : ${fsdev} - ${snaplvname} ====" | tee -a ${execlog}
		if [[ ! -z "${compress_cmd}" ]];then
			if [[ "${filesystem}" == "xfs" ]];then
				${dummyecho} xfsdump -J -l 0 - ${snaplvdev} | ${compress_cmd} -c > ${bkupfile_path}  2>> ${execlog}
				lst_dump_rc=( ${PIPESTATUS[@]} )
			elif [[ "${filesystem}" == "ext2" || "${filesystem}" == "ext3" || "${filesystem}" == "ext4" ]];then
				${dummyecho} dump 0f - ${snaplvdev} | ${compress_cmd} -c > ${bkupfile_path}  2>> ${execlog}
				lst_dump_rc=( ${PIPESTATUS[@]} )
			elif [[ "${filesystem}" == "vfat" || "${filesystem}" == "fat" ]];then
				${dummyecho} tar cf - ${fsdev} | ${compress_cmd} -c > ${tarfile_path} 2>> ${execlog}
				lst_dump_rc=( ${PIPESTATUS[@]} )
			else
				echo "???? Nomatch filesystem name : ${filesystem} ????" | tee -a ${execlog}
				CleanSpapshot "${filesystem}" "${snaplvdev}" "${mounteddir_snapshot}"
				exit1flg=1
				continue
			fi
		else
			if [[ "${filesystem}" == "xfs" ]];then
				${dummyecho} xfsdump -J -l 0 -L "full backup" -M "${bkupimgname}" -f ${bkupfile_path} ${snaplvdev}  >> ${execlog} 2>&1
				dump_rc=$?
			elif [[ "${filesystem}" == "ext2" || "${filesystem}" == "ext3" || "${filesystem}" == "ext4" ]];then
				${dummyecho} dump 0f ${bkupfile_path} ${snaplvdev}  >> ${execlog} 2>&1
				dump_rc=$?
			elif [[ "${filesystem}" == "vfat" || "${filesystem}" == "fat" ]];then
				${dummyecho} tar cf ${tarfile_path} ${fsdev} >> ${execlog} 2>&1
				dump_rc=$?
			else
				echo "???? Nomatch filesystem name : ${filesystem} ????" | tee -a ${execlog}
				CleanSpapshot "${filesystem}" "${snaplvdev}" "${mounteddir_snapshot}"
				exit1flg=1
				continue
			fi
		fi

		echo "===== $(date "+%Y%m%d %T") dump end : ${fsdev} - ${snaplvname} ====" | tee -a ${execlog}
		sync;sync;sync

		# unmount snapshot - xfsdump bug
		if [[ "${filesystem}" == "xfs" ]];then
			${dummyecho} umount "${snaplvdev}" >> ${execlog} 2>&1
			if (( $? > 0 ));then
				echo "!!!! Failed to umount :${snaplvdev} !!!!" | tee -a ${execlog}
				CleanSpapshot "${filesystem}" "${snaplvdev}" "${mounteddir_snapshot}"
				exit 1
			fi
			${dummyecho} rmdir "${mounteddir_snapshot}" >> ${execlog} 2>&1
		fi

		# delete snapshotlv
		${dummyecho} lvm lvremove -f ${snaplvdev}
		if (( $? > 0 ));then
			echo "!!!! Failed to lvremove snapshot :${snaplvname} ${fsdev} !!!!" | tee -a ${execlog}
			exit 1
		fi

	else
		# partiton or lvm no snapshot

		# preexec
		ExecExternalCommand "${preexec}"
		if (( $? > 0 ));then
			exit1flg=1
			continue
		fi

		# dump
		sync;sync;sync
		echo "===== $(date "+%Y%m%d %T") dump start : ${fsdev} ====" | tee -a ${execlog}
		if [[ ! -z "${compress_cmd}" ]];then
			if [[ "${filesystem}" == "xfs" ]];then
				${dummyecho} xfsdump -l 0 - ${fsdev} | ${compress_cmd} -c > ${bkupfile_path}  2>> ${execlog}
				lst_dump_rc=( ${PIPESTATUS[@]} )
			elif [[ "${filesystem}" == "ext2" || "${filesystem}" == "ext3" || "${filesystem}" == "ext4" ]];then
				${dummyecho} dump 0f - ${fsdev} | ${compress_cmd} -c > ${bkupfile_path}  2>> ${execlog}
				lst_dump_rc=( ${PIPESTATUS[@]} )
			elif [[ "${filesystem}" == "vfat" || "${filesystem}" == "fat" ]];then
				${dummyecho} tar cf - ${fsdev} | ${compress_cmd} -c > ${tarfile_path} 2>> ${execlog}
				lst_dump_rc=( ${PIPESTATUS[@]} )
			else
				echo "???? Nomatch filesystem name : ${filesystem} ????" | tee -a ${execlog}
				exit1flg=1
				continue
			fi
		else
			if [[ "${filesystem}" == "xfs" ]];then
				${dummyecho} xfsdump -l 0 -L "full backup" -M "${bkupimgname}" -f ${bkupfile_path} ${fsdev}  >> ${execlog} 2>&1
				dump_rc=$?
			elif [[ "${filesystem}" == "ext2" || "${filesystem}" == "ext3" || "${filesystem}" == "ext4" ]];then
				${dummyecho} dump 0f ${bkupfile_path} ${fsdev}  >> ${execlog} 2>&1
				dump_rc=$?
			elif [[ "${filesystem}" == "vfat" || "${filesystem}" == "fat" ]];then
				${dummyecho} tar cf ${tarfile_path} ${fsdev} >> ${execlog} 2>&1
				dump_rc=$?
			else
				echo "???? Nomatch filesystem name : ${filesystem} ????" | tee -a ${execlog}
				exit1flg=1
				continue
			fi
		fi
		echo "===== $(date "+%Y%m%d %T") dump end : ${fsdev} ====" | tee -a ${execlog}
		sync;sync;sync
		
		# postexec
		ExecExternalCommand "${postexec}"
		if (( $? > 0 ));then
			exit1flg=1
			continue
		fi
	fi
	
	if [[ ! -z "${compress_cmd}" ]];then
		if (( ${lst_dump_rc[0]} > 0 ));then
			echo "!!!! Failed to dump : ${fsdev} !!!!" | tee -a ${execlog}
			exit1flg=1
		else
			if (( ${lst_dump_rc[1]} > 0 ));then
				echo "!!!! Failed to compress : ${fsdev} !!!!" | tee -a ${execlog}
				exit1flg=1
			fi
		fi
	else
		if (( ${dump_rc} > 0 ));then
			echo "!!!! Failed to dump : ${fsdev} !!!!" | tee -a ${execlog}
			exit1flg=1
		fi
	fi
done < ${bklist_path}

# ---- info ----
${dummyecho} cat /proc/partitions > ${bkupdir}/${bkupimg_prefix}_proc_partitions_${bkupdate}.txt
${dummyecho} cat /proc/mounts > ${bkupdir}/${bkupimg_prefix}_proc_mounts_${bkupdate}.txt
${dummyecho} fdisk -l > ${bkupdir}/${bkupimg_prefix}_fdisk_${bkupdate}.txt
${dummyecho} lvm pvdisplay | tee ${bkupdir}/${bkupimg_prefix}_pvdisplay_${bkupdate}.txt
${dummyecho} lvm vgdisplay | tee ${bkupdir}/${bkupimg_prefix}_vgdisplay_${bkupdate}.txt
${dummyecho} lvm lvdisplay | tee ${bkupdir}/${bkupimg_prefix}_lvdisplay_${bkupdate}.txt
${dummyecho} cat /etc/fstab > ${bkupdir}/${bkupimg_prefix}_fstab_${bkupdate}.txt
${dummyecho} df > ${bkupdir}/${bkupimg_prefix}_df_${bkupdate}.txt

# ---- delete ----
listeddir=""
while read getline
do
	echo "${getline}" | egrep -e "^ *#" > /dev/null
	if (( $? == 0 ));then
		#echo "comment line : ${getline}"
		continue
	fi

	if [[ -z ${getline} ]];then
		#echo "empty line"
		continue
	fi

	bkupdir=$( echo "${getline}" | awk '{print $4}' )
	if [[ -z ${bkupdir} ]];then
		bkupdir=${bkupdir_defalut}
	fi

	# if bkupdir is searched , not search
	echo "${listeddir}" | grep -E " ${bkupdir}( |$)" > /dev/null
	if (( $? > 0 )) ;then

		rmlist=$( find ${bkupdir} -maxdepth 1 -name "${bkupimg_prefix}_*" -mtime +${deldays} )

		listeddir=" ${listeddir} ${bkupdir}"
	fi

done < ${bklist_path}

if [[ ! -z ${rmlist} ]];then
	${dummyecho} rm -f ${rmlist} >> ${execlog} 2>&1
	for rmfile in ${rmlist}
	do
		echo "delete file :" ${rmfile} | tee -a ${execlog}
	done
	#echo "delete file :" ${rmlist} | tee -a ${execlog}
fi


# ---- umount ----
if [[ ! -z "${mountdir}" ]];then
	if [[ ${alreadymountflg} = 0 ]];then
		umount ${mounteddir} >> ${execlog} 2>&1
		if (( $? > 0 ));then
			echo "!!!! Failed to umount : ${mounteddir} !!!!" | tee -a ${execlog}
			exit1flg=1
		fi
	fi
fi

if [[ ${exit1flg} = 1 ]];then
	exit 1
fi

