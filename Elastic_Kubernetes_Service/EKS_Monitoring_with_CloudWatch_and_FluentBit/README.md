#  EKS Monitoring with CloudWatch + FluentBit

    This is a hands-on project that integrates an Amazon EKS cluster with AWS CloudWatch for metrics and log collection.
    It deploys the CloudWatch Agent (metrics) and FluentBit (logs) as DaemonSets on every node, enabling Container Insights dashboards and centralized log management.
       
     Key highlights:
        
        CloudWatch Observability Addon installed via AWS CLI 
        CloudWatch Agent DaemonSet collects CPU, Memory, and Network metrics per node
        FluentBit DaemonSet collects container logs and pushes to CloudWatch Logs
        IAM policy attached to Node Role for CloudWatch access
        ConfigMap provides cluster name and region to the CloudWatch Agent
        Container Insights dashboards for Kubernetes-specific visibility

## Project Structure:

    EKS Monitoring with CloudWatch + FluentBit/
    │
    ├── k8s/
    │   └── cluster-info-configmap.yaml   # ConfigMap with cluster name + region
    │
    └── README.md                         # Project documentation


## Prerequisites:
    
    Requirement                        Detail

    AWS Account                   Active with sufficient permissions
    AWS CLI                       Installed and configured
    kubectl                       Installed on local machine
    eksctl                        For EKS cluster management

## Architecture:

    EKS Cluster
           │
           ├── CloudWatch Agent (DaemonSet)
           │     │
           │     ├── Node-1: 1 Pod  ──► CPU, Memory, Network metrics
           │     ├── Node-2: 1 Pod  ──► CPU, Memory, Network metrics
           │     └── Pushes to AWS CloudWatch (Container Insights)
           │
           └── FluentBit (DaemonSet)
                 │
                 ├── Node-1: 1 Pod  ──► Container logs
                 ├── Node-2: 1 Pod  ──► Container logs
                 └── Pushes to AWS CloudWatch Logs
                           │
                           ▼
                  ┌─────────────────────────────────┐
                  │        AWS CloudWatch           │
                  │                                 │
                  │  Container Insights             │
                  │  ├── CPU Utilization            │
                  │  ├── Memory Utilization         │
                  │  └── Network I/O                │
                  │                                 │
                  │  Log Groups                     │
                  │  ├── .../application            │
                  │  ├── .../performance            │
                  │  └── .../dataplane              │
                  └─────────────────────────────────┘

## Lab Steps:
    
    eksctl create cluster \
      --name=monitoring-lab \
      --version=1.34 \
      --region=us-east-1 \
      --node-type=t3.medium \
      --nodes=2 \
      --managed
    
    aws eks --region us-east-1 update-kubeconfig --name monitoring-lab
    kubectl get nodes

    Set Variables
    
    export CLUSTER_NAME=monitoring-lab
    export AWS_REGION=us-east-1
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    echo "Cluster: $CLUSTER_NAME"
    echo "Region:  $AWS_REGION"
    echo "Account: $ACCOUNT_ID"


    Step 1 — Attach CloudWatch Policy to Node IAM Role


    # Dynamically find Node IAM Role (suffix is random per cluster)
    NODE_ROLE=$(aws iam list-roles \
      --query "Roles[?contains(RoleName, 'NodeInstanceRole')].RoleName" \
      --output text)
    echo "Node Role: $NODE_ROLE"
    
    # Attach CloudWatch policy
    aws iam attach-role-policy \
      --role-name $NODE_ROLE \
      --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    
    # Verify
    aws iam list-attached-role-policies \
      --role-name $NODE_ROLE | grep CloudWatch
    # CloudWatchAgentServerPolicy


    Step 2 — Create CloudWatch Namespace


    kubectl create namespace amazon-cloudwatch

    kubectl label namespace amazon-cloudwatch \
      name=amazon-cloudwatch
    
    kubectl get namespace amazon-cloudwatch --show-labels
    # name=amazon-cloudwatch 

    Step 3 — Create Cluster Info ConfigMap
    
    kubectl apply -f cluster-info-configmap.yml

    kubectl describe configmap cluster-info -n amazon-cloudwatch
    # cluster.name: monitoring-lab 
    # logs.region:  us-east-1    

    
    Step 4 — Install CloudWatch Observability Addon

    
        aws eks create-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name amazon-cloudwatch-observability \
      --region $AWS_REGION
    
    # Check status
    aws eks describe-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name amazon-cloudwatch-observability \
      --region $AWS_REGION \
      --query 'addon.status'
    # "ACTIVE" 


    Step 5 — Verify Pods
    
    # Both DaemonSets should have one pod per node
    kubectl get pods -n amazon-cloudwatch
    # cloudwatch-agent-xxxxx   1/1   Running 
    # fluent-bit-xxxxx         1/1   Running 
    
    # View DaemonSets
    kubectl get daemonset -n amazon-cloudwatch
    
    # Node count should match pod count
    kubectl get nodes | wc -l
    # 2 nodes → 2 cloudwatch-agent pods + 2 fluent-bit pods


    Step 6 — Verify in AWS Console

    AWS Console → CloudWatch → Container Insights
      → EKS Clusters → monitoring-lab
      → CPU Utilization     
      → Memory Utilization  
      → Network I/O         
    
    AWS Console → CloudWatch → Log Groups
      → /aws/containerinsights/monitoring-lab/application  
      → /aws/containerinsights/monitoring-lab/performance  
     → /aws/containerinsights/monitoring-lab/dataplane   

## Cleanup:

    # Delete CloudWatch Addon
    aws eks delete-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name amazon-cloudwatch-observability \
      --region $AWS_REGION
    
    # Delete namespace
    kubectl delete namespace amazon-cloudwatch
    
    # Detach IAM policy from Node Role
    aws iam detach-role-policy \
      --role-name $NODE_ROLE \
      --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    
    # Delete EKS Cluster
    eksctl delete cluster --name monitoring-lab --region us-east-1

## License:

    This project is licensed under the MIT License.