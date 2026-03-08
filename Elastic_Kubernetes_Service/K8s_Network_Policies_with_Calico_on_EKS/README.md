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


Project Structure

    K8s_Network_Policies_with_Calico_on_EKS/
        │
        ├── k8s/
        │   ├── allow-nginx-policy.yaml    # Allow ingress from frontend → nginx only
        │   └── default-deny.yaml          # Default deny all ingress in namespace
        │
        └── README.md                      # Project documentation

