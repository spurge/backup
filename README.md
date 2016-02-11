Backup
======

A super simple rsync/s3 backup script.

* For tar-ing and compressing files,
* for doing mysqldump and compress them
* and for sending the stuff to s3 and some host with rsync.

Usage: ``backup.sh configfile.conf``

The Config File
---------------

	# Where to store all the packed filez and dumpz
	# The shit will be removed after they've been synced
	tmp=/tmp
	# Secret S3 data
	s3=username:key:secret@bucket
	# Be sure that the host's public ssh-key is placed in authorized_keys at the host
	rsync=user@host/var/backups
	# Files/directories to be packed: /var/www/wordpress/wp-content/uploads for example!
	files=(stuff:/var/www/stuff snuff:/var/www/snuff)
	# Mysql databases to dump
	mysql=(user:password@host/database user:password@host/another-database)
