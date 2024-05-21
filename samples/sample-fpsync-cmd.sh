PART_SIZE=512 && ./kfpsync -v -K  -m rclone -d /data/fpsync  -f $PART_SIZE -n 2 -o "--oos-no-check-bucket --oos-upload-cutoff 10Mi --multi-thread-cutoff 10Mi --no-traverse --no-check-dest --multi-thread-streams 64 --transfers $PART_SIZE  --oos-upload-concurrency 8 --oos-disable-checksum  --oos-leave-parts-on-error" /data/src/ rclone:data-bucket-1