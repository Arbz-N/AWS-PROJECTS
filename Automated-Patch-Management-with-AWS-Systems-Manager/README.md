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


