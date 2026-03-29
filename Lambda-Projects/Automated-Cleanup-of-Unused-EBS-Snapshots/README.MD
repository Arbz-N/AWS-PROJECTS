**_AWS Lambda – Automated Cleanup of Unused EBS Snapshots_**

    This project provides an AWS Lambda function written in Python 
    that automatically identifies and deletes unused or orphaned EBS snapshots in your AWS account.
    The Lambda function helps reduce unnecessary storage costs by cleaning up:
    
    Snapshots with no associated volume
    Snapshots whose volumes are not attached to any running EC2 instance
    Snapshots whose associated volumes no longer exist
    
    This is a cost-optimization and housekeeping automation commonly used in real-world AWS environments.

**How It Works**

The Lambda function performs the following steps:

    Fetches all EBS snapshots owned by the AWS account
    Retrieves all running EC2 instances
    Collects the Instance IDs of running instances
    Iterates through each snapshot and:
    Deletes it if VolumeId is missing
    Deletes it if the volume exists but is not attached
    Deletes it if the associated volume does not exist
    Keeps snapshots that are still in use


****Prerequisites****

Before deploying this project, ensure you have:

An AWS account
Basic understanding of:

    AWS EC2
    EBS volumes & snapshots
    AWS Lambda
    AWS IAM role with required permissions
    Python 3.9 or later (Lambda runtime)

**Required IAM Permissions**

Attach the following permissions to the Lambda execution role:

    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ec2:DescribeSnapshots",  #for describe snapshots
            "ec2:DescribeInstances",  #for descirbe instances
            "ec2:DescribeVolumes",    #for describe volumes 
            "ec2:DeleteSnapshot"      #for delete snapshot
          ],
          "Resource": "*"
        }
      ]
    }


**Important:**
Grant only minimum permissions (least privilege principle).

**Deployment Steps**

**1- Create Lambda Function**

    Go to AWS Lambda Console
    Create a new function
    Runtime: Python 3.9+

Attach the IAM role with permissions

**2- Upload Code**

    Paste the code into lambda_function.py
    Deploy the function

**3- Test the Function**

    Use a simple test event:
    Check CloudWatch Logs to see which snapshots were deleted.

**(Optional) Automate with EventBridge**

    You can run this Lambda automatically:

    Daily
    Weekly
    Monthly

    Using Amazon EventBridge (CloudWatch Events) with a cron schedule.

**Important Warnings**

  - This Lambda permanently deletes EBS snapshots
  - Deleted snapshots cannot be recovered
  - Always test in non-production accounts first

**Best** practice:

  - Tag critical snapshots (e.g. DoNotDelete=true)
  - Modify the code to skip tagged snapshots if needed

**Benefits**

  - Reduces AWS storage cost
  - Removes orphaned resources
  - Improves AWS account hygiene
  - Fully serverless & automated


**Cleanup (If Created for Practice)**

    If you created this setup only for learning:
    Delete the Lambda function
    Remove the IAM role
    Disable EventBridge rules
    This avoids unnecessary AWS charges.