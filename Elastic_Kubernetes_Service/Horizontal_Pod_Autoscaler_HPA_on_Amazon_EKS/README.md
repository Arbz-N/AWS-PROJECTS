# Horizontal_Pod_Autoscaler_HPA_on_Amazon_EKS

THis is a hands-on project that demonstrates Horizontal Pod Autoscaling (HPA) on Amazon EKS.
It deploys a sample Nginx application, configures CPU-based autoscaling,
and validates scale-up and scale-down behavior under real load using a load generator pod.

Key highlights:

    EKS cluster provisioned via eksctl with managed node groups
    Nginx deployment with proper CPU requests/limits for HPA compatibility
    Metrics Server installed for real-time CPU/Memory data collection
    HPA configured to scale between 1–10 pods at 50% CPU threshold
    Load testing with busybox / alpine to trigger autoscaling
    Full scale-up and scale-down verification

Project Structure
    Horizontal_Pod_Autoscaler_HPA_on_Amazon_EKS/
    │
    ├── k8s/
    │   ├── deployment.yaml       # Nginx Deployment with CPU requests/limits
    │   ├── service.yaml          # ClusterIP Service for internal access
    │   └── hpa.yaml              # HorizontalPodAutoscaler (CPU based)
    │
    └── README.md                 # Project documentation
    

Architecture

                    Load Generator Pod
                           │
                           │ HTTP requests (loop)
                           ▼
                      Service (ClusterIP)
                           │
                           ▼
                      Deployment (simple-app)
                      ┌─────────────────────────────┐
                      │ Pod-1 │ Pod-2 │ ... │ Pod-N │
                      └─────────────────────────────┘
                           │
                           │ CPU Metrics
                           ▼
                      Metrics Server
                           │
                           ▼
                      HPA Controller
                      ├──► CPU > 50% → Scale Up   ↑
                      └──► CPU < 50% → Scale Down ↓


Prerequisites

    Requirement                            Detail
    
    AWS Account                    EKS, EC2, IAM permissions required
    AWS CLI                        Installed and configured
    kubectl                        Installed on local machine
    eksctl                         For EKS cluster management


Task 1 — Deploy Application on EKS

sudo apt-get update && sudo apt-get full-upgrade -y

    Step 1.1 — Install kubectl

    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    kubectl version --client

    Step 1.2 — Install eksctl

    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo mv /tmp/eksctl /usr/local/bin
    eksctl version

    Step 1.3 — Install & Configure AWS CLI

    sudo apt-get install zip unzip -y
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip && sudo ./aws/install
    
    aws configure
    # Enter: AWS Access Key ID
    # Enter: AWS Secret Access Key
    # Enter: Default region (us-east-1)
    # Enter: Output format (json)

    Step 1.4 — Create EKS Cluster

        eksctl create cluster \
      --name=hpa-lab-cluster \
      --version=1.34 \
      --region=us-east-1 \
      --node-type=t3.medium \
      --nodes=2 \
      --nodes-min=2 \
      --nodes-max=4 \
      --nodegroup-name=hpa-lab-nodes \
      --managed

    # Update kubeconfig
    aws eks --region us-east-1 update-kubeconfig --name hpa-lab-cluster
    
    # Verify nodes
    kubectl get nodes
    # STATUS: Ready hona chahiye

    Step 1.5 — Deploy Application & Service

    kubectl apply -f k8s/deployment.yaml
    kubectl apply -f k8s/service.yaml
    
    kubectl get pods
    kubectl get svc simple-app

Task 2 — Configure HPA

    Step 2.1 — Install Metrics Server

    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    # Verify (1-2 minute wait karo)
    kubectl get pods -n kube-system | grep metrics-server
    
    # Test metrics
    kubectl top nodes
    kubectl top pods

    Step 2.2 — Apply HPA

    kubectl apply -f k8s/hpa.yaml

    # Status check karo
    kubectl get hpa simple-app-hpa
    # Expected:
    # NAME             TARGETS   MINPODS   MAXPODS   REPLICAS
    # simple-app-hpa   0%/50%    1         10        1

Task 3 — Test Autoscaling
    
    Step 3.1 — Start Load Generator (Terminal 1)
    
        kubectl run load-generator \
      --image=busybox:1.28 \       #use alpine if busybox does not work
      --restart=Never \
      -it \
      -- /bin/sh -c "while true; do wget -q -O- http://simple-app.default.svc.cluster.local; done"

    Step 3.2 — Monitor Scaling (Terminal 2)

    # HPA watch karo
    kubectl get hpa simple-app-hpa -w
    
    # Expected progression:
    # simple-app-hpa   0%/50%    1    ← start
    # simple-app-hpa   85%/50%   1    ← load aaya
    # simple-app-hpa   85%/50%   3    ← scale up
    # simple-app-hpa   92%/50%   6    ← aur scale up
    # simple-app-hpa   55%/50%   8    ← stabilize
    
    # Pods monitor karo
    kubectl get pods -w
    
    # CPU usage
    kubectl top pods

    Step 3.3 — Verify Scale Down

    # Load generator band karo
    kubectl delete pod load-generator
    
    # Scale down watch karo (5 minute lagte hain)
    kubectl get hpa simple-app-hpa -w
    
    # Expected:
    # simple-app-hpa   5%/50%    8    ← load gaya
    # simple-app-hpa   2%/50%    4    ← scale down
    # simple-app-hpa   0%/50%    1    ← minimum par wapas 

    Step 3.4 — Look HPA Events 
    
    kubectl describe hpa simple-app-hpa
    # Expected:
    # SuccessfulRescale  Scaled up to 3 replicas
    # SuccessfulRescale  Scaled up to 6 replicas
    # SuccessfulRescale  Scaled down to 1 replica

     HPA Formula

     desiredReplicas = ceil(currentReplicas × (currentCPU / targetCPU))

    Example:
      currentReplicas = 2
      currentCPU      = 80%
      targetCPU       = 50%
    
      desiredReplicas = ceil(2 × (80/50))
                     = ceil(3.2)
                     = 4 pods 

Cleanup

    kubectl delete hpa simple-app-hpa
    kubectl delete -f k8s/deployment.yaml
    kubectl delete -f k8s/service.yaml
    kubectl delete -f k8s/hpa.yaml
    kubectl delete pod load-generator --ignore-not-found
    
    eksctl delete cluster --name hpa-lab-cluster --region us-east-1


License

    This project is licensed under the MIT License.
        