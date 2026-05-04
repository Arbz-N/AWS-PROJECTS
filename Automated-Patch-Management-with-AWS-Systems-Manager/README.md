 Automated Patch Management with AWS Systems Manager


    Overview
    This project sets up AWS Systems Manager Patch Manager to automatically scan and patch EC2 instances on a schedule. A custom patch baseline defines which patches to apply and when. A Maintenance Window controls the patching schedule. CloudWatch and SNS alert on non-compliant instances, and SSM State Manager provides auto-remediation.
    Key highlights:
    
        Patch Group tag applied to EC2 instances — Patch Manager uses this exact key
        Custom patch baseline for Ubuntu with separate rules for Critical and Important severity
        Patch baseline associated with the production-servers patch group
        Maintenance Window scheduled for every Sunday at 2:00 AM UTC
        AWS-RunPatchBaseline document used for both Scan and Install operations
        Rate control: 50% concurrency, 25% error threshold
        CloudWatch alarm triggers SNS email when any instance is non-compliant
        SSM State Manager association provides weekly auto-remediation

Project Structure:

    Automated-Patch-Management-with-AWS-Systems-Manager/
    |
    |-- README.md

    All operations are performed via AWS Console and CLI. No application code files are required.

Architecture:
    
    EC2 Instances (Patch Group=production-servers)
            |
            | SSM Agent (online)
            v
    SSM Patch Manager
      |
      |-- Custom Patch Baseline (production-ubuntu-baseline)
      |   |-- Rule 1: Critical security patches → auto-approve 7 days
      |   |-- Rule 2: Important security patches → auto-approve 14 days
      |   |-- Associated with: production-servers patch group
      |
      |-- Maintenance Window (production-patch-window)
      |   |-- Schedule: cron(0 2 ? * SUN *)  — Sunday 2 AM UTC
      |   |-- Target: tag Patch Group=production-servers
      |   |-- Task: AWS-RunPatchBaseline (Install, RebootIfNeeded)
      |   |-- Concurrency: 50%  Error threshold: 25%
      |
      |-- Compliance Reporting → Compliant / Non-Compliant
      |
      |-- CloudWatch Alarm → SNS Topic → Email alert
      |
      |-- SSM State Manager Association → weekly auto-remediation

Task 1 — Tag Instances with Patch Group:
    
    # List running instances
    aws ec2 describe-instances \
      --filters "Name=instance-state-name,Values=running" \
      --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
      --output table
    
    # Apply Patch Group tag to web-server-01
    aws ec2 create-tags \
      --resources i-0XXXXXXXXXXXXXXXXX \
      --tags Key="Patch Group",Value="production-servers"
    # "Patch Group" must have a space — SSM looks for this exact key name
    
    # Apply Patch Group tag to web-server-02
    aws ec2 create-tags \
      --resources i-0XXXXXXXXXXXXXXXXX \
      --tags Key="Patch Group",Value="production-servers"
    
    # Verify both instances are tagged
    aws ec2 describe-instances \
      --filters "Name=tag:Patch Group,Values=production-servers" \
      --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
      --output table

Task 2 — Create Custom Patch Baseline:

    Console
    Systems Manager → Patch Manager → Patch Baselines → Create patch baseline
    
      Basic Settings:
        Name:        production-ubuntu-baseline
        Description: Ubuntu production servers patch rules
        OS:          Ubuntu
    
      Approval Rules:
    
        Rule 1 — Critical patches:
          Products:         Ubuntu20.04, Ubuntu22.04
          Classification:   Security
          Severity:         Critical
          Auto-approval:    7 days
          Compliance level: Critical
    
        Rule 2 — Important patches:
          Products:         Ubuntu20.04, Ubuntu22.04
          Classification:   Security
          Severity:         Important
          Auto-approval:    14 days
          Compliance level: High
    
      → Create patch baseline
    Save the Baseline ID
    bashBASELINE_ID=$(aws ssm describe-patch-baselines \
      --filters "Key=NAME_PREFIX,Values=production-ubuntu-baseline" \
      --query 'BaselineIdentities[0].BaselineId' \
      --output text)
    echo "Baseline ID: $BASELINE_ID"

Task 3 — Create Maintenance Window:
    
    Console
    Systems Manager → Maintenance Windows → Create maintenance window
    
      Name:        production-patch-window
      Description: Weekly patching for production servers
    
      Schedule:
        CRON/Rate expression: cron(0 2 ? * SUN *)
        (Every Sunday at 2:00 AM UTC)
    
      Duration:           2 hours
      Stop initiating:    1 hour (cutoff — no new tasks after 1 hour)
      Allow unregistered: No
    
    → Create maintenance window

    Save Window ID
    bashWINDOW_ID=$(aws ssm describe-maintenance-windows \
      --filters "Key=Name,Values=production-patch-window" \
      --query 'WindowIdentities[0].WindowId' \
      --output text)
    echo "Window ID: $WINDOW_ID"

    Register Targets (Console)

    production-patch-window → Targets → Register target
    
      Target name:  production-servers-target
      Description:  Production patch group instances
    
      Targets:
        Specify instance tags
        Tag key:   Patch Group
        Tag value: production-servers
        → Add

    → Register target

    Register Patching Task (Console)
    
    production-patch-window → Tasks → Register tasks → Register Run Command task
    
      Name:               weekly-patch-task
      Command document:   AWS-RunPatchBaseline
      Targets:            production-servers-target
      Concurrency:        50 percent
      Error threshold:    25 percent
      IAM service role:   AWSSystemsManagerDefaultEC2InstanceManagementRole
      Parameters:
        Operation:    Install
        RebootOption: RebootIfNeeded
      Priority:       1
    
    → Register Run Command task

Task 4 — Manual Patching Run (Test):
    
    Patch now (Console)
    Patch Manager → Patch now
    
      Patching operation: Install
      Instances to patch: Patch groups
      Patch group:        production-servers
      Reboot option:      Reboot if needed

    → Patch now

    Scan only (CLI)
    bashaws ssm send-command \
      --document-name "AWS-RunPatchBaseline" \
      --targets "Key=tag:Patch Group,Values=production-servers" \
      --parameters 'Operation=Scan' \
      --comment "Compliance scan — no install" \
      --region your-region
    # Operation=Scan checks for missing patches without installing anything

Task 5 — Monitor Compliance:

    Console
    Patch Manager → Compliance reporting
    
    Shows per-instance status:
      web-server-01  Compliant    Missing: 0
      web-server-02  Compliant    Missing: 0

    CloudWatch Alarm for Non-Compliance

