# dumpbackup
This program is a shell script that backs up the Linux xfs / ext2 / ext3 / ext4 file system using the xfsdump / dump command.

## Description
 This command does not just execute xfsdump/dump commands, but it can also mount the nfs/cifs directory before executing this plog. The program can mount the nfs/cifs directory before performing a backup, or it can run scripts that you specify before and after a file system backup. Also, if you are using LVM, you can run an LVM snapshot to create a static point and then run the xfsdump/dump command. the EFI system partitions are backed up with the tar command. It also collects the information needed for the restore.

The emphasis is on providing an easy way to manage backups, so it is intended for use on a non-critical server. It is functionally unsuitable for use in an enterprise server. It assumes that the backup image is stored on a disk.

This program is implemented by bash script. So it is easy to install. 

## Demo

## Features
* Use the xfsdump or dump command for file system backup
* Back up EFI system partitions using the tar command
* Create a static point (snapshot) and then backup (only when using LVM)
* Compress the backup image
* Mount the nfs/cifs directory before performing a backup
* Execute the commands specified before and after the backup is performed on each file system
* Automatic deletion of backup files that have expired
* Obtaining the Information Required for Restoration

## Requirement
* bash
* dump
* xfsdump

## Installation
0. Install the dump command
```
# dnf install dump
```
0. Install the xfsdump command
```
# dnf install xfsdump
```
1. Download the archive file
2. Extract the downloaded archive file
```
# tar zxf dumpbackup_2.0.0.0.tar.gz
```
3. Change to the extracted directory
```
# cd dumpbackup_2.0.0
```
4. Change the configuration. Pay attention to the location of the log output.
```
# vi dumpbackup.sh
```
5. Please copy it to any location.
```
# cp . /dumpbackup.sh <INSTALL DIRECTORY>
```
6. Set the permissions.
```
# chmod 700 Anywhere/dumpbackup.sh
```
7. Create a backup list file
```
# cp diskdump.lst <INSTALL DIRECTORY>/<ANY FILENAME>.lst
# vi <INSTALL DIRECTORY>/<ANY FILENAME>.lst
```
8. (Optional) Set up scheduled execution.
```
# vi /etc/cron.d/dumpbackup
0 0 * * 0 root <INSTALL DIRECTORY>/dumpbackup.sh
```

## Usage
```
# ./dumpbackup.sh[ <backup list file path>[ <backup file name prefix>[ <backup file storage days>]]
```

## Note
* I am not responsible for any damage or other consequences that may arise from the use of this script. Use at your own risk.
* Logs should be rotated as needed. It is not a daemon and does not need to be restarted.
* I made this in my spare time, so I have a sense of inadequacy. Please forgive me for that part.
* I don't write the source code in a cool way, so it's not helpful.

## License
GPL-3.0 License

## Author

