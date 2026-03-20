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
