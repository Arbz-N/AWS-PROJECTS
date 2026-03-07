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

Project Structure

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

Architecture

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

