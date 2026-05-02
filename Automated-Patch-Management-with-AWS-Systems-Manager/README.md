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

