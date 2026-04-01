# PostgreSQL on AWS RDS with Automated Backups and CloudWatch Monitoring

    Overview
    This project provisions an Amazon RDS PostgreSQL instance, sets up an automated daily snapshot via Lambda and EventBridge, 
    optimizes PostgreSQL parameters through a custom parameter group, and configures a CloudWatch alarm to alert on high CPU usage.
   
    EventBridge (cron — daily midnight UTC)
            |
            v
    Lambda (RDSBackupFunction)
            |
            | boto3 rds.create_db_snapshot()
            v
    RDS Snapshot (AWS-managed storage)
    
    RDS PostgreSQL (my-postgres-db)
            |
            | metrics every minute
            v
    CloudWatch → CPUUtilizationHigh alarm
            |
            v
    SNS Topic (rds-alerts) → Email notification


Project Structure

    PostgreSQL-on-AWS-RDS-with-Automated-Backups-and-CloudWatch-Monitoring/
    |
    |-- rds_backup_lambda.py    # Lambda function — creates RDS snapshot
    |
    |-- README.md

Prerequisites

    # Verify AWS CLI
    aws sts get-caller-identity
    
    export AWS_DEFAULT_REGION=us-east-1
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "Account ID: $ACCOUNT_ID"
    
    # Install PostgreSQL client
    sudo apt install postgresql-client -y
    # macOS: brew install libpq