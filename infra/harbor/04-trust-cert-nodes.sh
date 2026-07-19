#!/usr/bin/env bash
# 04-trust-cert-nodes.sh — Cho CẢ 3 NODE tin cert tự ký của Harbor + phân giải harbor.local.
#
# CHẠY TRÊN HOST KVM (nơi có `sudo virsh`), giống 05-prepare-nodes.sh — nó SSH sang 3 node.
# Cần: đã sinh cert (./02-gen-cert.sh) => có certs/ca.crt và certs/harbor.local.crt.
#
# Vì sao BẮT BUỘC bước này:
#  Harbor dùng cert TỰ KÝ. containerd (runtime kéo image cho kubelet) mặc định KHÔNG tin
#  cert đó -> pod báo `x509: certificate signed by unknown authority` khi ImagePull.
#  Cách chuẩn của containerd hiện đại là "certs.d": tạo
#    /etc/containerd/certs.d/<host:port>/hosts.toml  trỏ tới cert CA.
#  Đồng thời client phải phân giải harbor.local -> IP node (thêm vào /etc/hosts).
set -euo pipefail

NODES=(cp1 worker1 worker2)
HARBOR_HOST="${HARBOR_HOST:-harbor.local}"
HARBOR_PORT="${HARBOR_PORT:-30443}"   # khớp NodePort HTTPS của ingress (script 01)
CERT_DIR="$(cd "$(dirname "$0")" && pwd)/certs"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

if [ ! -f "${CERT_DIR}/ca.crt" ]; then
  echo "!! Không thấy ${CERT_DIR}/ca.crt — chạy ./02-gen-cert.sh trước."
  exit 1
fi

# Lấy IP của cp1 để trỏ harbor.local vào đó (ingress chạy trên mọi node qua NodePort,
# nhưng ta chọn 1 IP ổn định — dùng cp1).
CP1_IP=$(sudo virsh net-dhcp-leases default 2>/dev/null \
          | grep -w "cp1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [ -z "$CP1_IP" ]; then
  echo "!! Không lấy được IP cp1 từ virsh. Chạy infra/kvm/04-show-ips.sh để kiểm tra."
  exit 1
fi
echo "==> harbor.local sẽ trỏ tới cp1 = ${CP1_IP}"

# Nội dung hosts.toml cho certs.d (dùng ca.crt làm CA tin cậy).
read -r -d '' HOSTS_TOML <<EOF || true
server = "https://${HARBOR_HOST}:${HARBOR_PORT}"

[host."https://${HARBOR_HOST}:${HARBOR_PORT}"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/${HARBOR_HOST}:${HARBOR_PORT}/ca.crt"
EOF

CA_CONTENT=$(cat "${CERT_DIR}/ca.crt")

for NODE in "${NODES[@]}"; do
  IP=$(sudo virsh net-dhcp-leases default 2>/dev/null \
        | grep -w "$NODE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
  if [ -z "$IP" ]; then
    echo "!! Không lấy được IP của $NODE — bỏ qua."
    continue
  fi
  echo
  echo "==================== $NODE ($IP) ===================="

  # Script chạy bên trong node. Truyền CA + IP cp1 + hosts.toml qua biến môi trường.
  # Đặt `set +e` quanh ssh để 1 node lỗi không giết cả vòng lặp (set -e ở đầu file).
  set +e
  ssh $SSH_OPTS "debian@${IP}" \
      "HARBOR_HOST='${HARBOR_HOST}' HARBOR_PORT='${HARBOR_PORT}' CP1_IP='${CP1_IP}' \
       CA_CONTENT='${CA_CONTENT}' HOSTS_TOML='${HOSTS_TOML}' bash -s" <<'REMOTE'
set -euo pipefail
CERTS_D="/etc/containerd/certs.d/${HARBOR_HOST}:${HARBOR_PORT}"

# 1) certs.d cho containerd
sudo mkdir -p "$CERTS_D"
echo "$CA_CONTENT"  | sudo tee "${CERTS_D}/ca.crt"      >/dev/null
echo "$HOSTS_TOML"  | sudo tee "${CERTS_D}/hosts.toml"  >/dev/null

# 2) Bật config_path cho containerd (nếu chưa) — để nó ĐỌC thư mục certs.d.
#    containerd mặc định KHÔNG bật; phải trỏ config_path = "/etc/containerd/certs.d".
if ! grep -q 'config_path = "/etc/containerd/certs.d"' /etc/containerd/config.toml; then
  sudo sed -ri 's#(\[plugins."io.containerd.grpc.v1.cri".registry\])#\1\n        config_path = "/etc/containerd/certs.d"#' /etc/containerd/config.toml
  # Nếu sed không khớp (layout config khác), báo để sửa tay.
  grep -q 'config_path = "/etc/containerd/certs.d"' /etc/containerd/config.toml \
    || echo "!! [${HOSTNAME}] Chưa chèn được config_path — kiểm tra /etc/containerd/config.toml thủ công."
  sudo systemctl restart containerd
fi

# 3) /etc/hosts: harbor.local -> cp1 (idempotent)
sudo sed -ri "/[[:space:]]${HARBOR_HOST}\$/d" /etc/hosts
echo "${CP1_IP} ${HARBOR_HOST}" | sudo tee -a /etc/hosts >/dev/null

echo "[${HOSTNAME}] OK: certs.d + hosts.toml + /etc/hosts (${HARBOR_HOST} -> ${CP1_IP})"
REMOTE
  [ $? -ne 0 ] && echo "!! Lỗi khi cấu hình $NODE (xem log SSH ở trên)."
  set -e
done

echo
echo "==> XONG cả 3 node. Kiểm tra nhanh trên 1 worker:"
echo "    ssh debian@<IP-worker> 'ls /etc/containerd/certs.d/${HARBOR_HOST}:${HARBOR_PORT}/ && getent hosts ${HARBOR_HOST}'"
echo
echo "Tiếp theo: ./05-test-login-push.sh  (docker login + push image thử)"
