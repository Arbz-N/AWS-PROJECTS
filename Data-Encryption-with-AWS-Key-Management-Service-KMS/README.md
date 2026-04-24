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



