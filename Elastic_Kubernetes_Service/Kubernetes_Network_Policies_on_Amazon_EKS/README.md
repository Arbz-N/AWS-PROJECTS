#  Kubernetes Network Policies on Amazon EKS

    This is a hands-on project that demonstrates Kubernetes Network Policies on Amazon EKS 
    using the AWS VPC CNI plugin. It deploys a multi-tier application (frontend + backend),
    enforces a default-deny-all policy, and selectively allows only the required traffic 
    paths — simulating a real production security model.

## Key highlights:

    EKS cluster with VPC CNI Network Policy support enabled via EKS Addon
    Multi-tier app deployed in a dedicated namespace
    Default deny-all policy blocks all ingress and egress
    Selective policies allow only frontend → backend communication
    DNS egress explicitly allowed for service name resolution
    Full connectivity tests before and after policy enforcement

## Project Structure

    Kubernetes Network Policies on Amazon EKS/
    │
    ├── k8s/
    │   ├── backend-deployment.yaml       # Backend Nginx Deployment (2 replicas)
    │   ├── backend-service.yaml          # ClusterIP Service for backend
    │   ├── frontend-deployment.yaml      # Frontend Nginx Deployment (2 replicas)
    │   ├── default-deny.yaml             # Default deny all ingress + egress
    │   ├── backend-network-policy.yaml   # Allow frontend → backend ingress
    │   └── frontend-egress-policy.yaml   # Allow frontend egress to backend + DNS
    │
    └── README.md                         # Project documentation

## Prerequisites

    Requirement                            Detail
    
    AWS Account                    EKS, EC2, IAM permissions required
    AWS CLI                        Installed and configured
    kubectl                        Installed on local machine
    eksctl                         For EKS cluster management
    VPC CNI                        Version 1.14+ required for NetworkPolicy support


## Architecture

          ┌─────────────────────────────────────────────────────┐
          │              Namespace: multi-tier-app              │
          │                                                     │
          │   ┌─────────────────┐        ┌──────────────────┐   │
          │   │    Frontend     │        │     Backend      │   │
          │   │   (2 replicas)  │──────► │  (2 replicas)    │   │
          │   │   app=frontend  │  HTTP  │  app=backend     │   │
          │   └─────────────────┘  :80   └──────────────────┘   │
          │          │                           ▲              │
          │          │ DNS (UDP/TCP :53)         │              │
          │          ▼                           │              │
          │   ┌─────────────────┐        ┌───────────────────┐  │
          │   │   kube-dns      │        │  backend-service  │  │
          │   │  (CoreDNS)      │        │  (ClusterIP :80)  │  │
          │   └─────────────────┘        └───────────────────┘  │
          │                                                     │
          │   ┌─────────────────┐                               │
          │   │   test-pod      │──── BLOCKED ────► Backend     │
          │   │  (no label)     │                               │
          │   └─────────────────┘                               │
          └─────────────────────────────────────────────────────┘

##   NetworkPolicy Rules:

      frontend  ──► backend-service   (allowed)
      frontend  ──► DNS :53           (allowed)
      test-pod  ──► backend-service   (blocked)
      backend   ──► frontend          (blocked)
      everything else                 (default deny)

## Setup — EKS Cluster:

    eksctl create cluster \
      --name=network-policy-lab \
      --version=1.34 \
      --region=us-east-1 \
      --node-type=t3.medium \
      --nodes=2 \
      --managed
    
    aws eks --region us-east-1 update-kubeconfig --name network-policy-lab
    
    kubectl get nodes

    Step 0 — Enable VPC CNI Network Policy

    # Step 1: Check VPC CNI version  (1.14+ require)
    kubectl get daemonset aws-node -n kube-system -o yaml | grep -A2 ENABLE_NETWORK_POLICY
    
    # Step 2: Enable it via EKS Addon 
    aws eks update-addon \
      --cluster-name network-policy-lab \
      --addon-name vpc-cni \
      --region us-east-1 \
      --configuration-values '{"enableNetworkPolicy": "true"}' \
      --resolve-conflicts OVERWRITE
    
    # Step 3: Wait for getting Acrtive
    aws eks describe-addon \
      --cluster-name network-policy-lab \
      --addon-name vpc-cni \
      --region us-east-1 \
      --query 'addon.{status:status,config:configurationValues}'
    # Expected: "status": "ACTIVE"
    
    # Step 4: Restart the aws-node pods 
    kubectl rollout restart daemonset aws-node -n kube-system
    kubectl rollout status daemonset aws-node -n kube-system
    
    # Step 5: Verify them 
    kubectl get pods -n kube-system | grep aws-node
    # aws-node-xxxxx   2/2   Running
    # aws-node-yyyyy   2/2   Running  

## Task 1 — Deploy Multi-Tier Application:

    # Namespace banao
    kubectl create namespace multi-tier-app
    
    # Deploy karo
    kubectl apply -f k8s/backend-deployment.yaml
    kubectl apply -f k8s/backend-service.yaml
    kubectl apply -f k8s/frontend-deployment.yaml
    
    # Verify
    kubectl get all -n multi-tier-app

    Connectivity Test — Before Network Policy Implementation

    FRONTEND_POD=$(kubectl get pods -n multi-tier-app \
      -l app=frontend \
      -o jsonpath='{.items[0].metadata.name}')
    
    kubectl exec -n multi-tier-app $FRONTEND_POD \
      -- curl -s --max-time 5 http://backend-service

     Expected: Nginx welcome page

## Task 2 — Apply Network Policies:
    
    Step 2.1 — Default Deny All
    kubectl apply -f k8s/default-deny.yaml

    # Now test — SHOULD FAIL
    kubectl exec -n multi-tier-app $FRONTEND_POD \
      -- curl -s --max-time 5 http://backend-service
    # Expected: curl: (28) Operation timed out  — block everything
    
    Step 2.2 — Frontend → Backend Allow
    kubectl apply -f k8s/backend-network-policy.yaml

    Step 2.3 — Frontend Egress + DNS Allow
    kubectl apply -f k8s/frontend-egress-policy.yaml

    Step 2.4 — Verify  Policies 

    kubectl get networkpolicy -n multi-tier-app

    # Expected:
    # NAME                    POD-SELECTOR   AGE
    # default-deny-all        <none>
    # backend-allow-frontend  app=backend
    # frontend-allow-egress   app=frontend


## Task 3 — Test Network Segmentation:

    Test 1 — Frontend → Backend (SHOULD WORK)

    kubectl exec -n multi-tier-app $FRONTEND_POD \
    -- curl -s --max-time 5 http://backend-service

    # Expected: Nginx welcome page 

    Test 2 — Random Pod → Backend (SHOULD FAIL)

    kubectl run test-pod \
      --image=nginx \
      --namespace=multi-tier-app \
      --restart=Never \
      -- sleep 3600
    
    kubectl wait --for=condition=Ready pod/test-pod -n multi-tier-app
    
    kubectl exec -n multi-tier-app test-pod \
      -- curl -s --max-time 5 http://backend-service
    # Expected: curl: (28) Operation timed out  — NetworkPolicy blocked it

    Test 3 — Backend → Frontend (SHOULD FAIL)

    BACKEND_POD=$(kubectl get pods -n multi-tier-app \
      -l app=backend \
      -o jsonpath='{.items[0].metadata.name}')
    
    kubectl exec -n multi-tier-app $BACKEND_POD \
      -- curl -s --max-time 5 http://frontend-deployment
    
### Cleanup:
    
    kubectl delete namespace multi-tier-app
    kubectl delete pod test-pod -n multi-tier-app --ignore-not-found
    
    eksctl delete cluster --name network-policy-lab --region us-east-1


### License:

    This project is licensed under the MIT License.