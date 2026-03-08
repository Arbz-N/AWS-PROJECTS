# Kubernetes RBAC on Amazon EKS

    This project is a hands-on project that demonstrates Role-Based Access Control (RBAC) on Amazon EKS.
    It covers creating namespace-scoped Roles and cluster-wide ClusterRoles, 
    binding them to users and ServiceAccounts, and verifying permissions using kubectl auth can-i.

    Key highlights:

    Namespace-scoped Role for read-only pod access
    Developer Role with multi-resource and multi-verb permissions
    ClusterRole for cluster-wide read access across all namespaces
    ServiceAccount RBAC with resourceNames for least-privilege secret access
    Permission verification using kubectl auth can-i --as
    Full cleanup commands included

## Project Structure

    Kubernetes_RBAC_on_Amazon_EKS/
    │
    ├── k8s/
    │   ├── pod-reader-role.yaml            # Read-only Role for pods
    │   ├── pod-reader-rolebinding.yaml     # Bind pod-reader to user ali
    │   ├── developer-role.yaml             # Developer Role (pods, deployments, logs)
    │   ├── developer-binding.yaml          # Bind developer to user ali
    │   ├── app-secret-role.yaml            # Secret reader (least privilege)
    │   ├── app-secret-binding.yaml         # Bind secret-reader to my-app-sa
    │   ├── cluster-pod-reader.yaml         # ClusterRole (pods + nodes, all namespaces)
    │   └── cluster-pod-reader-binding.yaml # Bind ClusterRole to monitor-user
    │
    └── README.md                           # Project documentation


## Prerequisites

    Requirement                     Detail
    
    AWS Account                     EKS, EC2, VPC, IAM permissions
    AWS CLI                         Installed and configured
    kubectl                         Installed
    eksctl                          For EKS cluster management

## Architecture

        Kubernetes API Server
                  │
                  │  RBAC Authorization
                  ▼
          ┌───────────────────────────────────────────────────────┐
          │                  default namespace                    │
          │                                                       │
          │  User: ali ──► RoleBinding: read-pods                 │
          │                     └──► Role: pod-reader             │
          │                          (get, list pods)             │
          │                                                       │
          │  User: ali ──► RoleBinding: ali-developer             │
          │                     └──► Role: developer              │
          │                          (pods, services, deployments)│
          │                                                       │
          │  SA: my-app-sa ──► RoleBinding: app-reads-secret      │
          │                        └──► Role: secret-reader       │
          │                             (get secret/mysecret only)│
          └───────────────────────────────────────────────────────┘
        
          ┌───────────────────────────────────────────────────────┐
          │               Cluster-Wide (all namespaces)           │
          │                                                       │
          │  User: monitor-user ──► ClusterRoleBinding            │
          │                             └──► ClusterRole          │
          │                                  (get, list, watch    │
          │                                   pods + nodes)       │
          └───────────────────────────────────────────────────────┘


## Setup

    export CLUSTER_NAME=security-lab
    export AWS_REGION=us-east-1
    
    eksctl create cluster \
      --name=security-lab \
      --region=us-east-1 \
      --node-type=t3.small \
      --nodes=2 \
      --nodes-min=2 \
      --nodes-max=3 \
      --version=1.29

    aws eks --region us-east-1 update-kubeconfig --name security-lab
    kubectl get nodes

## Step 1 — Create Read-Only Role

    kubectl apply -f k8s/pod-reader-role.yaml
    
    # Verify
    kubectl describe role pod-reader -n default
    # Resources   Verbs
    # pods        [get list] 

## Step 2 — Create RoleBinding

    kubectl apply -f k8s/pod-reader-rolebinding.yaml
    kubectl describe rolebinding read-pods -n default

## Step 3 — Test Permissions

    kubectl auth can-i get pod --as ali -n default
    # yes  (granted)
    
    kubectl auth can-i list pod --as ali -n default
    # yes  (granted)
    
    kubectl auth can-i delete pod --as ali -n default
    # no  (not granted)
    
    kubectl auth can-i get secret --as ali -n default
    # no  (not granted)
    
    kubectl auth can-i get pod --as ali -n kube-system
    # no  (namespace-scoped Role — default only)

## Step 4 — Developer Role (Multiple Resources)

    kubectl apply -f k8s/developer-role.yaml
    kubectl apply -f k8s/developer-binding.yaml
    
    # Test
    kubectl auth can-i create deployment --as ali -n default
    # yes 
    
    kubectl auth can-i delete namespace --as ali
    # no  (no cluster-level permission)

## Step 5 — RBAC for ServiceAccount (Least Privilege)

    kubectl create serviceaccount my-app-sa -n default
    
    kubectl apply -f k8s/app-secret-role.yaml
    kubectl apply -f k8s/app-secret-binding.yaml
    
    # Test — only mysecret is accessible
    kubectl auth can-i get secret/mysecret \
      --as system:serviceaccount:default:my-app-sa
    # yes 
    
    kubectl auth can-i get secret/other-secret \
      --as system:serviceaccount:default:my-app-sa
    # no  (least privilege)

## Step 6 — ClusterRole (Cluster-Wide Access)

    kubectl apply -f k8s/cluster-pod-reader.yaml
    kubectl apply -f k8s/cluster-pod-reader-binding.yaml
    
    # Test — works across all namespaces
    kubectl auth can-i list pod --as monitor-user -n default
    # yes 
    
    kubectl auth can-i list pod --as monitor-user -n kube-system
    # yes  (ClusterRole applies to all namespaces)
    
    kubectl auth can-i delete pod --as monitor-user
    # no  (read-only was granted)

## Final Verification

    # All Roles in default namespace
    kubectl get roles -n default
    # pod-reader    
    # developer     
    # secret-reader 

    # All RoleBindings
    kubectl get rolebindings -n default
    # read-pods        
    # ali-developer    
    # app-reads-secret 

    # ClusterRole and ClusterRoleBinding
    kubectl get clusterrole cluster-pod-reader
    kubectl get clusterrolebinding cluster-read-pods
    
    echo "=== ali permissions ==="
    kubectl auth can-i get pod --as ali -n default       # yes 
    kubectl auth can-i delete namespace --as ali         # no  
    
    echo "=== monitor-user permissions ==="
    kubectl auth can-i list pod --as monitor-user -n default      # yes 
    kubectl auth can-i list pod --as monitor-user -n kube-system  # yes 
    kubectl auth can-i delete pod --as monitor-user               # no  

    echo "=== my-app-sa permissions ==="
    kubectl auth can-i get secret/mysecret \
      --as system:serviceaccount:default:my-app-sa   # yes 
    kubectl auth can-i get secret/other-secret \
      --as system:serviceaccount:default:my-app-sa   # no  


## Cleanup

    # Delete Roles and RoleBindings
    kubectl delete role pod-reader developer secret-reader -n default
    kubectl delete rolebinding read-pods ali-developer app-reads-secret -n default
    
    # Delete ClusterRole and ClusterRoleBinding
    kubectl delete clusterrole cluster-pod-reader
    kubectl delete clusterrolebinding cluster-read-pods
    
    # Delete ServiceAccount
    kubectl delete serviceaccount my-app-sa -n default
    
    # Delete local YAML files
    rm -f pod-reader-role.yaml pod-reader-rolebinding.yaml \
          developer-role.yaml developer-binding.yaml \
          app-secret-role.yaml app-secret-binding.yaml \
          cluster-pod-reader.yaml cluster-pod-reader-binding.yaml
    
    # Delete EKS Cluster
    eksctl delete cluster --name security-lab --region us-east-1

## License

    This project is licensed under the MIT License.