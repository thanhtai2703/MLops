#!/usr/bin/env bash
# 01-prereqs.sh — Cài công cụ và cấu hình libvirt (network + storage pool) trên host Debian.
# Chạy MỘT LẦN trước khi tạo VM. An toàn khi chạy lại (idempotent).
set -euo pipefail

echo "==> [1/3] Cài công cụ ảo hóa còn thiếu"
# virtinst   : cung cấp virt-install
# cloud-image-utils : cung cấp cloud-localds (đóng gói cloud-init thành seed ISO)
# libguestfs-tools  : cung cấp virt-customize / virt-sysprep (tùy chọn, tiện gỡ rối image)
sudo apt-get update
sudo apt-get install -y \
  virtinst \
  cloud-image-utils \
  libguestfs-tools \
  qemu-utils \
  genisoimage

echo "==> [2/3] Tạo & bật libvirt network 'default' (NAT, dải 192.168.122.0/24)"
if ! virsh net-info default >/dev/null 2>&1; then
  # Định nghĩa network NAT mặc định của libvirt.
  cat >/tmp/libvirt-default-net.xml <<'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
  virsh net-define /tmp/libvirt-default-net.xml
  rm -f /tmp/libvirt-default-net.xml
fi
virsh net-autostart default
virsh net-start default 2>/dev/null || echo "    (network 'default' đã chạy)"

echo "==> [3/3] Tạo & bật storage pool 'default' -> /var/lib/libvirt/images"
if ! virsh pool-info default >/dev/null 2>&1; then
  virsh pool-define-as default dir --target /var/lib/libvirt/images
fi
virsh pool-autostart default
virsh pool-start default 2>/dev/null || echo "    (pool 'default' đã chạy)"

echo
echo "==> Xong. Kiểm tra:"
virsh net-list --all
virsh pool-list --all
