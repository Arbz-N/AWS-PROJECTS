# Secrets Management on Amazon EKS

    Overview
    SecureKube is a hands-on project that demonstrates three approaches to secrets management on Amazon EKS. 
    It covers storing secrets in AWS Secrets Manager, injecting them into pods via the Secrets Store CSI Driver, 
    and managing native Kubernetes Secrets as both environment variables and volume mounts.
    Key highlights:
    
    AWS Secrets Manager for centralized, auditable secret storage
    Secrets Store CSI Driver + AWS Provider for direct secret injection into pods
    OIDC-based IAM Service Account for secure, keyless pod authentication
    Auto-synced Kubernetes Secret from AWS Secrets Manager via secretObjects
    Native Kubernetes Secret as environment variable (Method 2)
    Native Kubernetes Secret as volume mount (Method 3)
    Full verification of all three methods

## Project Structure:

    Secrets_Management_on_Amazon_EKS/
    │
    ├── k8s/
    │   ├── secret-provider-class.yaml   # SecretProviderClass (AWS Secrets Manager)
    │   ├── pod-aws-secret.yaml          # Pod using CSI Driver (Method 1)
    │   ├── mysecret.yaml                # Native Kubernetes Secret
    │   ├── mypod-env.yaml               # Pod with secret as env variable (Method 2)
    │   └── mypod-vol.yaml               # Pod with secret as volume mount (Method 3)
    │
    └── README.md                        # Project documentation


## Prerequisites:
    
    Requirement                        Detail

    AWS Account                   Active with sufficient permissions
    AWS CLI                       Installed and configured
    kubectl                       Installed on local machine
    eksctl                        For EKS cluster management
    Helm 3.x                      For Prometheus and Grafana install

## Architecture:

    AWS Secrets Manager
      (MyApp/DatabaseCredentials)
              │
              │  GetSecretValue (IAM Role via OIDC)
              ▼
      Secrets Store CSI Driver  ◄──  AWS Provider (ASCP)
              │
              ▼
      SecretProviderClass
      (aws-secrets-db)
              │
              ├──► Volume Mount  ──► /mnt/secrets-store/db_username
              │                      /mnt/secrets-store/db_password
              │
              └──► secretObjects ──► K8s Secret (db-secret-from-aws)
                                            │
                                            └──► Env Variables
                                                 DB_USERNAME
                                                 DB_PASSWORD
    
      ─────────────────────────────────────────────────────
      Method 2: K8s Secret → Env Variable
      mysecret ──► MY_USERNAME / MY_PASSWORD (env)
    
      Method 3: K8s Secret → Volume Mount
      mysecret ──► /etc/secrets/username
               /etc/secrets/password

## Setup:

    export CLUSTER_NAME=security-lab
    export AWS_REGION=us-east-1
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    echo "Account: $ACCOUNT_ID"
    echo "Region:  $AWS_REGION"
    
    # Create EKS Cluster (if not already created)
    eksctl create cluster \
      --name=security-lab \
      --version=1.29 \
      --region=us-east-1 \
      --node-type=t3.medium \
      --nodes=2 \
      --managed
    
    aws eks --region us-east-1 update-kubeconfig --name security-lab
    kubectl get nodes

###  Task 1 — Store Secret in AWS Secrets Manager:
 
    aws secretsmanager create-secret \
      --name MyApp/DatabaseCredentials \
      --description "Database credentials" \
      --secret-string '{
        "username": "secret-user",
        "password": "secret-pass",
        "host": "mydb.us-east-1.rds.amazonaws.com",
        "port": "5432"
      }' \
      --region $AWS_REGION

    # IMPORTANT: Set SECRET_ARN immediately after creation
    SECRET_ARN=$(aws secretsmanager describe-secret \
      --secret-id MyApp/DatabaseCredentials \
      --region $AWS_REGION \
      --query 'ARN' --output text)
    
    echo "Secret ARN: $SECRET_ARN"
    # Expected: arn:aws:secretsmanager:us-east-1:... 
    # If empty → re-run the command above

### Task 2 — AWS Secrets Manager → Pod via CSI Driver (Method 1):

    Step 2.1 — Enable OIDC Provider
    
    eksctl utils associate-iam-oidc-provider \
      --region=$AWS_REGION \
      --cluster $CLUSTER_NAME \
      --approve
    
    aws iam list-open-id-connect-providers

### Step 2.2 — Create IAM Policy:

    cat > secrets-policy.json << EOF
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        "Resource": "$SECRET_ARN"
      }]
    }
    EOF
    
    cat secrets-policy.json

    aws iam create-policy \
      --policy-name EKSSecretsManagerPolicy \
      --policy-document file://secrets-policy.json

### Step 2.3 — Create IAM Service Account:

    # eksctl creates IAM Role + ServiceAccount + OIDC link in one command
    eksctl create iamserviceaccount \
      --name secrets-sa \
      --namespace default \
      --cluster $CLUSTER_NAME \
      --region $AWS_REGION \
      --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/EKSSecretsManagerPolicy \
      --approve
    
    # Verify annotation exists
    kubectl describe serviceaccount secrets-sa -n default | grep eks.amazonaws.com
    # eks.amazonaws.com/role-arn: arn:aws:iam::...

### Step 2.4 — Install Secrets Store CSI Driver:

    helm repo add secrets-store-csi-driver \
      https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
    helm repo update
    
    helm install csi-secrets-store \
      secrets-store-csi-driver/secrets-store-csi-driver \
      --namespace kube-system \
      --set syncSecret.enabled=true
    
    kubectl get pods -n kube-system | grep secrets-store
    # secrets-store-csi-driver-*   Running 

### Step 2.5 — Install AWS Provider (ASCP):

    kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
    
    kubectl get pods -n kube-system | grep csi-secrets-store-provider
    # csi-secrets-store-provider-aws-*   Running 

### Step 2.6 — Apply SecretProviderClass:

    kubectl apply -f k8s/secret-provider-class.yaml
    kubectl get secretproviderclass -n default
    # aws-secrets-db 
    
    # K8s Secret does NOT exist yet — this is expected
    kubectl get secrets
    # No resources found — normal  (Secret is created when pod starts)

### Step 2.7 — Deploy Pod:

    kubectl apply -f k8s/pod-aws-secret.yaml
    kubectl get pod pod-aws-secret -w
    # pod-aws-secret   1/1   Running 

### Step 2.8 — Verify:

    kubectl exec -it pod-aws-secret -- /bin/sh
    
    ls /mnt/secrets-store/
    # db_username  db_password
    
    cat /mnt/secrets-store/db_username
    # secret-user  (directly from AWS Secrets Manager)
    
    echo $DB_USERNAME
    # secret-user  (synced via secretObjects)
    
    exit
    
    # Verify auto-synced K8s Secret (created when pod started)
    kubectl get secret db-secret-from-aws
    # db-secret-from-aws   Opaque   2   
    
    kubectl get secret db-secret-from-aws \
      -o jsonpath='{.data.username}' | base64 --decode
    # secret-user 

### Task 3 — K8s Secret as Env Variable (Method 2):

    kubectl apply -f k8s/mysecret.yaml
    kubectl get secrets
    # mysecret   Opaque   2   
    
    kubectl apply -f k8s/mypod-env.yaml
    kubectl get pod mypod-env -w
    
    # Verify
    kubectl exec -it mypod-env -- /bin/sh
    echo $MY_USERNAME
    # secret-user 
    echo $MY_PASSWORD
    # secret-pass 
    exit

### Final Verification — All Three Methods:

    # All pods running?
    kubectl get pods
    # pod-aws-secret   Running 
    # mypod-env        Running 
    # mypod-vol        Running 
    
    # Method 1 — AWS Secrets Manager (volume mount)
    kubectl exec pod-aws-secret -- cat /mnt/secrets-store/db_username
    # secret-user 
    
    # Method 1 — AWS Secrets Manager (env variable)
    kubectl exec pod-aws-secret -- sh -c 'echo $DB_USERNAME'
    # secret-user 
    
    # Method 2 — K8s Secret env variable
    kubectl exec mypod-env -- sh -c 'echo $MY_USERNAME'
    # secret-user 
    
    # Method 3 — K8s Secret volume mount
    kubectl exec mypod-vol -- cat /etc/secrets/username
    # secret-user 

### Cleanup:

    # Delete pods and secrets
    kubectl delete pod pod-aws-secret mypod-env mypod-vol
    kubectl delete secret mysecret db-secret-from-aws
    kubectl delete secretproviderclass aws-secrets-db
    kubectl delete serviceaccount secrets-sa -n default
    
    # Uninstall CSI Driver
    helm uninstall csi-secrets-store -n kube-system
    
    # Delete local YAML files
    rm -f secrets-policy.json secret-provider-class.yaml \
          pod-aws-secret.yaml mysecret.yaml mypod-env.yaml mypod-vol.yaml
    
    # Delete IAM Policy
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/EKSSecretsManagerPolicy"
    aws iam list-policy-versions \
      --policy-arn $POLICY_ARN \
      --query 'Versions[?IsDefaultVersion==`false`].VersionId' \
      --output text | xargs -I{} aws iam delete-policy-version \
      --policy-arn $POLICY_ARN --version-id {}
    aws iam delete-policy --policy-arn $POLICY_ARN
    
    # Delete AWS Secret
    aws secretsmanager delete-secret \
      --secret-id MyApp/DatabaseCredentials \
      --force-delete-without-recovery \
      --region $AWS_REGION
    
    # Delete EKS Cluster
    eksctl delete cluster --name security-lab --region us-east-1


### License:

    This project is licensed under the MIT License.


