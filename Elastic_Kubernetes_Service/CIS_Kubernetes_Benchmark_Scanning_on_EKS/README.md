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

## Project Structure:

    KubeBench/
    │
    ├── cluster.yaml           # eksctl ClusterConfig for EKS
    ├── job-eks.yaml           # Method 1: official Docker Hub image
    ├── job-eks-ecr.yaml       # Method 2: patched with private ECR image
    │
    └── README.md              # Project documentation

## Prerequisites:

    Requirement                     Detail
    
    AWS Account                     EKS, EC2, VPC, IAM permissions
    AWS CLI                         Installed and configured
    kubectl                         Installed
    eksctl                          For EKS cluster management
    Docker                          Installed (for Method 2)
    Git                             Installed (for Method 2 clone)

## Architecture:

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

## Setup — Variables:

    export AWS_REGION=us-east-1
    export ACCOUNT_ID=$(aws sts get-caller-identity \
      --query Account --output text)
    export CLUSTER_NAME=kube-bench-lab
    
    echo "Account: $ACCOUNT_ID"
    echo "Region : $AWS_REGION"

## Task 1 — Create EKS Cluster:

    eksctl create cluster -f cluster.yaml
    
    aws eks update-kubeconfig \
      --name $CLUSTER_NAME \
      --region $AWS_REGION
    
    kubectl get nodes
    # ip-10-0-x-x   Ready 
    # ip-10-0-x-x   Ready 

## Task 2 — Method 1: Quick Scan (Official Docker Hub Image):

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

## Task 3 — Method 2: ECR (Official EKS Recommended Method):

    Step 3.1 — Create ECR Repository


    aws ecr create-repository \
      --repository-name k8s/kube-bench \
      --image-tag-mutability MUTABLE \
      --region $AWS_REGION
    
    export ECR_URI=$(aws ecr describe-repositories \
      --repository-names k8s/kube-bench \
      --region $AWS_REGION \
      --query 'repositories[0].repositoryUri' \
      --output text)

    echo "ECR URI: $ECR_URI"


    Step 3.2 — Clone kube-bench Repository


    git clone https://github.com/aquasecurity/kube-bench.git
    cd kube-bench
    
    The cloned repo contains:
    
    Dockerfile — for building the image
    job-eks.yaml — EKS-specific job (use this, not job.yaml)
    cfg/eks-1.5.0/ — EKS CIS benchmark check definitions
    cfg/cis-1.8/ — Generic Kubernetes checks


    Step 3.3 — Build and Push Image


    bash# ECR login
    aws ecr get-login-password --region $AWS_REGION | \
      docker login --username AWS \
      --password-stdin \
      $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    
    # Build — build args are REQUIRED
    # Without them: kubectl download URL is empty → 404 error
    docker build \
      --build-arg KUBECTL_VERSION=1.27.0 \
      --build-arg TARGETARCH=amd64 \
      -t k8s/kube-bench .
    
    # Tag and push
    docker tag k8s/kube-bench:latest $ECR_URI:latest
    docker push $ECR_URI:latest
    
    echo "Image pushed: $ECR_URI:latest "
    cd ..


    Step 3.4 — Patch job-eks.yaml with ECR Image
    
    
    curl -Lo job-eks-ecr.yaml \
      https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-eks.yaml
    
    # Replace official image with your ECR image
    sed -i "s|image: .*|image: $ECR_URI:latest|g" job-eks-ecr.yaml
    
    # Verify
    grep "image:" job-eks-ecr.yaml
    # image: 123456789.dkr.ecr.us-east-1.amazonaws.com/k8s/kube-bench:latest 

    kubectl apply -f deployment.yaml


    Step 3.5 — Run ECR Job


    kubectl delete job kube-bench 2>/dev/null
    
    kubectl apply -f job-eks-ecr.yaml
    # job.batch/kube-bench created 
    
    sleep 20
    
    BENCH_POD=$(kubectl get pods \
      -l app=kube-bench \
      -o jsonpath='{.items[0].metadata.name}')
    
    kubectl logs $BENCH_POD > kube-bench-ecr-report.txt
    echo "Report saved "

## Task 4 — Analyze Results:

    Summary
    kubectl logs $BENCH_POD | grep -E "^== Summary|checks PASS|checks FAIL|checks WARN"
    
    # == Summary node ==
    # 15 checks PASS
    # 3 checks FAIL
    # 2 checks WARN
    # 0 checks INFO
    

## Cleanup:
    
    kubectl delete job kube-bench 2>/dev/null
    
    aws ecr delete-repository \
      --repository-name k8s/kube-bench \
      --region $AWS_REGION \
      --force 2>/dev/null
    
    eksctl delete cluster \
      --name $CLUSTER_NAME \
      --region $AWS_REGION
    
    rm -f job-eks.yaml job-eks-ecr.yaml kube-bench-report.txt \
          kube-bench-ecr-report.txt cluster.yaml
    rm -rf kube-bench/


License

    This project is licensed under the MIT License.
