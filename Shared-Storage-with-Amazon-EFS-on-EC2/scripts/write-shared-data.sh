#!/bin/bash
# =============================================
# EFS Shared Data Test Script
# Run on: EC2 Instance 1 or Instance 2
# =============================================

INSTANCE_NAME=${1:-"Instance-1"}

echo "=== Writing shared data from $INSTANCE_NAME ==="

# Create directory structure
mkdir -p /mnt/efs/{shared,logs,configs,uploads}

# Shared config
if [ ! -f /mnt/efs/configs/app.conf ]; then
    cat << 'EOF' > /mnt/efs/configs/app.conf
# Shared Application Config
# Both EC2 instances see this file
DB_HOST=rds.us-east-1.amazonaws.com
DB_PORT=5432
APP_ENV=production
LOG_LEVEL=info
EOF
    echo "Config created "
else
    echo "$INSTANCE_NAME >> config" >> /mnt/efs/configs/app.conf
fi

# Log entry
echo "$(date) | $INSTANCE_NAME | Server started" >> /mnt/efs/logs/app.log
echo "$(date) | $INSTANCE_NAME | Config loaded"  >> /mnt/efs/logs/app.log

# Shared message
echo "Hello from $INSTANCE_NAME! Time: $(date)" >> /mnt/efs/shared/messages.txt

echo ""
echo "=== EFS Contents ==="
ls -lR /mnt/efs/

echo ""
echo "=== Shared Messages ==="
cat /mnt/efs/shared/messages.txt

echo ""
echo "=== App Log ==="
cat /mnt/efs/logs/app.log