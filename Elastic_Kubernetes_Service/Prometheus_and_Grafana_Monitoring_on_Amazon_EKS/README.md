# Prometheus + Grafana Monitoring on Amazon EKS

    This is a hands-on project that sets up a full observability stack on Amazon EKS using Prometheus for metrics collection and Grafana for dashboards and alerting. 
    It uses the EBS CSI Driver for persistent storage, Helm for installation, and demonstrates both pre-built and custom dashboard creation with PromQL queries
    
    Key highlights:
    
        EBS CSI Driver provisioning persistent volumes for Prometheus and Grafana
        Prometheus installed via Helm with dynamic EBS storage (Pull Model)
        Grafana auto-configured with Prometheus as default data source
        Pre-built community dashboards imported (Node Exporter, Kubernetes Cluster)



Project Structure:

    Prometheus + Grafana Monitoring on Amazon EKS/
    │
    ├── grafana/
    │   └── grafana.yaml              # Grafana values file (Prometheus datasource)
    │
    └── README.md                     # Project documentation

## Prerequisites:
    
    Requirement                        Detail

    AWS Account                   Active with sufficient permissions
    AWS CLI                       Installed and configured
    kubectl                       Installed on local machine
    eksctl                        For EKS cluster management
    Helm 3.x                      For Prometheus and Grafana install

Architecture

    EKS Cluster
       │
       ├── prometheus-node-exporter  (DaemonSet)
       │     └── Every node → exposes CPU / Memory / Disk metrics
       │
       ├── prometheus-kube-state-metrics
       │     └── K8s object state (pods, deployments, replicasets)
       │
       ├── prometheus-server
       │     └── Scrapes all /metrics endpoints (Pull Model)
       │     └── Stores in TSDB database
       │     └── Persisted on EBS Volume (gp2)
       │
       └── grafana
             └── Queries Prometheus via PromQL
             └── Renders dashboards
             └── Fires alerts (Slack / Email / PagerDuty)
                       │
                       ▼
              ┌──────────────────────────────┐
              │     AWS EBS (gp2)            │
              │  prometheus-server  (PVC)    │
              │  prometheus-alertmgr (PVC)   │
              │  grafana            (PVC)    │
              └──────────────────────────────┘

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

Step 1 — Install EBS CSI Driver

    Prometheus and Grafana require persistent storage. The EBS CSI Driver enables EKS to automatically provision EBS volumes

    EBS CSI Driver Setup
    Without OIDC, the EBS CSI Driver cannot assume IAM roles and volumes will not provision.
    
        eksctl utils associate-iam-oidc-provider \
      --region us-east-1 \
      --cluster myekscluster \
      --approve

    #Create IAM Role for EBS CSI Driver

        eksctl create iamserviceaccount \
      --name ebs-csi-controller-sa \
      --namespace kube-system \
      --cluster myekscluster \
      --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
      --approve \ 
      --role-only \
      --role-name AmazonEKS_EBS_CSI_DriverRole

    Install EBS CSI Driver (EKS Addon)
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    eksctl create addon \
      --name aws-ebs-csi-driver \
      --cluster myekscluster \
      --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole \
      --force
    
    # Verify installation
    kubectl get pods -n kube-system | grep ebs-csi


    Step 2 — Add Helm Repos


    helm repo add prometheus-community \
      https://prometheus-community.github.io/helm-charts
    
    helm repo add grafana \
      https://grafana.github.io/helm-charts
    
    helm repo update
    helm repo list


    Step 3 — Install Prometheus
 
    kubectl create namespace prometheus

    helm install prometheus prometheus-community/prometheus \
      --namespace prometheus \
      --set alertmanager.persistentVolume.storageClass="gp2" \
      --set server.persistentVolume.storageClass="gp2"
    
    # Watch pods come up
    kubectl get pods -n prometheus -w   
    

    # Verify all components
    kubectl get all -n prometheus
    # prometheus-server-*              1/1   Running 
    # prometheus-alertmanager-*        1/1   Running 
    # prometheus-kube-state-metrics-*  1/1   Running 
    # prometheus-node-exporter-*       1/1   Running 
    # prometheus-pushgateway-*         1/1   Running 
    
    # Verify PVCs are Bound
    kubectl get pvc -n prometheus
    # prometheus-server         Bound 
    # prometheus-alertmanager   Bound 


    Step 4 — Expose Prometheus Publicly


    # Patch service type from ClusterIP to LoadBalancer

    kubectl patch svc prometheus-server \
      -n prometheus \
      --type=json \
      -p='[{"op": "replace", "path": "/spec/type", "value": "LoadBalancer"}]'
    
    # Wait for DNS (2-3 minutes)
    kubectl get svc prometheus-server -n prometheus -w
    
    # Get URL
    PROMETHEUS_URL=$(kubectl get svc prometheus-server -n prometheus \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "Prometheus URL: http://$PROMETHEUS_URL"


    Step 6 — Create Grafana Config File

    mkdir -p ${HOME}/environment/grafana

    mkdir -p ${HOME}/environment/grafana

    cat << 'EOF' > ${HOME}/environment/grafana/grafana.yaml
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-server.prometheus.svc.cluster.local
          access: proxy
          isDefault: true
    EOF
    
    cat ${HOME}/environment/grafana/grafana.yaml


    Step 7 — Install Grafana

    
    kubectl create namespace grafana

    helm install grafana grafana/grafana \
      --namespace grafana \
      --set persistence.storageClassName="gp2" \
      --set persistence.enabled=true \
      --set adminPassword='eks-monitoring' \
      --values ${HOME}/environment/grafana/grafana.yaml \
      --set service.type=LoadBalancer
    
    kubectl get pods -n grafana
    # grafana-*   1/1   Running 


     Step 8 — Get Grafana URL + Password


    # Retrieve admin password
    kubectl get secret \
      --namespace grafana grafana \
      -o jsonpath="{.data.admin-password}" | base64 --decode
    echo ""

    # Login:
    # Username: admin
    # Password: eks-monitoring
        

    Step 9 — Import Pre-built Dashboards


    Grafana Console:
    1. Left menu → Dashboards → Import
    2. Enter Dashboard ID:

      3119  → Kubernetes Cluster Monitoring (basic)
      6417  → Kubernetes Cluster (Prometheus)
      1860  → Node Exporter Full
      8685  → Kubernetes Deployment / StatefulSet / DaemonSet

    3. Click "Load"
    4. Select data source: Prometheus
    5. Click "Import" 


Cleanup

        # Remove Grafana
    helm uninstall grafana -n grafana
    kubectl delete namespace grafana
    rm -rf ${HOME}/environment/grafana
    
    # Remove Prometheus
    helm uninstall prometheus -n prometheus
    kubectl delete namespace prometheus
    
    # Remove EBS CSI Driver
    aws eks delete-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name aws-ebs-csi-driver \
      --region $AWS_REGION
    
    # Remove IAM Role
    aws iam detach-role-policy \
      --role-name AmazonEKS_EBS_CSI_DriverRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
    
    aws iam delete-role --role-name AmazonEKS_EBS_CSI_DriverRole


