#!/usr/bin/env bash
# 03-install-harbor.sh — helm install Harbor với TLS tự ký + expose qua ingress-nginx.
#
# CHẠY TRÊN cp1. Cần đã chạy 01 (storage+ingress) và 02 (sinh cert) trước.
# Idempotent: dùng `helm upgrade --install`.
#
# Luồng: client -> ingress-nginx (NodePort 30443, TLS harbor.local) -> Service Harbor.
# Harbor chart tự tạo Ingress object; ta nhét cert tự ký vào 1 Secret TLS và trỏ chart tới đó.
set -euo pipefail

HARBOR_HOST="${HARBOR_HOST:-harbor.local}"
HARBOR_NS="${HARBOR_NS:-harbor}"
HARBOR_ADMIN_PW="${HARBOR_ADMIN_PW:-Harbor12345}"   # ĐỔI khi lên thật
HARBOR_CHART_VERSION="${HARBOR_CHART_VERSION:-1.15.1}"  # app Harbor v2.11.x
CERT_DIR="$(cd "$(dirname "$0")" && pwd)/certs"

if [ ! -f "${CERT_DIR}/${HARBOR_HOST}.crt" ]; then
  echo "!! Chưa thấy cert ${CERT_DIR}/${HARBOR_HOST}.crt — chạy ./02-gen-cert.sh trước."
  exit 1
fi

echo "==> [1/4] Thêm helm repo harbor + tạo namespace ${HARBOR_NS}..."
helm repo add harbor https://helm.goharbor.io >/dev/null 2>&1 || true
helm repo update harbor >/dev/null
kubectl create namespace "$HARBOR_NS" --dry-run=client -o yaml | kubectl apply -f -

echo "==> [2/4] Nạp cert tự ký thành Secret TLS 'harbor-tls' trong ns ${HARBOR_NS}..."
# Ingress dùng secret này để phục vụ HTTPS cho harbor.local.
kubectl create secret tls harbor-tls \
  --cert="${CERT_DIR}/${HARBOR_HOST}.crt" \
  --key="${CERT_DIR}/${HARBOR_HOST}.key" \
  -n "$HARBOR_NS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> [3/4] helm upgrade --install harbor (chart ${HARBOR_CHART_VERSION})..."
# Giải thích các value quan trọng:
#  expose.type=ingress + ingress.className=nginx  -> đi qua ingress-nginx đã cài.
#  expose.tls.certSource=secret + secretName=harbor-tls -> dùng cert tự ký của ta.
#  externalURL=https://harbor.local:30443 -> URL client thấy (kèm NodePort HTTPS của ingress).
#    QUAN TRỌNG: externalURL phải chứa cổng NodePort, nếu không Harbor sinh redirect sai cổng.
#  persistence.* -> để trống storageClass => dùng StorageClass mặc định (local-path).
helm upgrade --install harbor harbor/harbor \
  --version "$HARBOR_CHART_VERSION" \
  --namespace "$HARBOR_NS" \
  --set expose.type=ingress \
  --set expose.tls.enabled=true \
  --set expose.tls.certSource=secret \
  --set expose.tls.secret.secretName=harbor-tls \
  --set expose.ingress.hosts.core="${HARBOR_HOST}" \
  --set expose.ingress.className=nginx \
  --set "expose.ingress.annotations.ingress\.kubernetes\.io/ssl-redirect=true" \
  --set externalURL="https://${HARBOR_HOST}:30443" \
  --set harborAdminPassword="${HARBOR_ADMIN_PW}" \
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.registry.size=10Gi \
  --set persistence.persistentVolumeClaim.database.size=2Gi \
  --set persistence.persistentVolumeClaim.redis.size=1Gi \
  --set persistence.persistentVolumeClaim.jobservice.jobLog.size=1Gi \
  --set persistence.persistentVolumeClaim.trivy.size=2Gi \
  --set trivy.enabled=false \
  --set notary.enabled=false

echo
echo "==> [4/4] Đợi các pod Harbor Running (tối đa ~180s)..."
kubectl -n "$HARBOR_NS" wait --for=condition=ready pod \
  --selector=app=harbor --timeout=180s || \
  echo "!! Một số pod chưa Ready. Xem: kubectl get pods -n ${HARBOR_NS}"

echo
echo "==> XONG. Harbor:"
echo "    Namespace : ${HARBOR_NS}"
echo "    URL       : https://${HARBOR_HOST}:30443"
echo "    User/pass : admin / ${HARBOR_ADMIN_PW}"
echo
echo "Kiểm tra:  kubectl get pods,pvc,ingress -n ${HARBOR_NS}"
echo
echo "LƯU Ý: các node/máy client phải phân giải được '${HARBOR_HOST}' -> IP một node,"
echo "và tin cert tự ký (certs.d). Làm việc đó ở: ./04-trust-cert-nodes.sh"
