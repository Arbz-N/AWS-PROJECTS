# AWS IAM Custom Policies and Permissions:


    Overview
    This project demonstrates AWS Identity and Access Management (IAM) concepts through hands-on creation 
    and simulation of policies, roles, and permission boundaries. 
    It covers writing custom JSON policies, attaching them to a role, applying a permission boundary, and validating effective permissions using the IAM policy simulator.

    Policy JSON files
            |
            | aws iam create-policy
            v
    AWS IAM Custom Policies
      -- S3ReadPolicy       (Policy1.json)
      -- EC2ReadPolicy      (Policy2.json)
      -- DynamoDB policy    (Policy3.json)
      -- BoundaryPolicy     (BoundaryPolicy.json)
            |
            | aws iam attach-role-policy
            v
    IAM Role (MyLabRole)
            |
            | aws iam put-role-permissions-boundary
            v
    Permission Boundary applied
            |
            | aws iam simulate-principal-policy
            v
    Effective permissions validated

## Project Structure:

    AWS-IAM-Custom-Policies-and-Permissions/
    |
    |-- Policy1.json          # S3 read-only (ListBucket, GetObject)
    |-- Policy2.json          # EC2 read-only + explicit deny on terminate/stop
    |-- Policy3.json          # DynamoDB CRUD with region condition
    |-- BoundaryPolicy.json   # Permission boundary — S3 only, deny IAM changes
    |-- trust-policy.json     # EC2 service trust relationship for the role
    |
    |-- README.md

## Prerequisites:

    Sudo apt update -y
    sudo apt install awscli -y
    aws --version
    
    aws configure
    # Enter: Access Key, Secret Key, Region, Output format
    
    aws sts get-caller-identity

### Task 1 — Validate Policy Files Locally:

    mkdir ~/iam-lab && cd ~/iam-lab
    # Copy all JSON files here
    
    # Validate JSON syntax
    python3 -m json.tool Policy1.json
    python3 -m json.tool Policy2.json
    python3 -m json.tool Policy3.json
    python3 -m json.tool BoundaryPolicy.json
    # Valid JSON prints formatted output
    # Invalid JSON shows the line number of the error

### Task 2 — Simulate Policies Without Creating Them:

    Test a single action against Policy1.json before creating it
    aws iam simulate-custom-policy \
      --policy-input-list file://Policy1.json \
      --action-names s3:ListBucket \
      --resource-arns arn:aws:s3:::mybucket
    
    # Expected:
    # "EvalDecision": "allowed"

### Task 3 — Create Role and Attach Policies:

    Create the Role
    aws iam create-role \
      --role-name MyLabRole \
      --assume-role-policy-document file://trust-policy.json
    
    ROLE_ARN=$(aws iam get-role \
      --role-name MyLabRole \
      --query 'Role.Arn' --output text)
    
    echo "Role ARN: $ROLE_ARN"

### Create and Attach Policies:

    # S3 read policy
    POLICY1_ARN=$(aws iam create-policy \
      --policy-name S3ReadPolicy \
      --policy-document file://Policy1.json \
      --query 'Policy.Arn' --output text)
    
    # EC2 read policy
    POLICY2_ARN=$(aws iam create-policy \
      --policy-name EC2ReadPolicy \
      --policy-document file://Policy2.json \
      --query 'Policy.Arn' --output text)
    
    # Attach both to the role
    aws iam attach-role-policy \
      --role-name MyLabRole --policy-arn $POLICY1_ARN
    
    aws iam attach-role-policy \
      --role-name MyLabRole --policy-arn $POLICY2_ARN

### Apply Permission Boundary:

    BOUNDARY_ARN=$(aws iam create-policy \
      --policy-name MyPermissionBoundary \
      --policy-document file://BoundaryPolicy.json \
      --query 'Policy.Arn' --output text)
    
    aws iam put-role-permissions-boundary \
      --role-name MyLabRole \
      --permissions-boundary $BOUNDARY_ARN

### Task 4 — Simulate Effective Permissions:

    # S3 ListBucket — should be allowed
    aws iam simulate-principal-policy \
      --policy-source-arn $ROLE_ARN \
      --action-names s3:ListBucket \
      --resource-arns arn:aws:s3:::mybucket
    
    # S3 DeleteBucket — should be denied (not in any policy)
    aws iam simulate-principal-policy \
      --policy-source-arn $ROLE_ARN \
      --action-names s3:DeleteBucket \
      --resource-arns arn:aws:s3:::mybucket
    
    # EC2 DescribeInstances — should be allowed
    aws iam simulate-principal-policy \
      --policy-source-arn $ROLE_ARN \
      --action-names ec2:DescribeInstances \
      --resource-arns "*"
    
    # EC2 TerminateInstances — should be denied (explicit Deny in Policy2.json)
    aws iam simulate-principal-policy \
      --policy-source-arn $ROLE_ARN \
      --action-names ec2:TerminateInstances \
      --resource-arns "*"

### Key Concepts:

    How Permission Boundaries Work
    A permission boundary sets the maximum permissions a role can have. Even if an identity policy grants an action, the boundary must also allow it for the action to be permitted.
    Effective permission = identity policy AND boundary policy
    
    identity policy allows s3:ListBucket  → YES
    boundary policy allows s3:ListBucket  → YES
    Result: ALLOWED
    
    identity policy allows ec2:DescribeInstances  → YES
    boundary policy allows ec2:DescribeInstances  → NO (boundary only allows S3)
    Result: DENIED

    Explicit Deny Always Wins

    An explicit "Effect": "Deny" in any attached policy overrides any "Effect": "Allow" regardless of the source. In Policy2, ec2:TerminateInstances is explicitly denied — no other policy can grant it as long as this policy is attached.
    Condition Keys
    Policy3 uses aws:RequestedRegion to restrict DynamoDB access to us-east-1 only. Requests from any other region are implicitly denied even if the action would otherwise be allowed.

### Cleanup:

    Detach policies from role
    aws iam detach-role-policy \
      --role-name MyLabRole --policy-arn $POLICY1_ARN
    aws iam detach-role-policy \
      --role-name MyLabRole --policy-arn $POLICY2_ARN
    
    # Remove permission boundary
    aws iam delete-role-permissions-boundary \
      --role-name MyLabRole
    
    # Delete role
    aws iam delete-role --role-name MyLabRole
    
    # Delete policies
    aws iam delete-policy --policy-arn $POLICY1_ARN
    aws iam delete-policy --policy-arn $POLICY2_ARN
    aws iam delete-policy --policy-arn $BOUNDARY_ARN
    
    # Remove local files
    rm -rf ~/iam-lab

### License:

    MIT License