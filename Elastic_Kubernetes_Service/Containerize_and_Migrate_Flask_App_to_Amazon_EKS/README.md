# Containerize & Migrate Flask App to Amazon EKS

    Overview
    This project is a hands-on project that demonstrates the full journey of containerizing a Python Flask application and migrating 
    from a local Kubernetes cluster (Kind) to Amazon EKS. It covers Docker image building,
    local testing, ECR image publishing, and production deployment with an AWS Load Balancer. proxy.

        Key highlights:
        Flask app containerized with Python 3.8-slim Docker image
        Local testing with Docker and Kind cluster
        Image pushed to Amazon ECR (private registry)
        Deployed on EKS with spot instances for cost efficiency
        AWS Load Balancer provisioned automatically via Kubernetes Service
        Full migration workflow: local → ECR → EKS

## Project Structure

        Containerize_and_Migrate_Flask_App_to_Amazon_EKS/
            │
            ├── flask-app/
            │   ├── app.py                  # Flask application (Hello World)
            │   ├── requirements.txt        # Python dependencies
            │   ├── Dockerfile              # Container build instructions
            │   ├── deployment.yaml         # Local Kind deployment (NodePort)
            │   └── deployment-eks.yaml     # EKS deployment (LoadBalancer + ECR image)
            │
            └── README.md                   # Project documentation



## Prerequisites

    Requirement                     Detail
    AWS Account                     EKS, EC2, VPC, IAM permissions
    AWS CLI                         Installed and configured
    kubectl                         Installed
    eksctl                          For EKS cluster management
    Docker                          Installed locally
    Kind                            For local Kubernetes testing

## Architecture

        Local Development
          ┌──────────────────────────────────────────────────┐
          │  Flask App (app.py)                              │
          │       │                                          │
          │       ▼                                          │
          │  Docker Image (my-flask-app:latest)              │
          │       │                                          │
          │       ▼                                          │
          │  Kind Cluster                                    │
          │  ├── Pod-1 (flask-app)                           │
          │  ├── Pod-2 (flask-app)                           │
          │  └── Service (NodePort :80)                      │
          └──────────────────────────────────────────────────┘
                             │
                             │  docker tag + push
                             ▼
          Amazon ECR
          (my-flask-app:latest)
                             │
                             │  kubectl apply
                             ▼
          Amazon EKS (Production)
          ┌──────────────────────────────────────────────────┐
          │  ├── Pod-1 (flask-app) ← ECR image               │
          │  ├── Pod-2 (flask-app) ← ECR image               │
          │  └── Service (LoadBalancer)                      │
          │            │                                     │
          │            ▼                                     │
          │       AWS ELB (public URL)                       │
          │            │                                     │
          │            ▼                                     │
          │       curl → Hello, World!                       │
          └──────────────────────────────────────────────────┘


## Setup — Variables

    export AWS_REGION=us-east-2
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export APP_NAME=my-flask-app
    export CLUSTER_NAME=eks-migration-lab

    echo "Account: $ACCOUNT_ID"
    echo "Region:  $AWS_REGION"

## Task 1 — Containerize Flask App

    Step 1.1 — Build Docker Image


    cd flask-app
    
    docker build -t my-flask-app:latest .

    # Verify
    docker images | grep my-flask-app
    # my-flask-app   latest   


    Step 1.2 — Test Locally


    docker run -d -p 5000:5000 --name flask-test my-flask-app:latest
    
    curl http://localhost:5000
    # Hello, World! 

    docker stop flask-test && docker rm flask-test


## Task 2 — Deploy on Local Kubernetes (Kind)


    Step 2.1 — Create Kind Cluster + Load Image


    kind create cluster --name local-cluster
    
    # Load local image into Kind (Kind does not pull from Docker Hub)
    kind load docker-image my-flask-app:latest --name local-cluster
    
    kubectl get nodes
    # local-cluster-control-plane   Ready 


    Step 2.2 — Deploy to Kind


    kubectl apply -f flask-app/deployment.yaml
    
    kubectl get pods -w
    # flask-app-deployment-xxxxx   1/1   Running 
    # flask-app-deployment-xxxxx   1/1   Running 
    
    # Test via port-forward
    kubectl port-forward svc/flask-app-service 8080:80
    In a second terminal:
    bashcurl http://localhost:8080
    # Hello, World! 

## Task 3 — Migrate to Amazon EKS
    
    Step 3.1 — Create EKS Cluster
    
    
    basheksctl create cluster \
      --name=$CLUSTER_NAME \
      --version=1.27 \
      --region=$AWS_REGION \
      --spot \
      --node-type=t2.medium \
      --nodes=1 \
      --nodes-min=1 \
      --nodes-max=2 \
      --nodegroup-name=flask-app-nodes \
      --managed

    aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
    kubectl get nodes
    # ip-xxx.ec2.internal   Ready 

    
    Step 3.2 — Create ECR Repository
    
    
    aws ecr create-repository \
      --repository-name $APP_NAME \
      --region $AWS_REGION
    
    ECR_URI=$(aws ecr describe-repositories \
      --repository-names $APP_NAME \
      --region $AWS_REGION \
      --query 'repositories[0].repositoryUri' \
      --output text)

    echo "ECR URI: $ECR_URI"
    # 164782963416.dkr.ecr.us-east-2.amazonaws.com/my-flask-app 


    Step 3.3 — Login to ECR


    aws ecr get-login-password --region $AWS_REGION \
      | docker login \
      --username AWS \
      --password-stdin \
      ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    # Login Succeeded 


    Step 3.4 — Tag and Push Image to ECR


    docker tag my-flask-app:latest $ECR_URI:latest
    docker push $ECR_URI:latest

    # Verify
    aws ecr list-images \
      --repository-name $APP_NAME \
      --region $AWS_REGION
    # imageTag: latest 


    Step 3.5 — Deploy to EKS


    bash# Update deployment-eks.yaml with your ECR URI first
    sed -i "s|ECR_IMAGE_URI|$ECR_URI:latest|g" flask-app/deployment-eks.yaml
    
    kubectl apply -f flask-app/deployment-eks.yaml
    
    kubectl get pods -w
    # flask-app-deployment-xxxxx   1/1   Running 
    # flask-app-deployment-xxxxx   1/1   Running 


    Step 3.6 — Get Load Balancer URL
    
    
    Wait 2-3 minutes for ELB to provision
    kubectl get svc flask-app-service -w
    
    APP_URL=$(kubectl get svc flask-app-service \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "App URL: http://$APP_URL"


    Step 3.7 — Test on EKS

    
    curl http://$APP_URL
    # Hello, World! 
    
    Final Verification
    bash# Pods running?
    kubectl get pods
    # flask-app-deployment-xxxxx   1/1   Running 
    
    # Load Balancer URL?
    kubectl get svc flask-app-service
    # LoadBalancer ... xxx.elb.amazonaws.com 

    # ECR image exists?
    aws ecr list-images \
      --repository-name $APP_NAME \
      --region $AWS_REGION \
      --query 'imageIds[*].imageTag'
    # ["latest"] 
    
    # App responding?
    curl http://$APP_URL
    # Hello, World! 
    
    echo "Migration complete!"

## Cleanup

    Delete K8s resources
    kubectl delete -f flask-app/deployment-eks.yaml
    
    # Delete ECR repository
    aws ecr delete-repository \
      --repository-name $APP_NAME \
      --region $AWS_REGION \
      --force
    
    # Delete EKS cluster
    eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
    
    # Delete Kind cluster
    kind delete cluster --name local-cluster

## License

This project is licensed under the MIT License.