# Flask Application Deployment with Docker, ECR and ECS Fargate:

    Overview
    This project containerizes a simple Flask web application using Docker,
    pushes the image to Amazon ECR, and deploys it on Amazon ECS
    with the Fargate launch type — no EC2 instances to manage.

    Flask app (app.py)
            |
            | docker build
            v
    Docker image (simple-web-app:latest)
            |
            | docker push
            v
    Amazon ECR (simple-web-app repository)
            |
            | ECS task definition
            v
    Amazon ECS Fargate (simple-web-cluster)
            |
            v
    http://PUBLIC_IP:5000

## Project Structure:

    Secrets_Management_on_Amazon_EKS/
    |
    |-- app/
    |   |-- app.py              # Flask application
    |   |-- Dockerfile          # Container build instructions
    |   |-- requirements.txt    # Python dependencies
    |   |-- templates/
    |   |   |-- index.html      # HTML template
    |   |-- static/
    |       |-- styles.css      # CSS styles
    |
    |-- task-def.json           # ECS Fargate task definition template
    |
    |-- README.md

## Prerequisites:

    Docker installed?
    docker --version
    
    # AWS CLI configured?
    aws sts get-caller-identity
    
    # Set variables
    export AWS_REGION="your-region"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "Account: $AWS_ACCOUNT_ID | Region: $AWS_REGION"

### Task 1 — Build Docker Image:
    
    cd app/
    
    docker build -t simple-web-app .

### Task 2 — Test Locally:

    bash# Run in foreground
    docker run -p 5000:5000 simple-web-app
    
    # Run in background (detached)
    docker run -d -p 5000:5000 simple-web-app
    
    # Check running containers
    docker ps
    
    # Test
    curl http://localhost:5000
    # Expected: HTML with "Hello, World!"

### Task 3 — Push to ECR:

    Create Repository
    aws ecr create-repository \
      --repository-name simple-web-app \
      --region $AWS_REGION
    
    ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/simple-web-app"
    echo "ECR URI: $ECR_URI"

### Authenticate Docker with ECR:

    aws ecr get-login-password --region $AWS_REGION | \
      docker login --username AWS --password-stdin \
      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    # Expected: Login Succeeded

### Tag and Push:

    docker tag simple-web-app:latest $ECR_URI:latest
    docker push $ECR_URI:latest
    
    # Verify
    aws ecr describe-images \
      --repository-name simple-web-app \
      --region $AWS_REGION \
      --query 'imageDetails[*].{Tag:imageTags[0],Size:imageSizeInBytes}' \
      --output table


### Task 4 — Deploy to ECS Fargate:

    Create Cluster
    aws ecs create-cluster \
      --cluster-name simple-web-cluster \
      --region $AWS_REGION

    Register Task Definition
    
    Update task-def.json with your actual values:
    json"executionRoleArn": "arn:aws:iam::YOUR-ACCOUNT-ID:role/ecsTaskExecutionRole",
    "image": "YOUR-ACCOUNT-ID.dkr.ecr.YOUR-REGION.amazonaws.com/simple-web-app:latest"

    Then register:
    aws ecs register-task-definition \
      --cli-input-json file://task-def.json \
      --region $AWS_REGION

    Create Service (Console)
    
    AWS Console → ECS → Clusters → simple-web-cluster → Services → Create
    
      Launch type:     FARGATE
      Task definition: simple-web-task
      Service name:    simple-web-service
      Desired tasks:   1
    
    Networking:
      VPC:             Default VPC
      Subnets:         Select available subnets
      Security group:  Allow inbound TCP on port 5000
      Public IP:       ENABLED
    
    → Create Service

### Task 5 — Test the Deployment:

    Get the Public IP from the console:
    # ECS → Cluster → Tasks → Task → Public IP
    
    PUBLIC_IP="xxx.xxx.xxx.xxx"
    
    curl http://${PUBLIC_IP}:5000
    # Expected: HTML with "Hello, World!"

    Or open http://PUBLIC_IP:5000 in a browser.

### Cleanup:

    Scale down service first
    aws ecs update-service \
      --cluster simple-web-cluster \
      --service simple-web-service \
      --desired-count 0 \
      --region $AWS_REGION
    
    # Delete service
    aws ecs delete-service \
      --cluster simple-web-cluster \
      --service simple-web-service \
      --region $AWS_REGION
    
    # Delete cluster
    aws ecs delete-cluster \
      --cluster simple-web-cluster \
      --region $AWS_REGION
    
    # Delete ECR image
    aws ecr batch-delete-image \
      --repository-name simple-web-app \
      --image-ids imageTag=latest \
      --region $AWS_REGION
    
    # Delete ECR repository
    aws ecr delete-repository \
      --repository-name simple-web-app \
      --region $AWS_REGION

### License:

    MIT License