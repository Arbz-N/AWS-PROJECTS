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

Test Manually:

    # Invoke without waiting for the schedule
    aws lambda invoke \
      --function-name RDSBackupFunction \
      --payload '{}' \
      response.json
    
    cat response.json
    # {"statusCode": 200, "body": "Snapshot created: my-postgres-db-snapshot-2026-..."}
    
    # Verify snapshot was created
    aws rds describe-db-snapshots \
      --db-instance-identifier my-postgres-db \
      --query 'DBSnapshots[*].{Snapshot:DBSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime}' \
      --output table

Task 3 — Optimize PostgreSQL Parameters:

    Create Parameter Group
    RDS → Parameter groups → Create parameter group
    
      Parameter group family: postgres15
      Group name:             lab-postgres-params
      Description:            Custom params for lab
    
    → Create

    Edit Parameters
    Open lab-postgres-params → Edit parameters
    
      shared_buffers   = 131072   (131072 × 8KB = 1GB — 25% of RAM)
      work_mem         = 16384    (16MB per sort operation)
      max_connections  = 100

    → Save changes
    Apply to Database
    RDS → my-postgres-db → Modify
      Parameter group: lab-postgres-params
      Apply:           Immediately
    
    → Modify DB instance

Task 4 — CloudWatch Alarm for High CPU

    Create SNS Topic
    AWS Console → SNS → Create topic
      Type: Standard
      Name: rds-alerts
    → Create
    
    Create subscription:
      Protocol: Email
      Endpoint: your@email.com
    → Create subscription
    
    Check your email and confirm the subscription.

    Create Alarm
    CloudWatch → Alarms → Create alarm
    → Select metric → RDS → Per-DB instance metrics
    → my-postgres-db → CPUUtilization → Select metric
    
      Threshold type:  Static
      Condition:       Greater than
      Threshold:       90
      Datapoints:      2 out of 2
      Period:          5 minutes
    
    Notification:
      In alarm state: send to rds-alerts SNS topic
    
    Alarm name: CPUUtilizationHigh
    → Create alarm

Task 5 — Verify Everything:

    # RDS instance status
    aws rds describe-db-instances \
      --db-instance-identifier my-postgres-db \
      --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Engine:Engine,Version:EngineVersion,Class:DBInstanceClass}' \
      --output table
    
    # List snapshots
    aws rds describe-db-snapshots \
      --db-instance-identifier my-postgres-db \
      --output table
    
    # CloudWatch alarm state
    aws cloudwatch describe-alarms \
      --alarm-names CPUUtilizationHigh \
      --query 'MetricAlarms[*].{Alarm:AlarmName,State:StateValue,Reason:StateReason}' \
      --output table
    
    # Connect and check applied parameters
    psql -h $RDS_ENDPOINT -U postgres -d labdb -c "
    SELECT version();
    SHOW shared_buffers;
    SHOW work_mem;
    SHOW max_connections;
    "

