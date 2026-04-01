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


Task 1 — Create RDS PostgreSQL Instance:

    AWS Console → RDS → Create database
    
      Database creation method: Standard create
      Engine:                   PostgreSQL
      Engine version:           PostgreSQL 15.x (latest)
      Template:                 Free tier
    
      DB instance identifier:   my-postgres-db
      Master username:          postgres
      Master password:          (choose a strong password)
    
      Instance class:           db.t3.micro
      Storage:                  20 GB gp2
    
      VPC:                      Default VPC
      Public access:            Yes (for this lab only — disable in production)
      VPC security group:       Create new → rds-lab-sg
    
      Initial database name:    labdb
    
    → Create database
    Wait for status to change from Creating to Available (5–10 minutes).

    Note the endpoint from Connectivity & security tab:
    my-postgres-db.xxxx.us-east-1.rds.amazonaws.com

    Connect and Verify

    export RDS_ENDPOINT="my-postgres-db.xxxx.us-east-1.rds.amazonaws.com"
    
    psql -h $RDS_ENDPOINT -U postgres -d labdb -p 5432
    
    # Inside psql:
    labdb=> \l                  -- list databases
    labdb=> \dt                 -- list tables (empty at this point)
    labdb=> SELECT version();   -- confirm PostgreSQL version
    labdb=> \q                  -- quit

Task 2 — Automated Backup with Lambda

    Create Lambda Function
    AWS Console → Lambda → Create function
    
      Function name: RDSBackupFunction
      Runtime:       Python 3.11
      Role:          Create new role with basic Lambda permissions
    
    → Create function
    Paste the contents of rds_backup_lambda.py into the code editor and click Deploy.

    Grant RDS Access to Lambda
    Lambda → Configuration → Permissions → click the role name
    IAM Console → Add permissions → Attach policies
    Search: AmazonRDSFullAccess → Attach

Create EventBridge Schedule

    Lambda → Add trigger
      Source:           EventBridge (CloudWatch Events)
      Rule type:        Schedule expression
      Rule name:        RDSBackupRule
      Schedule:         cron(0 0 * * ? *)
                        (runs daily at midnight UTC)

    → Add




