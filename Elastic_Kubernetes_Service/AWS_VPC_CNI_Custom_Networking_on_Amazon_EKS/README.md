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

Project Structure

        AWS_VPC_CNI_Custom_Networking_on_Amazon_EKS/
        │
        ├── cluster.yaml           # eksctl ClusterConfig (custom VPC)
        ├── eniconfig-az1.yaml     # ENIConfig for us-east-1a (pod subnet)
        ├── eniconfig-az2.yaml     # ENIConfig for us-east-1b (pod subnet)
        │
        └── README.md              # Project documentation


Prerequisites

Requirement                     Detail
AWS Account                     EKS, EC2, VPC, IAM permissions
AWS CLI                         Installed and configured
kubectl                         Installed
eksctl                          For EKS cluster management


Architecture

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


