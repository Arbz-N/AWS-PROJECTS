# EKS CI/CD Pipeline with CodeBuild + CodePipeline


## Overview:

    PipelineKube is a production-style CI/CD pipeline that automatically builds, pushes, 
    and deploys a containerized application to Amazon EKS on every GitHub push. 
    It uses AWS CodePipeline for orchestration and AWS CodeBuild for building Docker images and deploying to Kubernetes.
    
    Key highlights:

    GitHub push triggers CodePipeline automatically via webhook
    CodeBuild builds Docker image and pushes to Amazon ECR
    Image tagged with Git commit hash for full traceability and rollback
    kubectl apply deploys updated image to EKS cluster
    IAM Roles with least-privilege access for CodeBuild and CodePipeline
    aws-auth ConfigMap updated to grant pipeline roles EKS access

## Project Structure:

    eks-cicd-lab/
    │
    ├── app/
    │   └── index.html                # Sample web application
    │
    ├── k8s/
    │   ├── deployment.yaml           # Nginx Deployment (CONTAINER_IMAGE placeholder)
    │   └── service.yaml              # LoadBalancer Service
    │
    ├── Dockerfile                    # Uses public.ecr.aws (no Docker Hub rate limit)
    ├── buildspec.yml                 # CodeBuild instructions (install → build → deploy)
    └── README.md                     # Project documentation

##  Prerequisites:

    Requirement                            Detail
    
    AWS Account                    EKS, EC2, IAM permissions required
    AWS CLI                        Installed and configured
    kubectl                        Installed on local machine
    eksctl                         For EKS cluster management
    GitHub Account                 For source repository

## Architecture:

                        Developer
                         │
                         │  git push
                         ▼
                      GitHub Repository
                      (eks-cicd-lab)
                         │
                         │  Webhook trigger
                         ▼
                      ┌──────────────────────────────────────────┐
                      │           AWS CodePipeline               │
                      │                                          │
                      │  ┌─────────┐  ┌──────────┐               │
                      │  │ Source  │─►│  Build   │               │
                      │  │ GitHub  │  │CodeBuild │               │
                      │  └─────────┘  └────┬─────┘               │
                      └───────────────────┼──────────────────────┘
                                          │
                             ┌────────────┴────────────┐
                             │                         │
                             ▼                         ▼
                      ┌──────────────┐        ┌──────────────────┐
                      │ Amazon ECR   │        │   Amazon EKS     │
                      │              │        │                  │
                      │ image:latest │        │  ┌────────────┐  │
                      │ image:abc123 │        │  │ cicd-app   │  │
                      └──────────────┘        │  │  Pod-1     │  │
                                              │  │  Pod-2     │  │
                                              │  └────────────┘  │
                                              │  LoadBalancer    │
                                              │  Service         │
                                              └──────────────────┘

### Task 1 — GitHub Repository + Application Code:
    
    Step 1.1 — Create EKS Cluster 

        eksctl create cluster \
      --name=cicd-lab-cluster \
      --version=1.34 \
      --region=us-east-1 \
      --node-type=t3.medium \
      --nodes=2 \
      --managed
    
    aws eks --region us-east-1 update-kubeconfig --name cicd-lab-cluster
    kubectl get nodes


    Step 1.2 — Clone the GitHub Repository 
    
    git clone https://github.com/<your-username>/eks-cicd-lab.git
    cd eks-cicd-lab

    Step 1.3 — Push the Code 

    git add .
    git commit -m "Initial commit: Add app, Dockerfile, k8s manifests, buildspec"
    git push origin main

### Task 2 — AWS Setup — ECR + IAM Roles:
    
        Step 2.1 — Create ECR Repository 

        aws ecr create-repository \
      --repository-name cicd-lab-app \
      --region us-east-1
    # Note the URI: <account-id>.dkr.ecr.us-east-1.amazonaws.com/cicd-lab-app

    Step 2.2 — Create CodeBuild IAM Role 

    # Trust policy
    cat > codebuild-trust-policy.json << 'EOF'
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "codebuild.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }]
    }
    EOF
    
    aws iam create-role \
      --role-name eks-codebuild-role \
      --assume-role-policy-document file://codebuild-trust-policy.json
    
    # Policies attach karo
    aws iam attach-role-policy \
      --role-name eks-codebuild-role \
      --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess
    
    aws iam attach-role-policy \
      --role-name eks-codebuild-role \
      --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
    
    aws iam attach-role-policy \
      --role-name eks-codebuild-role \
      --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess
    
    # EKS DescribeCluster permission (Necassary to update-kubeconfig )
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    cat > eks-access-policy.json << 'EOF'
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": ["eks:DescribeCluster", "eks:ListClusters"],
        "Resource": "*"
      }]
    }
    EOF
    
    aws iam create-policy \
      --policy-name eks-codebuild-access \
      --policy-document file://eks-access-policy.json
    
    aws iam attach-role-policy \
      --role-name eks-codebuild-role \
      --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/eks-codebuild-access

    Step 2.3 — Create CodePipeline IAM Role 

    cat > codepipeline-trust-policy.json << 'EOF'
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "codepipeline.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }]
    }
    EOF
    
    aws iam create-role \
      --role-name eks-codepipeline-role \
      --assume-role-policy-document file://codepipeline-trust-policy.json
    
    aws iam attach-role-policy \
      --role-name eks-codepipeline-role \
      --policy-arn arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess
    
    aws iam attach-role-policy \
      --role-name eks-codepipeline-role \
      --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess
    
    # S3 access — take the code from GitHub and save it into S3 
    cat > codepipeline-s3-policy.json << 'EOF'
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:PutObject","s3:GetObject","s3:GetObjectVersion",
                   "s3:GetBucketAcl","s3:GetBucketLocation","s3:ListBucket"],
        "Resource": ["arn:aws:s3:::codepipeline-us-east-1-*",
                     "arn:aws:s3:::codepipeline-us-east-1-*/*"]
      }]
    }
    EOF
    
    aws iam create-policy \
      --policy-name codepipeline-s3-access \
      --policy-document file://codepipeline-s3-policy.json
    
    aws iam attach-role-policy \
      --role-name eks-codepipeline-role \
      --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/codepipeline-s3-access

    
### Task 3 — EKS aws-auth ConfigMap Update:

    kubectl edit -n kube-system configmap/aws-auth

    # only add these (Don't delete the other role from the file)

    Entry 2: CodeBuild role — 
    - rolearn: arn:aws:iam::<ACCOUNT_ID>:role/eks-codebuild-role
      username: codebuild
      groups:
        - system:masters
    # Entry 3: CodePipeline role —
    - rolearn: arn:aws:iam::<ACCOUNT_ID>:role/eks-codepipeline-role
      username: codepipeline
      groups:
        - system:masters

    # Verify them?
    kubectl describe configmap aws-auth -n kube-system | grep rolearn

### Task 4 — CodeBuild + CodePipeline Setup (AWS Console):

    CodeBuild Project
    
    AWS Console → CodeBuild → Create build project
    Project name: eks-cicd-build
    Source: GitHub → Connection: github-eks-cicd → Repo: eks-cicd-lab → Branch: main
    Environment: aws/codebuild/standard:7.0 → Privileged:  Enable (For Docker build )
    Service role: eks-codebuild-role
    Buildspec: Use buildspec file
    
    CodePipeline
    
    AWS Console → CodePipeline → Create pipeline
    Pipeline name: eks-cicd-pipeline → Service role: eks-codepipeline-role
    Stage 1 — Source: GitHub (Version 2) → Connection → Repo → Branch: main → Automatic webhook
    Stage 2 — Build: AWS CodeBuild → eks-cicd-build
    Stage 3 — Deploy: Skip (CodeBuild has already kubectl apply)

### Task 5 — Verify + End-to-End Test:
 
    # Pods check karo
    kubectl get pods
    kubectl get svc cicd-app-service
    
    # App URL lo
    EXTERNAL_IP=$(kubectl get svc cicd-app-service \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    curl http://$EXTERNAL_IP
    # Expected: Version: 1.0

    End-to-End CI/CD Test
    
    #update the Version  
    cat > app/index.html << 'EOF'
    <!DOCTYPE html>
    <html>
    <head><title>EKS CI/CD Lab</title></head>
    <body>
      <h1>Hello from EKS CI/CD Pipeline!</h1>
      <p>Version: 2.0 - Auto Deployed! </p>
    </body>
    </html>
    EOF
    
    git add app/index.html
    git commit -m "Update version to 2.0"
    git push origin main

    Automatic flow after Push 

    git push → CodePipeline trigger → CodeBuild →
    Docker image build → ECR push → kubectl apply →
    EKS rolling update → curl → "Version: 2.0" 

### Cleanup:

    kubectl delete deployment cicd-app
    kubectl delete svc cicd-app-service
    
    aws ecr delete-repository \
      --repository-name cicd-lab-app \
      --region us-east-1 \
      --force
    
    aws iam delete-role --role-name eks-codebuild-role
    aws iam delete-role --role-name eks-codepipeline-role
    aws codebuild delete-project --name eks-cicd-build
    
    eksctl delete cluster --name cicd-lab-cluster --region us-east-1

### License:

    This project is licensed under the MIT License.