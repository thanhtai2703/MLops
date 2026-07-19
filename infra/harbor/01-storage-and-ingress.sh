#!/usr/bin/env bash
# 01-storage-and-ingress.sh — Cài local-path-provisioner (StorageClass mặc định)
# + ingress-nginx (Service NodePort) lên cluster kubeadm.
#
# CHẠY TRÊN cp1 (nơi có kubectl trỏ tới cluster). Idempotent — chạy lại không hỏng.
#
# Vì sao 2 thứ này TRƯỚC Harbor:
#  - Harbor cần PersistentVolume (registry, database, redis...). kubeadm KHÔNG có
#    StorageClass mặc định -> PVC sẽ Pending mãi. local-path-provisioner cấp PV
#    từ đĩa local của node, đủ dùng cho lab.
#  - Ta expose Harbor qua Ingress (hostname harbor.local). Cần một Ingress Controller.
#    kubeadm không có LoadBalancer -> ingress-nginx chạy kiểu NodePort.
set -euo pipefail

LOCAL_PATH_VERSION="v0.0.30"
INGRESS_NGINX_VERSION="controller-v1.11.3"
# NodePort cố định cho HTTPS của ingress (mặc định NodePort ngẫu nhiên 30000-32767;
# ta ghim 30443 cho dễ nhớ + khớp doc/test).
INGRESS_HTTPS_NODEPORT=30443
INGRESS_HTTP_NODEPORT=30080

echo "==> [1/3] Cài local-path-provisioner ${LOCAL_PATH_VERSION}..."
kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_VERSION}/deploy/local-path-storage.yaml"

echo "==> [2/3] Đặt local-path làm StorageClass MẶC ĐỊNH..."
# Nếu không đặt default, Harbor chart phải khai báo storageClass rõ ràng ở mọi PVC.
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "==> [3/3] Cài ingress-nginx ${INGRESS_NGINX_VERSION} (kiểu NodePort)..."
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/baremetal/deploy.yaml"

echo "==> Ghim NodePort cho ingress (http=${INGRESS_HTTP_NODEPORT}, https=${INGRESS_HTTPS_NODEPORT})..."
# Chờ Service tồn tại rồi mới patch (apply ở trên là async).
for i in $(seq 1 30); do
  kubectl get svc ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1 && break
  sleep 2
done
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p="[
  {\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":${INGRESS_HTTP_NODEPORT}},
  {\"op\":\"replace\",\"path\":\"/spec/ports/1/nodePort\",\"value\":${INGRESS_HTTPS_NODEPORT}}
]" || echo "!! Patch NodePort lỗi — có thể port đã dùng. Kiểm tra: kubectl get svc -n ingress-nginx"

echo
echo "==> Đợi ingress-nginx controller sẵn sàng (tối đa ~120s)..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || echo "!! Controller chưa Ready — kiểm tra: kubectl get pods -n ingress-nginx"

echo
echo "==> XONG. Kiểm tra:"
echo "    kubectl get storageclass          # local-path (default)"
echo "    kubectl get pods -n ingress-nginx # controller Running"
echo "    kubectl get svc  -n ingress-nginx ingress-nginx-controller  # NodePort ${INGRESS_HTTP_NODEPORT}/${INGRESS_HTTPS_NODEPORT}"
echo
echo "Tiếp theo: ./02-gen-cert.sh  (sinh cert tự ký cho harbor.local)"
