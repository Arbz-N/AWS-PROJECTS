# Data Encryption with AWS Key Management Service (KMS)

    Overview
    This project demonstrates AWS Key Management Service (KMS) for data protection across multiple AWS services. 
    A Customer Managed Key (CMK) is created, used to encrypt and decrypt data directly, 
    and then integrated with S3 (SSE-KMS) and RDS (storage encryption). Key rotation and key policy management are also covered.
    Key highlights:
    
        CMK created with alias my-lab-cmk — symmetric AES-256 key
        CLI-based encrypt/decrypt test using aws kms encrypt and aws kms decrypt
        S3 bucket default encryption set to SSE-KMS using the CMK
        RDS MySQL instance created with --storage-encrypted and the CMK
        Annual automatic key rotation enabled
        Key disable/enable tested to observe KMSDisabledException
        Key scheduled for deletion with a 7-day pending window
    
Project Structure

    Data-Encryption-with-AWS-Key-Management-Service-KMS/
    |
    |-- README.md

    All operations in this lab are performed via AWS Console and CLI. 
    No application code files are required.

Prerequisites:
    
    aws sts get-caller-identity
    
    export AWS_REGION="your-region"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "Account: $AWS_ACCOUNT_ID | Region: $AWS_REGION"

Architecture:

    IAM User / Role
            |
            | kms:Encrypt, kms:Decrypt, kms:GenerateDataKey
            v
    CMK (alias/my-lab-cmk)
      |
      |-- Direct encrypt/decrypt (CLI test)
      |
      |-- S3 Bucket (SSE-KMS default encryption)
      |   Upload → auto-encrypt with CMK
      |   Download → auto-decrypt with CMK
      |
      |-- RDS MySQL (storage-encrypted)
          All data at rest encrypted with CMK

Task 1 — Create Customer Managed Key (CMK):

    Console
    AWS Console → KMS → Customer managed keys → Create key
    
    Step 1 — Key type:
      Key type:   Symmetric
      Key usage:  Encrypt and decrypt
    
    Step 2 — Labels:
      Alias:       my-lab-cmk
      Description: KMS Lab - Data Protection Key
    
    Step 3 — Key administrators:
      Select your IAM user or role
    
    Step 4 — Key users:
      Select your IAM user or role
    
    Step 5 — Review → Finish

    Verify
    
    aws kms describe-key \
      --key-id alias/my-lab-cmk \
      --region $AWS_REGION \
      --query 'KeyMetadata.{KeyId:KeyId,State:KeyState,Usage:KeyUsage,Created:CreationDate}' \
      --output table
    
    # Save the Key ID for later tasks
    KEY_ID=$(aws kms describe-key \
      --key-id alias/my-lab-cmk \
      --region $AWS_REGION \
      --query 'KeyMetadata.KeyId' \
      --output text)
    echo "Key ID: $KEY_ID"




