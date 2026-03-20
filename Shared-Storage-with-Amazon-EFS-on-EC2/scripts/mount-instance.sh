#!/bin/bash
# =============================================
# EFS Mount Script
# Run on: EC2 Ubuntu instance
# Usage: EFS_DNS="fs-xxx.efs.us-east-1.amazonaws.com" bash mount-instance.sh
# =============================================

if [ -z "$EFS_DNS" ]; then
    echo "ERROR: Set EFS_DNS before running"
    echo "export EFS_DNS=fs-xxx.efs.us-east-1.amazonaws.com"
    exit 1
fi

echo "=== EFS Mount Setup ==="
echo "EFS DNS: $EFS_DNS"

# ─── Connectivity Check ───
echo ""
echo "--- Connectivity Check ---"
echo "DNS check:"
nslookup $EFS_DNS
echo ""
echo "Port 2049 check:"
nc -zv $EFS_DNS 2049 -w 5
if [ $? -ne 0 ]; then
    echo "ERROR: Port 2049 blocked — check Security Group!"
    exit 1
fi
echo "Connectivity OK "

# ─── Install nfs-common ───
echo ""
echo "--- Installing nfs-common ---"
sudo apt-get install -y nfs-common
echo "nfs-common installed ✅"

# ─── Mount ───
sudo mkdir -p /mnt/efs
sudo mount -t nfs4 -o nfsvers=4.1 $EFS_DNS:/ /mnt/efs

if ! df -h /mnt/efs | grep -q efs; then
    echo "ERROR: EFS mount failed!"
    exit 1
fi

echo "EFS mounted "
df -h /mnt/efs

# ─── Ownership ───
sudo chown $(whoami):$(whoami) /mnt/efs
sudo chmod 755 /mnt/efs

# ─── Write test ───
echo "Mount test - $(date)" > /mnt/efs/test.txt
cat /mnt/efs/test.txt
echo "Write test passed "

# ─── fstab (persistent mount) ───
echo ""
echo "--- Adding to fstab ---"
sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)
echo "${EFS_DNS}:/ /mnt/efs nfs4 nfsvers=4.1,_netdev 0 0" | sudo tee -a /etc/fstab
echo "fstab updated "

echo ""
echo "=== Mount Complete ==="
echo "EFS is available at: /mnt/efs"