#!/usr/bin/env bash
# 02-gen-cert.sh — Sinh chứng chỉ TLS TỰ KÝ cho hostname Harbor (mặc định harbor.local).
#
# CHẠY TRÊN cp1. Sinh ra thư mục ./certs/ gồm:
#   ca.crt / ca.key       — CA tự ký (dùng để nạp vào containerd tin cert Harbor)
#   harbor.crt / harbor.key — cert server cho harbor.local, KÝ BỞI ca ở trên
#   harbor.local.cert     — bản .cert cho docker/certs.d (docker cần đuôi .cert)
#
# Vì sao tự ký CA riêng thay vì 1 self-signed cert đơn?
#  - Có CA -> ta chỉ cần cho containerd/docker tin CA (ca.crt), sạch hơn.
#  - Cert server BẮT BUỘC có SAN = harbor.local, nếu không Go (containerd, docker)
#    báo "x509: certificate relies on legacy Common Name field".
set -euo pipefail

HARBOR_HOST="${HARBOR_HOST:-harbor.local}"
CERT_DIR="$(cd "$(dirname "$0")" && pwd)/certs"
DAYS=3650   # 10 năm — lab, khỏi lo hết hạn

mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "==> Sinh cert cho host: ${HARBOR_HOST}  (thư mục: ${CERT_DIR})"

# 1) CA tự ký
if [ ! -f ca.key ]; then
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -nodes -sha512 -days "$DAYS" \
    -subj "/C=VN/ST=HN/L=HN/O=LLMops/OU=lab/CN=harbor-ca" \
    -key ca.key -out ca.crt
  echo "   + CA mới: ca.crt"
else
  echo "   = Đã có ca.key/ca.crt — dùng lại (xóa certs/ để sinh mới)."
fi

# 2) Khóa + CSR cho server
openssl genrsa -out "${HARBOR_HOST}.key" 4096
openssl req -sha512 -new \
  -subj "/C=VN/ST=HN/L=HN/O=LLMops/OU=lab/CN=${HARBOR_HOST}" \
  -key "${HARBOR_HOST}.key" -out "${HARBOR_HOST}.csr"

# 3) SAN — bắt buộc. Thêm cả DNS lẫn (nếu muốn) IP.
cat > v3.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=${HARBOR_HOST}
EOF

# 4) Ký cert server bằng CA
openssl x509 -req -sha512 -days "$DAYS" \
  -extfile v3.ext \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -in "${HARBOR_HOST}.csr" -out "${HARBOR_HOST}.crt"

# 5) Bản .cert cho docker (docker/certs.d yêu cầu đuôi .cert)
cp "${HARBOR_HOST}.crt" "${HARBOR_HOST}.cert"

echo
echo "==> Đã sinh trong ${CERT_DIR}:"
ls -1 "$CERT_DIR"
echo
echo "Kiểm tra SAN có đúng không:"
echo "    openssl x509 -in ${CERT_DIR}/${HARBOR_HOST}.crt -noout -text | grep -A1 'Subject Alternative Name'"
echo
echo "Tiếp theo: ./03-install-harbor.sh  (helm install harbor với cert này)"
