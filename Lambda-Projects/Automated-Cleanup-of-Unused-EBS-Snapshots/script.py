import boto3

# AWS_Projects Clients
ec2_client = boto3.client('ec2')


OWNER_ID = '<your-aws-account-id>'  # Replace with your AWS_Projects account ID
DRY_RUN = False  # Set to True for testing without deleting snapshots

# Lambda-Projects Handler

def lambda_handler(event, context):
    """
    Lambda-Projects function to clean up unused EBS snapshots.
    Deletes snapshots if:
      1. Snapshot has no VolumeId
      2. Volume exists but is not attached
      3. Volume no longer exists
    """

    # 1 Get all snapshots owned by account
    snapshots = ec2_client.describe_snapshots(OwnerIds=[OWNER_ID])['Snapshots']

    # 2 Get all running EC2 instances
    instances = ec2_client.describe_instances(
        Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
    )
    active_instance_ids = {
        instance['InstanceId']
        for reservation in instances['Reservations']
        for instance in reservation['Instances']
    }

    # 3 Iterate snapshots
    for snapshot in snapshots:
        snapshot_id = snapshot['SnapshotId']
        volume_id = snapshot.get('VolumeId')

        # Case 1: Snapshot has no associated volume
        if not volume_id:
            if not DRY_RUN:
                ec2_client.delete_snapshot(SnapshotId=snapshot_id)
            print(f"[INFO] Deleted orphaned snapshot {snapshot_id} (no VolumeId).")
            continue

        # Case 2 & 3: Volume exists
        try:
            volume = ec2_client.describe_volumes(VolumeIds=[volume_id])['Volumes'][0]
            attachments = volume.get('Attachments', [])

            # Volume exists but not attached
            if not attachments:
                if not DRY_RUN:
                    ec2_client.delete_snapshot(SnapshotId=snapshot_id)
                print(f"[INFO] Deleted snapshot {snapshot_id} (volume {volume_id} not attached).")

        # Case 3: Volume does not exist
        except ec2_client.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'InvalidVolume.NotFound':
                if not DRY_RUN:
                    ec2_client.delete_snapshot(SnapshotId=snapshot_id)
                print(f"[INFO] Deleted snapshot {snapshot_id} (volume {volume_id} not found).")

    print("[INFO] Snapshot cleanup completed.")
