# EKS Persistent Storage with Amazon EBS

    Overview
    KubePersist is a hands-on project that explores persistent storage options for Kubernetes on AWS using Amazon EKS and Amazon EBS (Elastic Block Store).
    It demonstrates how to attach EBS volumes to Kubernetes pods using the EBS CSI Driver, deploy a StatefulSet with auto-provisioned storage, and validate that data survives pod restarts.
    
    Key highlights:
    
    EKS cluster provisioned via eksctl
    EBS CSI Driver installed as a managed EKS addon with OIDC-based IAM authentication
    StorageClass with gp3 EBS volumes and WaitForFirstConsumer binding
    StatefulSet with auto-provisioned PersistentVolumeClaims
    Manual PV/PVC creation with a static EBS volume
    Full data persistence validation across pod restarts

## Project Structure

    EKS_Persistent_Storage_with_Amazon_EBS/
    │
    ├── k8s/
    │   ├── headless-svc.yaml       # Headless Service for StatefulSet
    │   ├── storageclass.yaml       # StorageClass (gp3 EBS, Retain policy)
    │   ├── statefulset.yaml        # StatefulSet with volumeClaimTemplates
    │   ├── pv.yaml                 # PersistentVolume (manual EBS binding)
    │   ├── pvc.yaml                # PersistentVolumeClaim (binds to PV)
    │   └── deployment.yaml         # Nginx Deployment with EBS volume
    │
    └── README.md                   # Project documentation

## Prerequisites

    Requirement                       Detail
    
    AWS Account              EKS, EC2, EBS, IAM permissions required
    AWS CLI                  Installed and configured
    kubectl                  Installed on local machine
    eksctl                   For EKS cluster management


## Architecture

    kubectl / User
           │
           ▼
      EKS API Server
           │
           ▼
      AWS EBS CSI Driver ◄──── IAM Role (OIDC)
           │
           ▼
      StorageClass (gp3)
           │
           ├──► StatefulSet ──► PVC (auto) ──► EBS Volume
           │         │
           │      Pod-0  Pod-1
           │
           └──► Deployment ──► PVC (manual) ──► PV ──► EBS Volume
                      │
                   Pod (nginx)

### Task 1 — Set Up EKS Cluster
    
    Step 1.0
    # Update packages and install kubectl
    sudo apt-get update && sudo apt-get install -y kubectl

    Step 1.1
    # Install AWS CLI
    # https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
    
    Step 1.2
    # Install aws-iam-authenticator (used for IAM-based EKS auth)
    # https://weaveworks-gitops.awsworkshop.io/60_workshop_6_ml/00_prerequisites.md/50_install_aws_iam_auth.html
    
    Step 1.3
    # Install eksctl
    # https://docs.aws.amazon.com/eks/latest/eksctl/installation.html
    
    Step 1.4
    # Create EKS Cluster

        eksctl create cluster \
      --name=<cluster_name>\
      --region=<region> \
      --node-type=<machine_type> \
      --nodes=2 \
      --nodes-min=2 \
      --nodes-max=3 \
      --version=<version>

    # Update kubeconfig
    aws eks --region us-east-1 update-kubeconfig --name myekscluster
    
    # Verify nodes
    kubectl get nodes

    Step 1.5
    EBS CSI Driver Setup
    Without OIDC, the EBS CSI Driver cannot assume IAM roles and volumes will not provision.
    
        eksctl utils associate-iam-oidc-provider \
      --region us-east-1 \
      --cluster myekscluster \
      --approve
    
    Step 1.6
    #Create IAM Role for EBS CSI Driver

        eksctl create iamserviceaccount \
      --name ebs-csi-controller-sa \
      --namespace kube-system \
      --cluster myekscluster \
      --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
      --approve \
      --role-only \
      --role-name AmazonEKS_EBS_CSI_DriverRole
    
    Step 1.7
    Install EBS CSI Driver (EKS Addon)
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    eksctl create addon \
      --name aws-ebs-csi-driver \
      --cluster myekscluster \
      --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole \
      --force
    
    # Verify installation
    kubectl get pods -n kube-system | grep ebs-csi

### Task 1 (cont.) — Deploy StatefulSet

    kubectl apply -f k8s/headless-svc.yaml
    kubectl apply -f k8s/storageclass.yaml
    kubectl apply -f k8s/statefulset.yaml
    
    # Monitor pod creation
    kubectl get pods -w
    
    # Check auto-created PVCs
    kubectl get pvc
    # Expected:
    # nginx-storage-nginx-0   Bound   pvc-xxx   2Gi   RWO   ebs-sc
    # nginx-storage-nginx-1   Bound   pvc-yyy   2Gi   RWO   ebs-sc

Task 2 — Attach EBS Volume (Manual PV/PVC)
 
    Step 2.1 — Create EBS Volume

    # Check node availability zone
    kubectl get nodes -o wide
    
    # Create EBS volume in same AZ as your node
    aws ec2 create-volume \
      --region us-east-1 \
      --availability-zone us-east-1a \
      --size 2 \
      --volume-type gp3 \
      --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=ebs-lab-volume}]'
    
    # Note the VolumeId: vol-xxxxxxxxxxxxxxxxx

    Step 2.2 — Apply PV, PVC and Deployment
    Replace vol-xxxxxxxxxxxxxxxxx in pv.yaml with your actual EBS Volume ID before applying.
    
    kubectl apply -f k8s/pv.yaml
    kubectl get pv
    
    kubectl apply -f k8s/pvc.yaml
    kubectl get pvc
    # Status should be: Bound
    
    kubectl apply -f k8s/deployment.yaml
    kubectl get pods

### Task 3 — Validate Data Persistence

        # Get pod name
    kubectl get pods
    
    # Write data into the pod
    kubectl exec -it <pod-name> -- /bin/bash
    echo "Hello from EBS Lab" > /usr/share/nginx/html/index.html
    cat /usr/share/nginx/html/index.html
    exit
    
    # Delete the pod
    kubectl delete pod <pod-name>
    
    # Watch new pod come up
    kubectl get pods -w
    
    # Verify data survived pod restart
    kubectl exec <new-pod-name> -- cat /usr/share/nginx/html/index.html
    # Expected: Hello from EBS Lab
    
    # For StatefulSet pods
    kubectl exec nginx-0 -- cat /usr/share/nginx/html/index.html

    If data is still present after pod deletion — EBS persistence is working correctly!

### Cleanup

    Always cleanup after the lab to avoid unexpected AWS charges!

    # Delete Kubernetes resources

    kubectl delete -f k8s/deployment.yaml
    kubectl delete -f k8s/pvc.yaml
    kubectl delete -f k8s/pv.yaml
    kubectl delete -f k8s/statefulset.yaml
    kubectl delete -f k8s/headless-svc.yaml
    kubectl delete -f k8s/storageclass.yaml
    
    # Delete EKS Cluster
    eksctl delete cluster --name myekscluster --region us-east-1
    
    # Delete manually created EBS Volume
    aws ec2 delete-volume --volume-id vol-xxxxxxxxxxxxxxxxx

### License
    
    This project is licensed under the MIT License.