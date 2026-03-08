# AWS VPC CNI Custom Networking on Amazon EKS

    This project is a hands-on project that demonstrates AWS VPC CNI Custom Networking on Amazon EKS.
    By default, EKS pods receive IPs from the same subnet as their nodes. 
    This project configures a secondary VPC CIDR (100.64.0.0/16) dedicated to pods — completely separate from the node subnet (10.0.0.0/16) — using ENIConfig resources to map each Availability Zone to its own pod subnet.

    Key highlights:

    Custom VPC with primary CIDR (10.0.0.0/16) for nodes and secondary CIDR (100.64.0.0/16) for pods
    ENIConfig CRDs created per Availability Zone for automatic pod subnet selection
    AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true enables the custom networking mode
    ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone auto-selects ENIConfig by AZ label
    Nodes recycled so new instances pick up the custom networking configuration
    Full validation: pods receive 100.64.x.x IPs while nodes stay in 10.0.x.x

## Project Structure

        AWS_VPC_CNI_Custom_Networking_on_Amazon_EKS/
        │
        ├── cluster.yaml           # eksctl ClusterConfig (custom VPC)
        ├── eniconfig-az1.yaml     # ENIConfig for us-east-1a (pod subnet)
        ├── eniconfig-az2.yaml     # ENIConfig for us-east-1b (pod subnet)
        │
        └── README.md              # Project documentation


## Prerequisites

Requirement                     Detail
AWS Account                     EKS, EC2, VPC, IAM permissions
AWS CLI                         Installed and configured
kubectl                         Installed
eksctl                          For EKS cluster management


## Architecture

            VPC: 10.0.0.0/16 (nodes)  +  100.64.0.0/16 (pods)
              ┌─────────────────────────────────────────────────────────┐
              │                                                         │
              │   us-east-1a                    us-east-1b              │
              │   ┌───────────────────┐         ┌───────────────────┐   │
              │   │ Node Subnet       │         │ Node Subnet       │   │
              │   │ 10.0.1.0/24       │         │ 10.0.2.0/24       │   │
              │   │ ┌─────────────┐   │         │ ┌─────────────┐   │   │
              │   │ │ EC2 Node    │   │         │ │ EC2 Node    │   │   │
              │   │ │ 10.0.1.x    │   │         │ │ 10.0.2.x    │   │   │
              │   │ └─────────────┘   │         │ └─────────────┘   │   │
              │   └───────────────────┘         └───────────────────┘   │
              │                                                         │
              │   ┌───────────────────┐         ┌───────────────────┐   │
              │   │ Pod Subnet        │         │ Pod Subnet        │   │
              │   │ 100.64.1.0/24     │         │ 100.64.2.0/24     │   │
              │   │ ┌───────────────┐ │         │ ┌───────────────┐ │   │
              │   │ │ Pod IP        │ │         │ │ Pod IP        │ │   │
              │   │ │ 100.64.1.x    │ │         │ │ 100.64.2.x    │ │   │
              │   │ └───────────────┘ │         │ └───────────────┘ │   │
              │   │ ENIConfig: 1a     │         │ ENIConfig: 1b     │   │
              │   └───────────────────┘         └───────────────────┘   │
              │                                                         │
              │   Internet Gateway → Route Table → All subnets          │
              └─────────────────────────────────────────────────────────┘

# Setup — Variables

    export AWS_REGION=us-east-1
    export CLUSTER_NAME=cni-lab
    export ACCOUNT_ID=$(aws sts get-caller-identity \
      --query Account --output text)
    
    export AZ1=us-east-1a
    export AZ2=us-east-1b
    
    echo "Account: $ACCOUNT_ID"
    echo "Region:  $AWS_REGION"

## Task 1 — Custom VPC Setup

    Step 1.1 — Create VPC

    
    VPC_ID=$(aws ec2 create-vpc \
      --cidr-block 10.0.0.0/16 \
      --region $AWS_REGION \
      --query 'Vpc.VpcId' \
      --output text)
    
    aws ec2 create-tags \
      --resources $VPC_ID \
      --tags Key=Name,Value=cni-lab-vpc
    
    aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
    aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames


    Step 1.2 — Add Secondary CIDR for 


    aws ec2 associate-vpc-cidr-block \
      --vpc-id $VPC_ID \
      --cidr-block 100.64.0.0/16
    
    aws ec2 describe-vpcs \
      --vpc-ids $VPC_ID \
      --query 'Vpcs[0].CidrBlockAssociationSet[*].CidrBlock'
    # ["10.0.0.0/16", "100.64.0.0/16"]


    Step 1.3 — Create Subnets


    # Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
      --query 'InternetGateway.InternetGatewayId' \
      --output text)
    aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
    
    # Node Subnets (primary CIDR)
    NODE_SUBNET_1=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 \
      --availability-zone $AZ1 \
      --query 'Subnet.SubnetId' --output text)
    
    NODE_SUBNET_2=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 \
      --availability-zone $AZ2 \
      --query 'Subnet.SubnetId' --output text)
    
    # Pod Subnets (secondary CIDR)
    POD_SUBNET_1=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID --cidr-block 100.64.1.0/24 \
      --availability-zone $AZ1 \
      --query 'Subnet.SubnetId' --output text)
    
    POD_SUBNET_2=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID --cidr-block 100.64.2.0/24 \
      --availability-zone $AZ2 \
      --query 'Subnet.SubnetId' --output text)
    
    echo "Node Subnets: $NODE_SUBNET_1 $NODE_SUBNET_2"
    echo "Pod  Subnets: $POD_SUBNET_1  $POD_SUBNET_2"


    Step 1.4 — Configure Route Table

    
    RTB_ID=$(aws ec2 describe-route-tables \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'RouteTables[0].RouteTableId' \
      --output text)
    
    aws ec2 create-route \
      --route-table-id $RTB_ID \
      --destination-cidr-block 0.0.0.0/0 \
      --gateway-id $IGW_ID
    
    for SUBNET in $NODE_SUBNET_1 $NODE_SUBNET_2 $POD_SUBNET_1 $POD_SUBNET_2; do
      aws ec2 associate-route-table \
        --route-table-id $RTB_ID \
        --subnet-id $SUBNET
    done
    

    Step 1.5 — Enable Public IP on Node Subnets
    This is required. Without it, the managed node group will fail with CREATE_FAILED.

    
    aws ec2 modify-subnet-attribute \
      --subnet-id $NODE_SUBNET_1 --map-public-ip-on-launch
    
    aws ec2 modify-subnet-attribute \
      --subnet-id $NODE_SUBNET_2 --map-public-ip-on-launch


    Step 1.6 — Create EKS Cluster


    eksctl create cluster -f cluster.yaml    

    aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

    kubectl get nodes -o wide
    # ip-10-0-x-x   Ready 


## Task 2 — Configure AWS CNI Custom Networking

    Step 2.1 — Enable Custom Networking


    kubectl set env daemonset aws-node \
      -n kube-system \
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
    # daemonset.apps/aws-node env updated 

    
    Step 2.2 — Get EKS Cluster Security Group

    
    EKS_SG=$(aws eks describe-cluster \
      --name $CLUSTER_NAME \
      --region $AWS_REGION \
      --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
      --output text)


    Step 2.3 — Create ENIConfig per AZ


    kubectl apply -f eniconfig-az1.yaml
    kubectl apply -f eniconfig-az2.yaml
    
    kubectl get ENIConfigs
    # NAME          AGE
    # us-east-1a    
    # us-east-1b    


    Step 2.4 — Enable AZ Auto-Selection


    kubectl set env daemonset aws-node \
      -n kube-system \
      ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
    # daemonset.apps/aws-node env updated ✅
    
    # Verify both settings
    kubectl set env daemonset/aws-node -n kube-system --list \
      | grep -E "CUSTOM|ENI_CONFIG"
    # AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true          
    # ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone 


    Step 2.5 — Recycle Nodes
    Custom networking only applies to NEW nodes. Existing nodes must be replaced.

    
    # Delete PDBs temporarily (they block drain)
    kubectl delete pdb coredns -n kube-system
    kubectl delete pdb metrics-server -n kube-system
    
    # Drain all nodes
    kubectl get nodes -o name | while read node; do
      kubectl drain $node \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force
    done
    
    # Terminate existing EC2 instances
    INSTANCE_IDS=$(aws ec2 describe-instances \
      --filters \
        "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
        "Name=instance-state-name,Values=running" \
      --query 'Reservations[*].Instances[*].InstanceId' \
      --output text)
    
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
    
    # Auto Scaling Group provisions new nodes (2-3 min)
    kubectl get nodes -w
    # New nodes Ready 

## Task 3 — Validate
    
    # Deploy test pod
    kubectl run test-pod --image=nginx --restart=Never
    
    # Check pod IP — must be in 100.64.x.x range
    kubectl get pod test-pod -o wide
    # NAME       IP              NODE
    # test-pod   100.64.1.xxx    ip-10-0-1-xxx 
    
    # Deploy 4 replicas across both AZs
    kubectl create deployment nginx-test --image=nginx --replicas=4
    
    kubectl get pods -o wide
    # nginx-test-xxx   100.64.1.10   ip-10-0-1-xxx 
    # nginx-test-xxx   100.64.1.11   ip-10-0-1-xxx 
    # nginx-test-xxx   100.64.2.10   ip-10-0-2-xxx 
    # nginx-test-xxx   100.64.2.11   ip-10-0-2-xxx 
    # All pods in 100.64.x.x   Nodes in 10.0.x.x 


## Cleanup

    kubectl delete deployment nginx-test
    kubectl delete pod test-pod
    
    kubectl delete -f eniconfig-az1.yaml
    kubectl delete -f eniconfig-az2.yaml
    
    eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
    
    aws ec2 detach-internet-gateway \
      --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
    
    for SUBNET in $NODE_SUBNET_1 $NODE_SUBNET_2 $POD_SUBNET_1 $POD_SUBNET_2; do
      aws ec2 delete-subnet --subnet-id $SUBNET
    done
    
    aws ec2 delete-vpc --vpc-id $VPC_ID
    
    rm -f cluster.yaml eniconfig-az1.yaml eniconfig-az2.yaml
