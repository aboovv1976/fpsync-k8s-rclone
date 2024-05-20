#!/bin/bash

#exit 1

[ -z "$FPART_JOBCOMMAND" ] && echo "Environt variable FPART_JOBCOMMAND for the job is not provided" && exit 1

# RCLONE_CONFIG_FILE=/tmp/rclone/rclone.conf
if [ -n "${BASE64_RCLONE_CONFIG}" ]
then
    RCLONE_CONFIG_FILE=/root/.config/rclone/rclone.conf
    mkdir -p `dirname $RCLONE_CONFIG_FILE`
    echo "${BASE64_RCLONE_CONFIG}" | base64 -d > ${RCLONE_CONFIG_FILE}
    echo "Created $RCLONE_CONFIG_FILE"
fi

echo "Starting $FPART_JOBCOMMAND"
echo "$FPART_JOBCOMMAND" > ./start.sh
chmod 755 start.sh
./start.sh
