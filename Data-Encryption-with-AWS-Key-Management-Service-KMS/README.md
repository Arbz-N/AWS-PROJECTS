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

Task 2 — Direct Encrypt and Decrypt Test:
    
    echo "Hello, this is secret data!" > plaintext.txt
    
    # Encrypt
    aws kms encrypt \
      --key-id alias/my-lab-cmk \
      --plaintext fileb://plaintext.txt \
      --region $AWS_REGION \
      --query 'CiphertextBlob' \
      --output text | base64 --decode > encrypted.bin
    
    ls -lh encrypted.bin
    # Binary ciphertext file
    
    # Decrypt
    aws kms decrypt \
      --ciphertext-blob fileb://encrypted.bin \
      --region $AWS_REGION \
      --query 'Plaintext' \
      --output text | base64 --decode
    
    # Expected: Hello, this is secret data!

Task 3 — S3 Integration (SSE-KMS):

    Enable default encryption on the bucket
    AWS Console → S3 → your-bucket → Properties → Default encryption → Edit
    
      Encryption type: Server-side encryption with AWS KMS keys (SSE-KMS)
      AWS KMS key:     Choose from your AWS KMS keys → my-lab-cmk
    
    → Save changes

    Test upload and verify encryption

    export BUCKET_NAME="your-bucket-name"
    
    echo "This is sensitive data - $(date)" > sensitive-data.txt
    
    aws s3 cp sensitive-data.txt s3://$BUCKET_NAME/
    
    # Verify object is encrypted with the CMK
    aws s3api head-object \
      --bucket $BUCKET_NAME \
      --key sensitive-data.txt \
      --query '{Encryption:ServerSideEncryption,KMSKey:SSEKMSKeyId}' \
      --output table
    
    # Download and decrypt automatically
    aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt downloaded.txt
    cat downloaded.txt




