# CIS Kubernetes Benchmark Scanning on Amazon EKS

    Overview
    This project is a hands-on project that runs kube-bench on Amazon EKS to audit Kubernetes node configurations against the CIS Kubernetes Benchmark. 
    It covers two deployment methods: quick scanning via the official Docker Hub image, and the recommended ECR-based method 
    where you build and host the image in your own registry.
    Key highlights:
    
    EKS cluster created via eksctl with a ClusterConfig YAML
    Method 1: job-eks.yaml applied directly using the official public.ecr.aws image
    Method 2: kube-bench image built locally with required --build-arg flags, pushed to private ECR, and job-eks.yaml patched with sed
    Results analyzed for FAIL checks with remediation steps
    sed substitution pattern explained — reusable in any CI/CD pipeline

Project Structure

    KubeBench/
    │
    ├── cluster.yaml           # eksctl ClusterConfig for EKS
    ├── job-eks.yaml           # Method 1: official Docker Hub image
    ├── job-eks-ecr.yaml       # Method 2: patched with private ECR image
    │
    └── README.md              # Project documentation

Prerequisites

    Requirement                     Detail
    
    AWS Account                     EKS, EC2, VPC, IAM permissions
    AWS CLI                         Installed and configured
    kubectl                         Installed
    eksctl                          For EKS cluster management
    Docker                          Installed (for Method 2)
    Git                             Installed (for Method 2 clone)


