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