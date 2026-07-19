#!/usr/bin/env bash
# 05-test-login-push.sh — Test docker login + push 1 image nhỏ lên Harbor.
#
# CHẠY TRÊN MÁY CÓ DOCKER (máy dev host, hoặc cp1 nếu đã cài docker).
# Nó tự lo phần "docker tin cert tự ký" (docker dùng /etc/docker/certs.d, KHÁC containerd).
#
# Cần: đã cài Harbor (03) và có certs/ca.crt (từ 02) copy về máy này.
set -euo pipefail

HARBOR_HOST="${HARBOR_HOST:-harbor.local}"
HARBOR_PORT="${HARBOR_PORT:-30443}"
HARBOR_ADDR="${HARBOR_HOST}:${HARBOR_PORT}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PW="${HARBOR_PW:-Harbor12345}"
HARBOR_PROJECT="${HARBOR_PROJECT:-library}"   # 'library' là project public sẵn có
NODE_IP="${NODE_IP:-}"                          # IP node để trỏ harbor.local (bắt buộc nếu máy này chưa có /etc/hosts)
CERT_DIR="$(cd "$(dirname "$0")" && pwd)/certs"

echo "==> [1/4] Đảm bảo phân giải ${HARBOR_HOST} + docker tin cert..."
if ! getent hosts "$HARBOR_HOST" >/dev/null; then
  if [ -z "$NODE_IP" ]; then
    echo "!! ${HARBOR_HOST} chưa phân giải được. Đặt NODE_IP=<IP-cp1> rồi chạy lại, ví dụ:"
    echo "     NODE_IP=192.168.122.126 ./05-test-login-push.sh"
    exit 1
  fi
  echo "   + Thêm ${NODE_IP} ${HARBOR_HOST} vào /etc/hosts"
  sudo sed -ri "/[[:space:]]${HARBOR_HOST}\$/d" /etc/hosts
  echo "${NODE_IP} ${HARBOR_HOST}" | sudo tee -a /etc/hosts >/dev/null
fi

# docker dùng /etc/docker/certs.d/<host:port>/ca.crt (đuôi .crt vẫn ok cho CA).
DOCKER_CERTS_D="/etc/docker/certs.d/${HARBOR_ADDR}"
if [ -f "${CERT_DIR}/ca.crt" ]; then
  sudo mkdir -p "$DOCKER_CERTS_D"
  sudo cp "${CERT_DIR}/ca.crt" "${DOCKER_CERTS_D}/ca.crt"
  echo "   + Đã copy ca.crt vào ${DOCKER_CERTS_D}"
else
  echo "!! Không thấy ${CERT_DIR}/ca.crt — copy thư mục certs/ từ cp1 về máy này trước."
  exit 1
fi

echo "==> [2/4] docker login ${HARBOR_ADDR}..."
echo "$HARBOR_PW" | docker login "$HARBOR_ADDR" -u "$HARBOR_USER" --password-stdin

echo "==> [3/4] Kéo image nhỏ, tag theo Harbor, push..."
TEST_IMG="hello-world:latest"
TARGET="${HARBOR_ADDR}/${HARBOR_PROJECT}/hello-world:test"
docker pull "$TEST_IMG"
docker tag  "$TEST_IMG" "$TARGET"
docker push "$TARGET"

echo "==> [4/4] Xác nhận pull lại được..."
docker rmi "$TARGET" >/dev/null 2>&1 || true
docker pull "$TARGET"

echo
echo "==> XONG. Đã push + pull thành công: ${TARGET}"
echo "   Mở UI kiểm tra: https://${HARBOR_ADDR}  (bỏ qua cảnh báo cert tự ký trên trình duyệt)"
echo "   Project: ${HARBOR_PROJECT} -> repo hello-world"
echo
echo "Giờ image gateway của bạn (phase-1 § 1.2) push cùng cách:"
echo "   docker build -t ${HARBOR_ADDR}/llmops/llm-gateway:dev gateway/"
echo "   docker push  ${HARBOR_ADDR}/llmops/llm-gateway:dev"
echo "   (tạo project 'llmops' trong Harbor UI trước, hoặc để public)"
