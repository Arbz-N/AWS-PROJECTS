# Persistent Storage on Kubernetes using EFS with EKS

## Overview

This project demonstrates how to implement **persistent shared storage** for Kubernetes workloads running on AWS by integrating **Elastic File System (EFS)** with an **EKS cluster**.
The setup enables pods to share data and retain files even after pod restarts or rescheduling,
making it suitable for:

* Stateful workloads
* Shared file storage between pods
* Logs and uploads persistence
* Microservices requiring shared storage

---

## What is EFS?

**Amazon EFS** is a scalable, fully managed NFS file system that can be mounted by multiple EC2 instances or Kubernetes pods simultaneously.

Key benefits:

* Shared storage across pods
* Automatically scales storage
* Fully managed (no disk provisioning required)
* Supports ReadWriteMany access mode

---

## Architecture Flow

1. Create an EFS file system in AWS
2. Create an EFS Access Point for Kubernetes access
3. Install the EFS CSI Driver in the EKS cluster
4. Create a Kubernetes StorageClass using EFS
5. Create a PersistentVolumeClaim (PVC)
6. Mount the PVC inside a deployment
7. Verify data persistence after pod restart

---

## Prerequisites

Ensure the following tools are installed:

* kubectl
* eksctl
* awscli configured with credentials
* Helm package manager
* Existing EKS cluster

Required permissions:

* IAM role for cluster
* IAM role for worker nodes
* IAM role for EFS CSI driver

---

## Step 1 — Create EFS File System

1. Open AWS Console → EFS
2. Click **Create file system**
3. Choose VPC matching your EKS cluster
4. Configure security group
5. Create the file system

After creation, create an **Access Point** for Kubernetes.

---

## Step 2 — Install EFS CSI Driver

Create IAM service account:

```bash
export CLUSTER_NAME=<YOUR_CLUSTER_NAME>
export ROLE_NAME=AmazonEKS_EFS_CSI_DriverRole

eksctl create iamserviceaccount \
  --name efs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name $ROLE_NAME \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy \
  --approve
```

Update trust policy:

```bash
TRUST_POLICY=$(aws iam get-role --output json --role-name $ROLE_NAME --query 'Role.AssumeRolePolicyDocument' | \
sed -e 's/efs-csi-controller-sa/efs-csi-*/' -e 's/StringEquals/StringLike/')

aws iam update-assume-role-policy \
  --role-name $ROLE_NAME \
  --policy-document "$TRUST_POLICY"
```
for more information about CSI-driver refer to this official document
https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
Install CSI driver via Helm:

```bash
To install helm : https://phoenixnap.com/kb/install-helm

helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver
```

---

## Step 3 — Get Required IDs

Retrieve your filesystem ID:

aws efs describe-file-systems --region <REGION> \
  --query "FileSystems[*].FileSystemId" \
  --output text

Retrieve access point:

aws efs describe-access-points \
  --file-system-id <FILE_SYSTEM_ID> \
  --region <REGION>

## Step 4 — Create StorageClass

Replace placeholders before applying.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: <YOUR_FILESYSTEM_ID>
  accessPointId: <YOUR_ACCESS_POINT_ID>
  directoryPerms: "700"
  basePath: "/k8s"
mountOptions:
  - tls
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

Apply:

```bash
kubectl apply -f storage_class.yml
```

---

## Step 5 — Create PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
```

Apply:

```bash
kubectl apply -f pvc.yml
kubectl get pvc efs-pvc -w
```

---

## Step 6 — Security Group Requirement

EFS mount target security group must allow **NFS traffic (TCP 2049)** from worker node security group.

Example rule:

| Type | Protocol | Port | Source              |
| ---- | -------- | ---- | ------------------- |
| NFS  | TCP      | 2049 | <WORKER_NODE_SG_ID> |

No change required in worker node SG.

---

## Step 7 — Test Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: efs-test-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: efs-test
  template:
    metadata:
      labels:
        app: efs-test
    spec:
      containers:
      - name: efs-test
        image: busybox
        command: ["sleep", "3600"]
        volumeMounts:
        - name: efs-storage
          mountPath: /mnt/efs
      volumes:
      - name: efs-storage
        persistentVolumeClaim:
          claimName: efs-pvc
```

Apply:

```bash
kubectl apply -f deployment.yml
```

---

## Step 8 — Verify Persistence

Enter the pod:

```bash
kubectl exec -it <POD_NAME> -- /bin/sh
```

Create file:

```bash
echo "Hello EFS" > /mnt/efs/test.txt
cat /mnt/efs/test.txt
```

If output shows **Hello EFS**, storage is working correctly.

Delete the pod and recreate it — the file should still exist.

---

## Technologies Used

* AWS EKS
* Amazon EFS
* Kubernetes
* Helm
* AWS CLI

---

## Outcome

After completing this project, you will understand:

* How shared storage works in Kubernetes
* How to integrate AWS EFS with EKS
* How to use CSI drivers for dynamic storage provisioning
* How to test persistence across pod restarts

---

## Author

Your Name
Your GitHub Profile
