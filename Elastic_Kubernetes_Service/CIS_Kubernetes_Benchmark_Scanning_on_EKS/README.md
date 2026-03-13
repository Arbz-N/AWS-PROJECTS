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

Architecture

        EKS Cluster (kube-bench-lab)
          ┌────────────────────────────────────────────────────┐
          │                                                    │
          │  kube-bench Job (Kubernetes Job)                   │
          │  ┌──────────────────────────────────────────────┐  │
          │  │  Pod: kube-bench-xxxxx                       │  │
          │  │                                              │  │
          │  │  hostPID: true      ← process namespace      │  │
          │  │  hostPath volumes   ← /etc/kubernetes, /var  │  │
          │  │                                              │  │
          │  │  Runs CIS checks against:                    │  │
          │  │  → Kubelet configuration                     │  │
          │  │  → API server flags                          │  │
          │  │  → Node file permissions                     │  │
          │  └──────────────────────────────────────────────┘  │
          │            │                                       │
          │            ▼                                       │
          │  kubectl logs → Report                             │
          │  ┌──────────────────────────────────┐              │
          │  │  PASS: 15   FAIL: 3   WARN: 2    │              │
          │  └──────────────────────────────────┘              │
          │                                                    │
          │  Node 1 (t3.medium)   Node 2 (t3.medium)           │
          └────────────────────────────────────────────────────┘
        
          Method 1: public.ecr.aws/aquasecurity/kube-bench:latest
          Method 2: <ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/k8s/kube-bench:latest

Setup — Variables

    export AWS_REGION=us-east-1
    export ACCOUNT_ID=$(aws sts get-caller-identity \
      --query Account --output text)
    export CLUSTER_NAME=kube-bench-lab
    
    echo "Account: $ACCOUNT_ID"
    echo "Region : $AWS_REGION"

Task 1 — Create EKS Cluster

    eksctl create cluster -f cluster.yaml
    
    aws eks update-kubeconfig \
      --name $CLUSTER_NAME \
      --region $AWS_REGION
    
    kubectl get nodes
    # ip-10-0-x-x   Ready 
    # ip-10-0-x-x   Ready 

Task 2 — Method 1: Quick Scan (Official Docker Hub Image)

    Step 2.1 — Download Official EKS Job File
    

    # Use job-eks.yaml for EKS — NOT job.yaml (generic K8s)
    curl -Lo job-eks.yaml \
      https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-eks.yaml
    
    cat job-eks.yaml


    Step 2.2 — Run the Job


    kubectl apply -f job-eks.yaml
    # job.batch/kube-bench created 
    
    kubectl get pods
    # kube-bench-xxxxx   0/1   ContainerCreating → Completed 
    
    sleep 15
    kubectl get pods
    # kube-bench-xxxxx   0/1   Completed 


    Step 2.3 — View Results


    BENCH_POD=$(kubectl get pods \
      -l app=kube-bench \
      -o jsonpath='{.items[0].metadata.name}')
    
    kubectl logs $BENCH_POD
    
    kubectl logs $BENCH_POD > kube-bench-report.txt
    echo "Report saved "

Task 3 — Method 2: ECR (Official EKS Recommended Method)






