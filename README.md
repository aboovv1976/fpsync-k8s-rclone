# Data Transfer between file systems and Object Storage

 ## Data transfer to Object Storage
 
 Use [rclone](https://rclone.org/) tool to send files from Lustre to object storage. It is a versatile tool used to migrate data across storage systems of various types. It supports multiple threads and multiple streams concurrently. It has POSIX file system interface and supports various back-end storage types including file systems and object storage. Rclone has support for native OCI Object Storage APIs. It can also be used as standalone from a Compute instance to sync a directory with object storage and vice versa. However, one instance may not meet the required performance levels. Multiple worker instances are helpful to achieve higher throughput. 

 ## Data Transfer to another POSIX complaint file system

 [rsync](https://rsync.samba.org/documentation.html) is a popular tool used to migrate and also to keep the file systems in sync. 

# Tool installation 

## rclone

If transfer to object storage is needed, install [rclone](https://rclone.org/install/) and [oci-cli](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm#InstallingCLI__linux_and_unix). Configure [rclone](https://docs.oracle.com/en/solutions/move-data-to-cloud-storage-using-rclone/configure-rclone-object-storage.html#GUID-CFC20E9F-0576-4CF2-97A6-C19D85081F2E) for OCI object storage.

> \# bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
> \#  curl https://rclone.org/install.sh | bash

Configure API and CLI access from the Compute instance using [Instance principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm). The following is a very liberal permission given to rclone running on the instance. The policy gives permission to all the instances in dynamic group rclone-hosts to manage object storage in compartment storage

> allow dynamic-group rclone-hosts to manage object-family in compartment storage

## rsync
rsync usually comes installed on Ubuntu. It can be installed using the following command. 

> \# apt install rsync

## kubectl

If the data movers are run in OKE pods, the kubectl installation and its configuration should be done. 

Install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-binary-with-curl-on-linux) if rclone or rsync to be run as Kubernetes pods.

> \# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
> \# chmod 755 kubectl
> \# cp -a kubectl /usr/bin

The Compute instances managing OKE pods for rclone requires permission to operate the OKE cluster. The following policy can be used for this purpose.  

> allow dynamic-group fpsync-hosts to manage cluster-family in compartment storage

[Setup the kube config](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm#localdownload) file to have access to the OKE cluster.  

## modified fpsync (Ubuntu)

The fpsync is required to run rclone or rsync in parallel to scale out the data transfer.  

> \# apt-get install fpart
> \# git clone https://github.com/aboovv1976/fpsync-k8s-rclone.git
> \# cd fpsync-k8s-rclone/
> \# cp -p /usr/bin/fpsync /usr/bin/kfpsync
> \# patch /usr/bin/kfpsync fpsync.patch

# Running data migration tools
## rclone 

rclone can be run as a standalone tool to migrate data to object storage from file system. The following command sends /lst/ml-checkpoints to object storage bucket rclone-3, The chunk sizes is really large here as the files being transfers are big. 

Example: 
> rclone  --progress --stats-one-line --max-stats-groups 10   --oos-no-check-bucket --oos-upload-cutoff 10Mi --multi-thread-cutoff 10Mi --multi-thread-streams 64 --transfers 64 --checkers 128 --oos-chunk-size 5120Mi --oos-disable-checksum  --oos-attempt-resume-upload --oos-leave-parts-on-error copy /lst/ml-checkpoints/ rclone:rclone-3

## rsync

The simplest form of rsync command to copy data from source file system to target file system is:
> rsync -av /src/foo /dest

## Running tools as OKE pods 

The docker image build specification is available in the project. This can be used to build the image. Once image is build, it should be uploaded to a registry that can be accessed from OKE cluster. 

> \# rclone-rsync-image
> \#  docker build -t rclone-rsync . 
> \# docker login
> \# docker tag rclone-rsync:latest <registry url/rclone-rsync:latest>
> \# docker push <registry url/rclone-rsync:latest>

The sample yaml spec file for a data transfer job is provided with this project. 

# Scaling out data transfer

In order to scale data transfers, especially to storage systems that are relative high latency but are high throughput, requires parallelization of data transfers. One method would be to partition the directory structure in to multiple chunks and run the data transfer in parallel, either on the same compute instane or across multiple compute instances. This project demonstrate a method to achieve parallel transfers to achieve high throughput data transfers. 

 ## fpart file system partitioner

[fpart](http://www.fpart.org/#fpsync) is a tool that can be used to partition the directory structure. It can call tools such rsync, tar and rclone with a file system partition to run in parallel, and independent of each other. 

## fpsync - Running transfer tools in parallel

[fpsync](http://www.fpart.org/fpsync/) is a wrapper script, that wraps fpart to runs the transfer tools (rsync, rclone) in parallel. fpsync comes with fpart but it doesn't have native support for rclone support. fpsync supports remote workers to scaleout transfers across multiple Compute instances. fpsync also doesn't have support for Kubernetes pods. This project enhances fpsync to support rclone and have the ability to run Kubernetes pods as workers. 

## Running parallel rclone using fpsync on multiple instances

The fpsync can be invoked to run multiple data transfer tools concurrently on the same instance or across multiple instances.  

### Run on the same instance

Multiple file system partitions can be transferred concurrently using the same host. The following command partitions the file system in to 2048 files and runs two instances of rclone concurrently until all the partitions are transferred to rclone-1 bucket. 

> \# PART_NUM_FILES=2048 && kfpsync -v -m rclone -f \$PART_NUM_FILES -n 2 -o "--oos-no-check-bucket --oos-upload-cutoff 10Mi --multi-thread-cutoff 10Mi --multi-thread-streams 64 --transfers \$PART_NUM_FILES --checkers 128 --oos-chunk-size 5120Mi --oos-upload-concurrency 32 --oos-disable-checksum  --oos-leave-parts-on-error" /lst/ml-checkpoints/ rclone:rclone-1  
> 
### Run on multiple worker nodes

Every worker node should have the required tools (rsync, rclone, oci-cli, etc) installed and configured. Each of the worker nodes should be able to run the tool independently. The source file system should be mounted on the path on all worker nodes. Also, password-less login should be configured from the operator host. The fpsync tool refers to these worker nodes with host names. So, proper host resolution should be configured for operator host to reach the worker nodes. 

Prior to running the tools, a shared directory should be created that is accessible from all the worker nodes. 

> \# mkdir /lst/fpsync

> \# PART_NUM_FILES=2048 && kfpsync -v -m rclone -d /lst/fpsync  -f \$PART_NUM_FILES -n 2 -w 'root@worker-1 root@worker-2'  -o "--oos-no-check-bucket --oos-upload-cutoff 10Mi --multi-thread-cutoff 10Mi --multi-thread-streams 64 --transfers \$PART_NUM_FILES --checkers 128 --oos-chunk-size 5120Mi --oos-upload-concurrency 32 --oos-disable-checksum  --oos-leave-parts-on-error" /lst/ml-checkpoints/ rclone:rclone-1  

The above command will make partitions of 2048 files, and run it on two worker node until all the partitions are transferred to rclone-1 bucket. 

Similarly, rsync from one directory to another directory can be invoked using:

> \# ART_NUM_FILES=2048 && kfpsync -v -m rsync -d /lst/fpsync  -f \$PART_NUM_FILES -n 2 -w 'root@worker-1 root@worker-2' /lst/ml-checkpoints/ /dst


### Run multiple data transfer pods
