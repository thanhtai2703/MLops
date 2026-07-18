#!/usr/bin/env bash
# 04-show-ips.sh — Hiển thị IP các VM và gợi ý lệnh SSH.
# VM được tạo trong libvirt SYSTEM session (qemu:///system) vì chạy bằng sudo,
# nên mọi lệnh virsh ở đây đều dùng 'sudo virsh' để nhìn đúng không gian đó.
set -euo pipefail
NODES=(cp1 worker1 worker2)
VIRSH="sudo virsh"

echo "==> DHCP leases trên network 'default':"
$VIRSH net-dhcp-leases default

echo
echo "==> IP theo từng node + trạng thái node-ready:"
for NODE in "${NODES[@]}"; do
  # Lấy IP qua guest agent nếu có, fallback sang lease theo tên
  IP=$($VIRSH domifaddr "$NODE" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -n1)
  [ -z "$IP" ] && IP=$($VIRSH net-dhcp-leases default 2>/dev/null | awk -v n="$NODE" '$0 ~ n {print $5}' | cut -d/ -f1 | head -n1)
  printf "  %-10s %s\n" "$NODE" "${IP:-<chưa có IP, đợi thêm>}"
  if [ -n "${IP:-}" ]; then
    printf "     ssh debian@%s\n" "$IP"
  fi
done

echo
echo "Kiểm tra 1 node đã chuẩn bị xong chưa (file mốc do cloud-init tạo):"
echo "  ssh debian@<IP-cp1> 'ls -l /var/lib/cloud/kubeadm-node-ready && kubeadm version'"
