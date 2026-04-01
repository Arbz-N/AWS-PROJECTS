import boto3
from datetime import datetime

# ─────────────────────────────────────────────
# CONFIG — update these values before deploying
# ─────────────────────────────────────────────
DB_INSTANCE_IDENTIFIER = "my-postgres-db"


def lambda_handler(event, context):
    rds = boto3.client('rds')

    # Generate a unique snapshot name using the current date
    date_str            = datetime.utcnow().strftime('%Y-%m-%d-%H%M')
    snapshot_identifier = f"{DB_INSTANCE_IDENTIFIER}-snapshot-{date_str}"

    try:
        response = rds.create_db_snapshot(
            DBSnapshotIdentifier=snapshot_identifier,
            DBInstanceIdentifier=DB_INSTANCE_IDENTIFIER
        )

        snapshot_id = response['DBSnapshot']['DBSnapshotIdentifier']
        print(f"Snapshot created: {snapshot_id}")

        return {
            'statusCode': 200,
            'body': f"Snapshot created: {snapshot_id}"
        }

    except Exception as e:
        print(f"Error creating snapshot: {e}")
        return {
            'statusCode': 500,
            'body': f"Error creating snapshot: {str(e)}"
        }