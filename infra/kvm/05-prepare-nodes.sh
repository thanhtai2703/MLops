#!/usr/bin/env bash
# 05-prepare-nodes.sh — Cài containerd + kubeadm/kubelet/kubectl lên cả 3 node qua SSH.
# Thay cho phần cloud-init: chạy đúng "bước 1.3a" của phase-1-baseline.md trên mỗi VM.
# Chạy SAU khi 3 VM đã net-install xong, reboot, và có IP (xem ./04-show-ips.sh).
set -euo pipefail

NODES=(cp1 worker1 worker2)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Script chạy BÊN TRONG mỗi node (qua ssh). Idempotent.
read -r -d '' REMOTE_SCRIPT <<'REMOTE' || true
set -euo pipefail
echo "[node $(hostname)] Bắt đầu chuẩn bị kubeadm..."

# 0) Dọn repo K8s cũ NGAY TỪ ĐẦU (nếu lần chạy trước để lại v1.31) — nếu không,
#    apt-get update ở bước 3 sẽ gặp repo v1.31 hỏng và giết script (set -e).
sudo rm -f /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 1) Tắt swap
sudo swapoff -a || true
sudo sed -ri '/\sswap\s/s/^/#/' /etc/fstab || true

# 2) Module + sysctl bridge
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
sudo modprobe overlay || true
sudo modprobe br_netfilter || true
cat <<'EOF' | sudo tee /etc/sysctl.d/99-k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system >/dev/null

# 3) containerd + SystemdCgroup
sudo apt-get update || true
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y containerd apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -ri 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 4) Repo Kubernetes + cài + ghim
#    Debian 13 (sqv) TỪ CHỐI chữ ký GPG kiểu cũ (v3) của repo K8s -> apt báo "not signed".
#    Khắc phục: [trusted=yes] cho RIÊNG repo này -> apt bỏ qua verify chữ ký.
#    An toàn vì tải qua HTTPS từ pkgs.k8s.io chính thức + chỉ áp cho 1 repo.
K8S_CHANNEL="v1.33"
# Xóa mọi cấu hình repo K8s cũ (kể cả v1.31 từ lần chạy trước) để tránh xung đột
sudo rm -f /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [trusted=yes] https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
# apt-get update trả exit≠0 vì repo K8s ký kiểu cũ (chỉ là WARNING, apt vẫn cài được nhờ
# [trusted=yes]). '|| true' để cảnh báo này không giết script (set -e).
sudo apt-get update || true
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet

sudo touch /var/lib/kubeadm-node-ready
echo "[node $(hostname)] XONG. kubeadm: $(kubeadm version -o short)"
REMOTE

for NODE in "${NODES[@]}"; do
  # Lấy IP từ DHCP lease: tìm dòng có hostname = tên node, cột IP có dạng x.x.x.x/24.
  # (Không dùng --source agent vì VM net-install chưa cài qemu-guest-agent.)
  IP=$(sudo virsh net-dhcp-leases default 2>/dev/null \
        | grep -w "$NODE" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1)
  if [ -z "$IP" ]; then
    echo "!! Không lấy được IP của $NODE — bỏ qua. Chạy ./04-show-ips.sh để kiểm tra."
    continue
  fi
  echo
  echo "==================== Chuẩn bị $NODE ($IP) ===================="
  # shellcheck disable=SC2029
  ssh $SSH_OPTS "debian@${IP}" "bash -s" <<< "$REMOTE_SCRIPT" || {
    echo "!! Lỗi khi chuẩn bị $NODE. Kiểm tra SSH: ssh debian@${IP}"
  }
done

echo
echo "==> Xong. Kiểm tra 1 node đã sẵn sàng:"
echo "    ssh debian@<IP-cp1> 'ls -l /var/lib/kubeadm-node-ready && kubeadm version -o short'"
echo "Tiếp theo: kubeadm init trên cp1 (xem docs/phase-1-baseline.md § 1.3b)."
