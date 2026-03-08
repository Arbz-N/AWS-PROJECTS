# Kubernetes Network Policies with Calico on Amazon EKS

    This project is a hands-on project that demonstrates Calico-enforced Kubernetes Network Policies on Amazon EKS.
    Unlike the AWS VPC CNI native NetworkPolicy (which requires an addon), 
    this project installs Calico via the Tigera Operator — the official recommended method for EKS. 
    It then applies namespace-level policies to enforce traffic isolation between pods and validates enforcement with live curl tests.
    
    Key highlights:
    
    Calico installed via Tigera Operator (official EKS method)
    AWS VPC CNI retained as the CNI — Calico only handles policy enforcement
    ANNOTATE_POD_IP=true enabled for fast Calico pod IP tracking
    Default deny-all ingress policy applied across the namespace
    Selective allow policy grants only frontend pods access to nginx
    Full before/after test validation with curl from multiple pods


## Project Structure

    K8s_Network_Policies_with_Calico_on_EKS/
        │
        ├── k8s/
        │   ├── allow-nginx-policy.yaml    # Allow ingress from frontend → nginx only
        │   └── default-deny.yaml          # Default deny all ingress in namespace
        │
        └── README.md                      # Project documentation

## Prerequisites

    Requirement                     Detail

    AWS Account                     EKS, EC2, VPC, IAM permissions
    AWS CLI                         Installed and configured
    kubectl                         Installed
    eksctl                          For EKS cluster management

## Architecture
        
        default namespace
          ┌──────────────────────────────────────────────────────┐
          │                                                      │
          │   frontend pod ──────────────► nginx pod             │
          │   (app=frontend)      ALLOWED  (run=nginx)           │
          │                                                      │
          │   backend pod  ──── BLOCKED ──► nginx pod            │
          │   (app=backend)                (run=nginx)           │
          │                                                      │
          │   random-pod   ──── BLOCKED ──► nginx pod            │
          │   (no match)                   (run=nginx)           │
          │                                                      │
          └──────────────────────────────────────────────────────┘
        
          NetworkPolicy Rules:
          default-deny-ingress → blocks ALL ingress to ALL pods
          allow-nginx          → allows TCP:80 from app=frontend to run=nginx only
        
          Enforced by: Calico (Tigera Operator) on top of AWS VPC CNI


## Setup — Variables

    export CLUSTER_NAME=network-policy-lab
    export AWS_REGION=us-east-1
    export ACCOUNT_ID=$(aws sts get-caller-identity \
      --query Account --output text)
    
    echo "Account: $ACCOUNT_ID"
    echo "Region:  $AWS_REGION"


## Task 1 — EKS Cluster + Calico Install

    Step 1.1 — Create EKS Cluster


    basheksctl create cluster \
      --name=$CLUSTER_NAME \
      --version=1.27 \
      --region=$AWS_REGION \
      --node-type=t3.medium \
      --nodes=2 \
      --managed
    
    aws eks --region $AWS_REGION \
      update-kubeconfig --name $CLUSTER_NAME
    
    kubectl get nodes
    # ip-xxx   Ready 
    # ip-xxx   Ready 


    Step 1.2 — Enable Pod IP Annotation on AWS VPC CNI

    bash# Grant patch permission to aws-node ClusterRole

    cat << EOF > append.yaml
    - apiGroups:
      - ""
      resources:
      - pods
      verbs:
      - patch
    EOF
    
    kubectl apply -f <(cat <(kubectl get clusterrole aws-node -o yaml) append.yaml)
    # clusterrole.rbac.authorization.k8s.io/aws-node configured 

    # Enable ANNOTATE_POD_IP
    kubectl set env -n kube-system daemonset/aws-node ANNOTATE_POD_IP=true
    # daemonset.apps/aws-node env updated 
    
    # Verify
    kubectl get daemonset aws-node -n kube-system \
      -o jsonpath='{.spec.template.spec.containers[0].env}' \
      | grep ANNOTATE
    # {"name":"ANNOTATE_POD_IP","value":"true"} 

    Step 1.3 — Install Tigera Operator (Official EKS Method)

        # Install Calico CRDs
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/operator-crds.yaml
    
    # Install Tigera Operator
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/tigera-operator.yaml
    
    # Wait for operator pod to be Running
    kubectl get pods -n tigera-operator -w
    # tigera-operator-xxx   1/1   Running  (then Ctrl+C)


    Step 1.4 — Configure Calico for EKS + AmazonVPC Mode


    kubectl create -f - <<EOF
    apiVersion: operator.tigera.io/v1
    kind: Installation
    metadata:
      name: default
    spec:
      kubernetesProvider: EKS
      cni:
        type: AmazonVPC
      calicoNetwork:
        bgp: Disabled
    ---
    apiVersion: operator.tigera.io/v1
    kind: APIServer
    metadata:
      name: default
    spec: {}
    EOF
    # installation.operator.tigera.io/default created 
    # apiserver.operator.tigera.io/default created 


    Why AmazonVPC mode? Calico does NOT replace the AWS VPC CNI here. AWS VPC CNI handles pod networking (IP assignment), 
    while Calico only handles policy enforcement.This is the correct production setup for EKS.


    Step 1.5 — Wait for Calico to be Ready

    kubectl get pods -n calico-system -w
    # calico-kube-controllers-xxx   1/1   Running 
    # calico-node-xxx               1/1   Running 
    # calico-typha-xxx              1/1   Running 
    # (Ctrl+C when all are Running)
    
    # Verify nodes still healthy
    kubectl get nodes
    # ip-xxx   Ready 
    
    # Verify Calico installation status
    kubectl get tigerastatus
    # NAME     AVAILABLE   PROGRESSING   DEGRADED
    # calico   True        False         False    


Task 2 — Deploy Test Pods + Apply Network Policies

    Step 2.1 — Deploy Test Pods


    kubectl run nginx    --image=nginx --labels=run=nginx
    kubectl run frontend --image=nginx --labels=app=frontend
    kubectl run backend  --image=nginx --labels=app=backend
    
    kubectl get pods -w
    # nginx      1/1   Running 
    # fronten 1/1   Running 
    
    NGINX_IP=$(kubectl get d   1/1   Running 
    # backend   pod nginx -o jsonpath='{.status.podIP}')
    echo "Nginx IP: $NGINX_IP"


    Step 2.2 — Test Before Applying Policies


    # Both should succeed — no policy yet
    kubectl exec -it frontend -- curl -s --max-time 5 http://$NGINX_IP:80 | grep title
    # <title>Welcome to nginx!</title> 
    
    kubectl exec -it backend -- curl -s --max-time 5 http://$NGINX_IP:80 | grep title
    # <title>Welcome to nginx!</title>  (will be blocked after policy)


    Step 2.3 — Apply Network Policies

    
    kubectl apply -f k8s/allow-nginx-policy.yaml
    kubectl apply -f k8s/default-deny.yaml
    
    kubectl get networkpolicy
    # NAME                   POD-SELECTOR
    # allow-nginx            run=nginx
    # default-deny-ingress   <none>       


## Task 3 — Validate Policy Enforcement

    Test 1 — Frontend → Nginx (SHOULD WORK)
    bashkubectl exec -it frontend -- curl -s --max-time 5 http://$NGINX_IP:80 | grep title
    # <title>Welcome to nginx!</title> 
    
    Test 2 — Backend → Nginx (SHOULD BE BLOCKED)
    bashkubectl exec -it backend -- curl -s --max-time 5 http://$NGINX_IP:80
    # curl: (28) Connection timed out after 5000 milliseconds 
    
    Test 3 — Random Pod → Nginx (SHOULD BE BLOCKED)
    bashkubectl run random-pod --image=nginx
    kubectl exec -it random-pod -- curl -s --max-time 5 http://$NGINX_IP:80
    # curl: (28) Connection timed out 


Why Tigera Operator?

    The Tigera Operator is the official recommended installation method for Calico on EKS. 
    It manages the full lifecycle of Calico components and supports 
    the AmazonVPC CNI mode — meaning Calico only adds policy enforcement on top of the existing AWS networking without disrupting pod IP assignment


## Cleanup
    
    # Delete Network Policies
    kubectl delete networkpolicy allow-nginx default-deny-ingress
    
    # Delete test pods
    kubectl delete pod nginx frontend backend random-pod
    
    # Delete local files
    rm -f allow-nginx-policy.yaml default-deny.yaml append.yaml
    
    # Delete EKS Cluster
    eksctl delete cluster \
      --name $CLUSTER_NAME \
      --region $AWS_REGION

