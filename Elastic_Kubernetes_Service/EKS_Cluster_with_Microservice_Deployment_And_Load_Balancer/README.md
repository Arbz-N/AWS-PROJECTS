# EKS Cluster with Microservice Deployment With Load Balancer

## Overview

    This project is a hands-on project that demonstrates how to provision an Amazon EKS (Elastic Kubernetes Service) cluster,
    configure kubectl for remote access, and deploy a sample Nginx microservice exposed via an internet-facing AWS Load Balancer.
    
    Key highlights:
    EKS cluster provisioned via AWS Management Console
    kubectl configured locally using aws eks update-kubeconfig
    Subnet tagging for AWS Load Balancer Controller compatibility
    Nginx microservice deployed with 2 replicas
    Internet-facing Load Balancer using Kubernetes Service annotations

## Project Structure

    EKS_Cluster_with_Microservice_Deployment_And_Load_Balancer/
    │
    ├── k8s/
    │   ├── deployment.yaml       # Nginx Deployment (2 replicas)
    │   └── service.yaml          # LoadBalancer Service (internet-facing)
    │
    └── README.md                 # Project documentation

## Architecture Diagram
        
        ┌──────────────────────────────────────────────────────────────┐
        │                       AWS Account                            │
        │                                                              │
        │  ┌────────────────────────────────────────────────────────┐  │
        │  │                        VPC                             │  │
        │  │                                                        │  │
        │  │   ┌──────────────────┐   ┌──────────────────────────┐  │  │
        │  │   │  Subnet - AZ 1   │   │      Subnet - AZ 2       │  │  │
        │  │   │  (elb tag)       │   │      (elb tag)           │  │  │
        │  │   └────────┬─────────┘   └────────────┬─────────────┘  │  │
        │  │            │                          │                │  │
        │  │            └────────────┬─────────────┘                │  │
        │  │                         │                              │  │
        │  │              ┌──────────▼──────────┐                   │  │
        │  │              │   AWS Load Balance  │                   │  │
        │  │              │  (internet-facing)  │                   │  │
        │  │              └──────────┬──────────┘                   │  │
        │  │                         │                              │  │
        │  │              ┌──────────▼──────────┐                   │  │
        │  │              │    EKS Cluster      │                   │  │
        │  │              │  (MyEKScluster)     │                   │  │
        │  │              │                     │                   │  │
        │  │              │  ┌───────────────┐  │                   │  │
        │  │              │  │  Deployment   │  │                   │  │
        │  │              │  │               │  │                   │  │
        │  │              │  │ ┌───────────┐ │  │                   │  │
        │  │              │  │ │  Pod 1    │ │  │                   │  │
        │  │              │  │ │  (nginx)  │ │  │                   │  │
        │  │              │  │ └───────────┘ │  │                   │  │
        │  │              │  │ ┌───────────┐ │  │                   │  │
        │  │              │  │ │  Pod 2    │ │  │                   │  │
        │  │              │  │ │  (nginx)  │ │  │                   │  │
        │  │              │  │ └───────────┘ │  │                   │  │
        │  │              │  └───────────────┘  │                   │  │
        │  │              └─────────────────────┘                   │  │
        │  └────────────────────────────────────────────────────────┘  │
        └──────────────────────────────────────────────────────────────┘
        
        ────────────────── Traffic Flow ──────────────────
        
          User
           │
           │  HTTP (port 80)
           ▼
          AWS Load Balancer (internet-facing)
           │
           ├──► Pod 1 (nginx) — AZ 1
           │
           └──► Pod 2 (nginx) — AZ 2
        
        ────────────────── Auth Flow ──────────────────
        
          aws-iam-authenticator
           │
           └──► IAM Role ──► EKS Cluster ──► kubectl

## Prerequisites

Requirement                        Detail
AWS Account                   Active with sufficient permissions
AWS CLI                       Installed and configured
kubectl                       Installed on local machine
aws-iam-authenticator         For IAM-based EKS authentication
EKS IAM Role                  With necessary EKS permissions
VPC + Subnets                 At least 2 subnets in different Availability Zones

## Deployment Steps

Step 1 — Create EKS Cluster (AWS Console)

  - Open AWS Management Console → Navigate to Amazon EKS
  - Click "Create cluster"
  - Fill in the details:
      Cluster name: MyEKScluster
      Kubernetes version: Latest stable
      Role: Select or create an IAM role with EKS permissions
      VPC: Select your VPC
      Subnets: Choose at least 2 subnets in different Availability Zones

  - Click "Create"

Step 2 — Install Required Tools

    # Update packages and install kubectl
    sudo apt-get update && sudo apt-get install -y kubectl
    
    # Install AWS CLI
    # https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
    
    # Install aws-iam-authenticator (used for IAM-based EKS auth)
    # https://weaveworks-gitops.awsworkshop.io/60_workshop_6_ml/00_prerequisites.md/50_install_aws_iam_auth.html

Step 3 — Configure kubectl for EKS
    
    # Update local kubeconfig with EKS cluster details
    aws eks update-kubeconfig --region us-east-1 --name MyEKScluster
    
    # Verify nodes are accessible
    kubectl get nodes

    ⚠️ Make sure the EKS Security Group has an inbound rule allowing HTTPS (443) from your EC2 instance's Security Group.

Step 4 — Tag Subnets for Load Balancer

    # Tag subnets for public Load Balancer discovery
    aws ec2 create-tags \
      --resources subnet-xxxxxxxx subnet-yyyyyyyy \
      --tags Key=kubernetes.io/role/elb,Value=1
    
    # Tag subnets for EKS cluster association
    aws ec2 create-tags \
      --resources subnet-xxxxxxxx subnet-yyyyyyyy \
      --tags Key=kubernetes.io/cluster/MyEKScluster,Value=shared
    
        shared = multiple clusters can use the subnet
        owned = only one cluster can use the subnet

Step 5 — Deploy Nginx Microservice

    # Apply Deployment
    kubectl apply -f k8s/deployment.yaml
    
    # Apply Service
    kubectl apply -f k8s/service.yaml
    
    # Check service and get Load Balancer DNS
    kubectl get svc nginx-deployment


Step 6 — Test the Deployment

    # Curl the Load Balancer DNS
    curl http://xxxx.us-east-1.elb.amazonaws.com
    # Expected: <h1>Welcome to nginx!</h1>
    
    # Verify Load Balancer is active via AWS CLI
    aws elbv2 describe-load-balancers \
      --query 'LoadBalancers[*].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'

Important Note — Load Balancer Annotation

    By default, AWS creates a private Load Balancer. To force a public internet-facing Load Balancer, the following annotation is required in service.yaml:
    yamlannotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    This tells AWS to automatically provision a public Load Balancer and look for subnets tagged with the elb tag.

Cleanup

    # Delete Kubernetes resources
    kubectl delete -f k8s/service.yaml
    kubectl delete -f k8s/deployment.yaml
    
    # Delete EKS cluster from AWS Console or CLI
    aws eks delete-cluster --name MyEKScluster

Security Notes

    Never expose EKS API server publicly without IP restrictions
    Use IAM roles and aws-iam-authenticator instead of static credentials
    Restrict EKS Security Group to only allow necessary inbound traffic