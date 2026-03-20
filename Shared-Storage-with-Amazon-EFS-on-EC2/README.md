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

Task 3 — Create Mount Targets (Two AZs)

    MT_ID_1=$(aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $SUBNET_AZ1 \
        --security-groups $EFS_SG_ID \
        --query 'MountTargetId' --output text)
    
    MT_ID_2=$(aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $SUBNET_AZ2 \
        --security-groups $EFS_SG_ID \
        --query 'MountTargetId' --output text)
    
    echo "Waiting 30 seconds..."
    sleep 30
    
    # Verify VpcId matches EC2 VPC
    aws efs describe-mount-targets \
        --file-system-id $EFS_ID \
        --query 'MountTargets[*].{ID:MountTargetId,AZ:AvailabilityZoneName,State:LifeCycleState,IP:IpAddress,VPC:VpcId}' \
        --output table

    Verify VpcId matches your EC2 instance VPC. Mismatch = NXDOMAIN error on mount.


Task 4 — Mount on Instance 1 (Ubuntu)

    # Run on EC2 Instance 1
    export EFS_ID="fs-xxxxxxxxx"
    export AWS_REGION="us-east-1"
    export EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
    
    # Step 1: Connectivity check FIRST
    nslookup $EFS_DNS          # DNS resolves? 
    nc -zv $EFS_DNS 2049       # Port 2049 open? 
    
    # Step 2: Install nfs-common
    sudo apt-get install -y nfs-common
    
    # Step 3: Mount
    sudo mkdir -p /mnt/efs
    sudo mount -t nfs4 -o nfsvers=4.1 $EFS_DNS:/ /mnt/efs
    
    # Step 4: Verify
    df -h /mnt/efs
    # Filesystem  Size  Used Avail Use%  Mounted on
    # fs-xxx.efs  8.0E     0  8.0E   0%  /mnt/efs  
    # (8.0E = unlimited — EFS auto-grows)
    
    # Step 5: Set ownership and test write
    sudo chown $(whoami):$(whoami) /mnt/efs
    sudo chmod 755 /mnt/efs
    echo "EFS mount test - $(date)" > /mnt/efs/test.txt
    cat /mnt/efs/test.txt  # 

Add to fstab (Ubuntu Format)

    # Backup first — ALWAYS
    sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)
    
    # Correct Ubuntu format — use nfs4 type, NOT efs type
    echo "${EFS_DNS}:/ /mnt/efs nfs4 nfsvers=4.1,_netdev 0 0" | sudo tee -a /etc/fstab
    
    # Test auto-mount
    sudo umount /mnt/efs
    sudo systemctl daemon-reload
    sudo mount -a
    df -h /mnt/efs  # 

Task 5 — Write Shared Data (Instance 1)
 
    mkdir -p /mnt/efs/{shared,logs,configs,uploads}
    
    cat << 'EOF' > /mnt/efs/configs/app.conf
    DB_HOST=rds.us-east-1.amazonaws.com
    DB_PORT=5432
    APP_ENV=production
    LOG_LEVEL=info
    EOF
    
    echo "$(date) | Instance-1 | Server started" >> /mnt/efs/logs/app.log
    echo "Hello from Instance 1! Time: $(date)"  >> /mnt/efs/shared/messages.txt
    
    ls -lR /mnt/efs/
    echo "Instance 1 wrote data to EFS "

Task 6 — Launch Instance 2 and Mount EFS

    # Get Instance 1 details
    AMI_ID=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].ImageId' --output text)
    
    SUBNET_ID=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].SubnetId' --output text)
    
    KEY_NAME=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].KeyName' --output text)
    
    EC2_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Launch Instance 2
    INSTANCE2_ID=$(aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type t2.micro \
        --subnet-id $SUBNET_ID \
        --key-name $KEY_NAME \
        --security-group-ids $EC2_SG_ID \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EFS-Lab-Instance2}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    aws ec2 wait instance-running --instance-ids $INSTANCE2_ID
    
    INSTANCE2_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE2_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    
    echo "SSH: ssh -i ${KEY_NAME}.pem ubuntu@${INSTANCE2_IP}"

    
    Mount EFS on Instance 2
    
    # SSH into Instance 2, then:
    export EFS_DNS="fs-xxxxxxxxx.efs.us-east-1.amazonaws.com"
    
    sudo apt-get install -y nfs-common
    nc -zv $EFS_DNS 2049  # 
    
    sudo mkdir -p /mnt/efs
    sudo mount -t nfs4 -o nfsvers=4.1 $EFS_DNS:/ /mnt/efs
    df -h /mnt/efs  # 


Task 7 — Real-Time Shared Data Test

    # On Instance 2: Read Instance 1's data
    cat /mnt/efs/configs/app.conf      #  Instance 1's config
    cat /mnt/efs/shared/messages.txt   #  "Hello from Instance 1!"
    cat /mnt/efs/logs/app.log          #  Instance 1's logs
    
    # On Instance 2: Write
    echo "$(date) | Instance-2 | Started" >> /mnt/efs/logs/app.log
    echo "Hello from Instance 2! Time: $(date)" >> /mnt/efs/shared/messages.txt
    
    # On Instance 1: Verify instantly
    cat /mnt/efs/shared/messages.txt
    # Hello from Instance 1! ...
    # Hello from Instance 2! ...  ← appears immediately 

Live Watch Test

    # Terminal 1 (Instance 1):
    watch -n 1 'cat /mnt/efs/shared/messages.txt'
    
    # Terminal 2 (Instance 2):
    for i in {1..5}; do
        echo "Live update $i: $(date)" >> /mnt/efs/shared/messages.txt
        sleep 2
    done
    # Instance 1 terminal updates in real time 