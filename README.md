# Data Transfer between file systems and Object Storage using OKE

This project demonstrate how multiple Kubernetes pods can be used to scale out data transfer between file systems and object storage. 

To scale out data transfers, especially to storage systems that are relative high latency but are high throughput, requires parallelization of data transfers. One method would be to partition the directory structure in to multiple chunks and run the data transfer in parallel, either on the same compute node or across multiple nodes. The pods run on multiple nodes to take advantage of network throughput and compute power each node has. 

# Tools

 ## fpart - File system partitioner

[fpart](http://www.fpart.org/#fpsync) is a tool that can be used to partition the directory structure. It can call tools such rsync, tar and rclone with a file system partition to run in parallel, and independent of each other. 

## fpsync - Running transfer tools in parallel

[fpsync](http://www.fpart.org/fpsync/) is a wrapper script that wraps fpart to runs the transfer tools (rsync, rclone) in parallel. The fpsync tools run from the fpsync operator host. 

 ## rclone - Data transfer to Object Storage
 
 Use [rclone](https://rclone.org/) tool to send files from Lustre to object storage. It is a versatile tool used to migrate data across storage systems of various types. It supports multiple threads and multiple streams concurrently. It has POSIX file system interface and supports various back-end storage types including file systems and object storage. Rclone has support for native OCI Object Storage APIs. 

 ## rsync - Data Transfer to another POSIX complaint file system

 [rsync](https://rsync.samba.org/documentation.html) is a popular tool used to migrate file systems. 

# Tool installation

The rclone or rsync tool is run from the Kubernetes pods and all the required tools are installed on the container image. However, Since fpsync operator host copies the rclone configuration to the pods, rclone should be installed and configured on the fpsync operator host.  

## rclone

If transfer to object storage is needed, install [rclone](https://rclone.org/install/) and [oci-cli](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm#InstallingCLI__linux_and_unix). Configure [rclone](https://docs.oracle.com/en/solutions/move-data-to-cloud-storage-using-rclone/configure-rclone-object-storage.html#GUID-CFC20E9F-0576-4CF2-97A6-C19D85081F2E) for OCI object storage.

```
# bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
# curl https://rclone.org/install.sh | bash
```

Configure API and CLI access from the node using [Instance principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm). The following is a liberal permission given to rclone running on the OKe nodes. The policy gives permission to all the hosts in dynamic group rclone-oke to manage object storage in compartment storage

```
allow dynamic-group rclone-oke to manage object-family in compartment storage
```

## kubectl

When the movers are in OKE pods, kubectl installation and its configuration should be done on the fpsync operator host. 

Install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-binary-with-curl-on-linux) if rclone or rsync to be run as Kubernetes pods.

```
# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# chmod 755 kubectl
# cp -a kubectl /usr/bin
```

The operator host requires permission to manage the OKE cluster. The following policy can be used for this purpose. A more granular permission can be configured to achieve the bare minimum requirement to control the pods. 

```
allow dynamic-group fpsync-host to manage cluster-family in compartment storage
```

[Setup the kube config](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm#localdownload) file to have access to the OKE cluster.  

## modified fpsync (Ubuntu)

The fpsync is required to run rclone or rsync in parallel to scale out the data transfer. The fpsync that comes with the fpart package doesn't support rclone or Kubernetes pods. The patch in this github project adds that the support for these tools. 

```
# apt-get install fpart
# git clone https://github.com/aboovv1976/fpsync-k8s-rclone.git
# cd fpsync-k8s-rclone/
# cp -p /usr/bin/fpsync /usr/bin/k-fpsync
# patch /usr/bin/k-fpsync fpsync.patch
```

## Container image 

The docker image build specification is available in this github project. This can be used to build the container image. Once image is build, it should be uploaded to a registry that can be accessed from OKE cluster. 

```
# rclone-rsync-image
# docker build -t rclone-rsync . 
# docker login
# docker tag rclone-rsync:latest <registry url/rclone-rsync:latest>
# docker push <registry url/rclone-rsync:latest>
```

A copy of the image is maintained in *fra.ocir.io/fsssolutions/rclone-rsync:latest*


The *sample* directory contains some examples and k8s job spec file. 

# Running k-fpsync

The patched fpsync (k-fpsync) can partition the source file system and scale out the transfer using multiple Kubernetes pods. The Kubernetes [pod affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) can be configured to control how many pods are started per node. This requires modification in fpsync to add the the affinity in the job spec file. 

Mount the source file system on the fpart operator host and create a shared directory that will be accessed by all the pods. This is directory where all the logs file and partition files are kept. 

```
# mkdir /data/fpsync
# PART_SIZE=512 && ./k-fpsync -v -k fra.ocir.io/fsssolutions/rclone-rsync:latest,lustre-pvc  -m rclone -d /data/fpsync  -f $PART_SIZE -n 2 -o "--oos-no-check-bucket --oos-upload-cutoff 10Mi --multi-thread-cutoff 10Mi --no-traverse --no-check-dest --multi-thread-streams 64 --transfers $PART_SIZE  --oos-upload-concurrency 8 --oos-disable-checksum  --oos-leave-parts-on-error" /data/src/ rclone:rclone-2
```

The above command will transfer */data/src* to object storage bucket *rclone-2*. It will start 2 pods at a time to transfer the file system partition created by fpart. The logs for the run are kept in /data/fpsync/{Run-Id}/log directory. 

Similarly, the rsync can be used to transfer files from one directory to another directory. 
```
# PART_SIZE=512 && ./kfpsync -v -k -k fra.ocir.io/fsssolutions/rclone-rsync:latest,lustre-pvc  -d /data/fpsync  -f $PART_SIZE -n 2 /data/src/ /data/dst
```

The sample outputs are provided in the sample directory. 

