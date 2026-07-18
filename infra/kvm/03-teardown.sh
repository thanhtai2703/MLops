#!/usr/bin/env bash
# 03-teardown.sh — Xóa sạch 3 VM và disk/preseed để dựng lại từ đầu.
set -euo pipefail
NODES=(cp1 worker1 worker2)
POOL_DIR="/var/lib/libvirt/images"

# VM nằm trong libvirt system session (tạo bằng sudo) — dùng 'sudo virsh'.
for NODE in "${NODES[@]}"; do
  echo "==> Xóa VM $NODE"
  sudo virsh destroy "$NODE" 2>/dev/null || true       # tắt cứng nếu đang chạy
  sudo virsh undefine "$NODE" --nvram 2>/dev/null || true
  sudo rm -f "${POOL_DIR}/${NODE}.qcow2" \
             "${POOL_DIR}/${NODE}-seed.iso" \
             "${POOL_DIR}/${NODE}-preseed.cfg"
done

echo "==> Còn lại:"
sudo virsh list --all
