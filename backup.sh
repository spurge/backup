#!/bin/bash

########################################################################
# This program is free software: you can redistribute it and/or modify #
# it under the terms of the GNU General Public License as published by #
# the Free Software Foundation, either version 3 of the License, or    #
# (at your option) any later version.                                  #
#                                                                      #
# This program is distributed in the hope that it will be useful,      #
# but WITHOUT ANY WARRANTY; without even the implied warranty of       #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        #
# GNU General Public License for more details.                         #
#                                                                      #
# See <http://www.gnu.org/licenses/>                                   #
########################################################################

function pack_files() {
	date=$1

	if [[ $2 =~ ^([^:]+):([^$]+)$ ]]; then
		name=${BASH_REMATCH[1]}
		source=${BASH_REMATCH[2]}
		file=${name}.${date}.tar.bz2
	else
		echo "File config error: $2"
		exit 2
	fi

	tar cj $source > $file
	echo $file
}

function dump_mysql() {
	date=$1

	if [[ $2 =~ ^([^:]+):([^@]+)@([^/]+)/([^$]+)$ ]]; then
		user=${BASH_REMATCH[1]}
		passwd=${BASH_REMATCH[2]}
		host=${BASH_REMATCH[3]}
		db=${BASH_REMATCH[4]}
		file=${db}.${date}.sql.bz2
	else
		echo "Mysql config error: $2"
	fi

	mysqldump -u $user -p$passwd -h $host $db | bzip2 > $file
	echo $file
}

function send_with_rsync() {
	if [[ $1 =~ ^([^@]+)@([^/]+)(/[^$]+)$ ]]; then
		user=${BASH_REMATCH[1]}
		host=${BASH_REMATCH[2]}
		dest=${BASH_REMATCH[3]}
	else
		echo "Rsync config error: $1"
		exit 2
	fi

	rsync -az . ${user}@${host}:${dest}
}

function hmac_sha256s() {
	key="$1"
	data="$2"
	shift 2
	printf "$data" | openssl dgst -binary -sha256 -hmac "$key" | od -An -vtx1 | sed 's/[ \n]//g' | sed 'N;s/\n//'
}

function hmac_sha256h() {
	KEY="$1"
	DATA="$2"
	shift 2
	printf "$data" | openssl dgst -binary -sha256 -mac HMAC -macopt "hexkey:$key" | od -An -vtx1 | sed 's/[ \n]//g' | sed 'N;s/\n//'
}

function send_to_s3() {
	if [[ $1 =~ ^([^:]+):([^:]+):([^@]+)@([^$]+)$ ]]; then
		STARTS_WITH=$2
		AWS_ACCESS_KEY=${BASH_REMATCH[2]}
		AWS_SECRET_KEY=${BASH_REMATCH[3]}
		BUCKET=${BASH_REMATCH[4]}
	else
		echo "S3 config error: $1"
		exit 2
	fi

	FILE_TO_UPLOAD=$2
	REQUEST_TIME=$(date +"%Y%m%dT%H%M%SZ")
	REQUEST_REGION="eu-central-1"
	REQUEST_SERVICE="s3"
	REQUEST_DATE=$(printf "${REQUEST_TIME}" | cut -c 1-8)
	AWS4SECRET="AWS4"$AWS_SECRET_KEY
	ALGORITHM="AWS4-HMAC-SHA256"
	EXPIRE=$(date --date=@$(echo "$(date +'%s') + 30" | bc) +"%Y-%m-%dT%H:%M:%SZ")
	ACL="private"

	POST_POLICY='{"expiration":"'$EXPIRE'","conditions": [{"bucket":"'$BUCKET'" },{"acl":"'$ACL'" },["starts-with", "$key", "'$STARTS_WITH'"],["eq", "$Content-Type", "application/octet-stream"],{"x-amz-credential":"'$AWS_ACCESS_KEY'/'$REQUEST_DATE'/'$REQUEST_REGION'/'$REQUEST_SERVICE'/aws4_request"},{"x-amz-algorithm":"'$ALGORITHM'"},{"x-amz-date":"'$REQUEST_TIME'"}]}'

	UPLOAD_REQUEST=$(printf "$POST_POLICY" | openssl base64 )
	UPLOAD_REQUEST=$(echo -en $UPLOAD_REQUEST |  sed "s/ //g")

	SIGNATURE=$(hmac_sha256h $(hmac_sha256h $(hmac_sha256h $(hmac_sha256h $(hmac_sha256s $AWS4SECRET $REQUEST_DATE ) $REQUEST_REGION) $REQUEST_SERVICE) "aws4_request") $UPLOAD_REQUEST)

	curl \
		-F "key=""$STARTS_WITH" \
		-F "acl="$ACL"" \
		-F "Content-Type="application/octet-stream"" \
		-F "x-amz-algorithm="$ALGORITHM"" \
		-F "x-amz-credential="$AWS_ACCESS_KEY/$REQUEST_DATE/$REQUEST_REGION/$REQUEST_SERVICE/aws4_request"" \
		-F "x-amz-date="$REQUEST_TIME"" \
		-F "Policy="$UPLOAD_REQUEST"" \
		-F "X-Amz-Signature="$SIGNATURE"" \
		-F "file=@"$FILE_TO_UPLOAD https://$BUCKET.s3.$REQUEST_REGION.amazonaws.com/
}

function pack_and_send() {
	file=$(pack_files $1 $3)
	send_to_s3 $2 $file
}

function dump_and_send() {
	file=$(dump_mysql $1 $3)
	send_to_s3 $2 $file
}

function backup() {
	source $1

	LANG="en_US"
	orgdir=$(pwd)
	cd $tmp
	dir=$(date +'%s')
	i=1

	while [[ -d $dir ]]; do
		dir=$(date +'%s')${i}
		i=$i+1
	done

	mkdir $dir
	cd $dir

	date=$(date +'%a.%H' | tr '[:upper:]' '[:lower:]')
	workers=()

	if [[ ! -z $files ]]; then
		for file in ${files[@]}; do
			pack_and_send $date $s3 $file &
			workers+=($!)
		done
	fi

	if [[ ! -z $mysql ]]; then
		for m in ${mysql[@]}; do
			dump_and_send $date $s3 $m &
			workers+=($!)
		done
	fi

	wait ${workers[@]}

	if [[ ! -z $rsync ]]; then
		send_with_rsync $rsync
	fi

	cd $orgdir
	rm -R ${tmp}/${dir}
}

backup $@
