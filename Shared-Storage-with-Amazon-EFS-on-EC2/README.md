# Shared Storage with Amazon EFS on EC2 (Ubuntu)

    Overview
    EFSLab is a hands-on project that sets up Amazon Elastic File System (EFS) and mounts it on two EC2 Ubuntu instances simultaneously, demonstrating real-time shared storage. Both instances read and write to the same filesystem, proving that EFS is the right tool for shared, concurrent access across multiple EC2s.
    Key highlights:
    
    EFS created in the default VPC with generalPurpose performance and bursting throughput
    Dedicated EFS Security Group with NFS port 2049 open to VPC CIDR only
    Mount targets created in two Availability Zones for high availability
    Ubuntu-specific NFS4 mount method (-t nfs4 -o nfsvers=4.1) — not efs type
    fstab configured with correct Ubuntu format using nfs4 type and _netdev
    Real-time sync demonstrated: Instance 2 writes → Instance 1 sees it immediately
    Common errors documented: NXDOMAIN, port 2049 hang, wrong fstab type

Project Structure

    Shared-Storage-with-Amazon-EFS-on-EC2/
    │
    ├── scripts/
    │   ├── setup-efs.sh          # VPC, SG, EFS, mount targets (run from CLI)
    │   ├── mount-instance.sh     # Install nfs-common + mount (run on EC2)
    │   └── write-shared-data.sh  # Create dirs + test data on EFS
    │
    └── README.md

Prerequisites:

    Requirement                 Detail

    AWS Account                 EC2, EFS, VPC, IAM permissions
    AWS CLI                     Installed and configured
    EC2 Ubuntu instance         Already running (Instance 1)
    SSH key pair                For launching Instance 2


Architecture

        us-east-1
          ┌──────────────────────────────────────────────────────────┐
          │  Default VPC (172.31.0.0/16)                             │
          │                                                          │
          │  ┌────────────────┐        ┌────────────────┐            │
          │  │  Instance 1    │        │  Instance 2    │            │
          │  │  (Ubuntu)      │        │  (Ubuntu)      │            │
          │  │  /mnt/efs ──┐  │        │  /mnt/efs ──┐  │            │
          │  └─────────────│──┘        └─────────────│──┘            │
          │                │  NFS4 port 2049          │              │
          │                ▼                          ▼              │
          │  ┌──────────────────────────────────────────────────┐    │
          │  │  Amazon EFS (fs-xxxxxxxxx)                       │    │
          │  │  ├── Mount Target (AZ1) — 172.31.x.x             │    │
          │  │  └── Mount Target (AZ2) — 172.31.x.x             │    │
          │  │                                                  │    │
          │  │  /mnt/efs/                                       │    │
          │  │  ├── shared/messages.txt  ← both read/write      │    │
          │  │  ├── logs/app.log         ← both append          │    │
          │  │  ├── configs/app.conf     ← shared config        │    │
          │  │  └── uploads/             ← shared uploads       │    │
          │  └──────────────────────────────────────────────────┘    │
          │                                                          │
          │  EFS Security Group: TCP 2049 from 172.31.0.0/16 only    │
          └──────────────────────────────────────────────────────────┘

Export Variable First:

    export AWS_REGION="us-east-1"
    export PROJECT_TAG="EFS-Lab"
    aws sts get-caller-identity  # 

Task 1 — Network + Security Group Setup

    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --region $AWS_REGION \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    echo "VPC: $VPC_ID"
    
    # Get two subnets from different AZs
    SUBNET_AZ1=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[0].SubnetId' --output text)
    
    SUBNET_AZ2=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[1].SubnetId' --output text)
    
    # Create dedicated EFS Security Group
    EFS_SG_ID=$(aws ec2 create-security-group \
        --region $AWS_REGION \
        --group-name "EFS-Lab-SG" \
        --description "EFS Lab mount target security group" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    
    # Allow NFS port 2049 from VPC CIDR only (NOT 0.0.0.0/0)
    aws ec2 authorize-security-group-ingress \
        --group-id $EFS_SG_ID \
        --protocol tcp \
        --port 2049 \
        --cidr 172.31.0.0/16
    
    echo "EFS SG: $EFS_SG_ID"

Task 2 — Create EFS Filesystem
    
    EFS_ID=$(aws efs create-file-system \
        --region $AWS_REGION \
        --performance-mode generalPurpose \
        --throughput-mode bursting \
        --encrypted \
        --tags Key=Name,Value="EFS-Lab-FS" Key=Project,Value=$PROJECT_TAG \
        --query 'FileSystemId' --output text)
    
    echo "EFS ID: $EFS_ID"
    
    # Build DNS name
    export EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
    echo "EFS DNS: $EFS_DNS"
    
    # Optional: Lifecycle policy (cost saving — production best practice)
    aws efs put-lifecycle-configuration \
        --file-system-id $EFS_ID \
        --lifecycle-policies TransitionToIA=AFTER_30_DAYS \
                            TransitionToPrimaryStorageClass=AFTER_1_ACCESS