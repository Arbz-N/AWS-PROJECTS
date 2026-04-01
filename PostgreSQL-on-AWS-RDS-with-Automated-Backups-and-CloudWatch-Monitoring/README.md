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
RDSLab/
|
|-- rds_backup_lambda.py    # Lambda function — creates RDS snapshot
|
|-- README.md