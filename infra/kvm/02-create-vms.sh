#!/usr/bin/env bash
# 02-create-vms.sh — Tạo 3 VM Debian (cp1, worker1, worker2) bằng NET-INSTALL.
# virt-install tự tải kernel+initrd Debian và cài tự động qua preseed.
# (Đã bỏ cloud image genericcloud vì gây kẹt boot trên máy này.)
# Sau khi VM cài xong + reboot, chạy 05-prepare-nodes.sh để cài containerd + kubeadm.
set -euo pipefail

# ============================ CẤU HÌNH ============================
VM_RAM_MB=3072            # 3GB / VM  (3 VM = 9GB)
VM_VCPUS=2               # 2 vCPU / VM
VM_DISK_GB=20            # disk ảo mỗi VM
NODES=(cp1 worker1 worker2)

# Nguồn net-install Debian 13 (trixie). virt-install tải kernel/initrd từ đây.
# deb.debian.org là CDN toàn cầu (ổn định); đổi sang mirror JP nếu muốn nhanh hơn:
#   https://ftp.jp.debian.org/debian/dists/trixie/main/installer-amd64/
INSTALL_LOCATION="https://deb.debian.org/debian/dists/trixie/main/installer-amd64/"

POOL_DIR="/var/lib/libvirt/images"

# Khi chạy dưới 'sudo', $HOME thành /root. Suy ra home thật của người gọi sudo.
CALLER_HOME="$HOME"
if [ -n "${SUDO_USER:-}" ]; then
  CALLER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$CALLER_HOME/.ssh/id_ed25519.pub}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESEED_TMPL="${SCRIPT_DIR}/preseed/preseed.cfg.tmpl"
# =================================================================

command -v virt-install >/dev/null || { echo "Thiếu virt-install. Chạy ./01-prereqs.sh trước."; exit 1; }
[ -f "$SSH_PUBKEY_FILE" ] || { echo "Không thấy SSH public key: $SSH_PUBKEY_FILE"; exit 1; }
[ -f "$PRESEED_TMPL" ]    || { echo "Không thấy preseed template: $PRESEED_TMPL"; exit 1; }
SSH_PUBKEY="$(cat "$SSH_PUBKEY_FILE")"

for NODE in "${NODES[@]}"; do
  echo
  echo "======================================================================"
  echo "==> Tạo $NODE (net-install, ${VM_RAM_MB}MB RAM, ${VM_VCPUS} vCPU)"
  echo "======================================================================"
  DISK="${POOL_DIR}/${NODE}.qcow2"

  # Đĩa trống — installer sẽ phân vùng + cài Debian lên đây
  sudo qemu-img create -f qcow2 "$DISK" "${VM_DISK_GB}G" >/dev/null

  # Sinh preseed riêng cho node (thay hostname + SSH key)
  PRESEED="/tmp/${NODE}-preseed.cfg"
  sed -e "s|{{HOSTNAME}}|${NODE}|g" \
      -e "s|{{SSH_PUBKEY}}|${SSH_PUBKEY}|g" \
      "$PRESEED_TMPL" > "$PRESEED"
  sudo cp "$PRESEED" "/var/lib/libvirt/images/${NODE}-preseed.cfg"

  # virt-install với --location (net-install) + --initrd-inject (nhét preseed vào initrd)
  # + console kernel để xem log cài đặt.
  sudo virt-install \
    --name "$NODE" \
    --memory "$VM_RAM_MB" \
    --vcpus "$VM_VCPUS" \
    --cpu host-passthrough \
    --disk path="$DISK",format=qcow2,bus=virtio \
    --os-variant debian13 \
    --network network=default,model=virtio \
    --graphics none \
    --location "$INSTALL_LOCATION" \
    --initrd-inject "$PRESEED" \
    --extra-args "auto=true priority=critical preseed/file=/${NODE}-preseed.cfg console=ttyS0,115200n8 serial" \
    --noautoconsole

  rm -f "$PRESEED"
done

echo
echo "==> Cả 3 VM đang CÀI ĐẶT (net-install, mất ~5-15 phút/VM tùy mạng)."
echo "    Theo dõi cài đặt trực tiếp:  sudo virsh console cp1   (thoát: Ctrl+])"
echo "    Xem trạng thái:              sudo virsh list --all"
echo
echo "Khi cài xong VM sẽ TỰ REBOOT vào hệ thống. Sau đó:"
echo "    ./04-show-ips.sh            # lấy IP"
echo "    ./05-prepare-nodes.sh      # cài containerd + kubeadm lên cả 3 node qua SSH"
