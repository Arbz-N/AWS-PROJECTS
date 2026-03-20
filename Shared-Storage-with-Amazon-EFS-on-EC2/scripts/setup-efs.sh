#!/bin/bash
# =============================================
# EFS Lab Setup Script
# Run from: local machine / AWS CLI
# =============================================

export AWS_REGION="us-east-1"
export PROJECT_TAG="EFS-Lab"

echo "=== EFS Lab Setup ==="
echo "Region: $AWS_REGION"

# ─── VPC + Subnets ───
VPC_ID=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)
echo "VPC: $VPC_ID"

SUBNET_AZ1=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' --output text)

SUBNET_AZ2=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[1].SubnetId' --output text)

echo "Subnet 1: $SUBNET_AZ1 | Subnet 2: $SUBNET_AZ2"

# ─── Security Group ───
EFS_SG_ID=$(aws ec2 create-security-group \
    --region $AWS_REGION \
    --group-name "EFS-Lab-SG" \
    --description "EFS Lab mount target security group" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text)
echo "EFS SG: $EFS_SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $EFS_SG_ID \
    --protocol tcp \
    --port 2049 \
    --cidr 172.31.0.0/16

echo "Port 2049 allowed"

# ─── EFS Filesystem ───
EFS_ID=$(aws efs create-file-system \
    --region $AWS_REGION \
    --performance-mode generalPurpose \
    --throughput-mode bursting \
    --encrypted \
    --tags Key=Name,Value="EFS-Lab-FS" Key=Project,Value=$PROJECT_TAG \
    --query 'FileSystemId' --output text)

echo "EFS ID: $EFS_ID"

export EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
echo "EFS DNS: $EFS_DNS"

# ─── Lifecycle Policy ───
aws efs put-lifecycle-configuration \
    --file-system-id $EFS_ID \
    --lifecycle-policies TransitionToIA=AFTER_30_DAYS \
                        TransitionToPrimaryStorageClass=AFTER_1_ACCESS
echo "Lifecycle policy set "

# ─── Mount Targets ───
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

echo "Waiting 30 seconds for mount targets..."
sleep 30

aws efs describe-mount-targets \
    --file-system-id $EFS_ID \
    --query 'MountTargets[*].{ID:MountTargetId,AZ:AvailabilityZoneName,State:LifeCycleState,VPC:VpcId}' \
    --output table

echo ""
echo "=== Setup Complete ==="
echo "EFS_ID=$EFS_ID"
echo "EFS_DNS=$EFS_DNS"
echo "EFS_SG_ID=$EFS_SG_ID"
echo ""
echo "Copy EFS_DNS to your EC2 instances and run mount-instance.sh"

