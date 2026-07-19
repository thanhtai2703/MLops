# Harbor registry (trong cluster, TLS tự ký) — cho Phase 1

Cài **Harbor** vào chính cluster kubeadm 3 node bằng **Helm**, expose qua **ingress-nginx
(NodePort)** với hostname `harbor.local` và **cert TLS tự ký**. Sau đó cho cả 3 node tin cert
đó (`certs.d`) để `containerd` pull image không lỗi `x509`.

> Đây là bước "một Harbor registry truy cập được từ cả 3 node" trong
> [phase-1-baseline.md](../../docs/phase-1-baseline.md). Xong bước này mới build/push image
> gateway (§ 1.2) rồi deploy `k8s/base`.

## Sơ đồ

```
docker/kubelet client
      │  https://harbor.local:30443   (tin cert tự ký qua certs.d / docker certs.d)
      ▼
ingress-nginx (Service NodePort 30443)  ──►  Service Harbor core  ──►  các pod Harbor
                                                                  └─ PVC (local-path-provisioner)
```

## Thứ tự chạy

| Bước | Script | Chạy ở đâu | Việc |
|---|---|---|---|
| 1 | `01-storage-and-ingress.sh` | **cp1** (có kubectl) | local-path-provisioner (StorageClass mặc định) + ingress-nginx (NodePort 30080/30443) |
| 2 | `02-gen-cert.sh` | **cp1** | Sinh CA + cert tự ký cho `harbor.local` (có SAN) → `certs/` |
| 3 | `03-install-harbor.sh` | **cp1** | `helm upgrade --install harbor` với TLS tự ký + ingress |
| 4 | `04-trust-cert-nodes.sh` | **host KVM** (có `sudo virsh`) | SSH sang 3 node: nạp CA vào `certs.d`, bật `config_path`, thêm `/etc/hosts` |
| 5 | `05-test-login-push.sh` | **máy có docker** | `docker login` + push/pull image thử |

### Chi tiết

```bash
# --- Trên cp1 (SSH vào cp1) ---
# copy thư mục infra/harbor lên cp1 trước, hoặc git clone repo trên cp1.
cd infra/harbor

./01-storage-and-ingress.sh      # storage + ingress
./02-gen-cert.sh                 # sinh cert -> certs/  (HARBOR_HOST=harbor.local mặc định)
./03-install-harbor.sh           # helm install; đợi pod Ready
kubectl get pods,pvc,ingress -n harbor   # kiểm tra

# --- Trên HOST KVM (máy chạy libvirt, KHÔNG phải trong VM) ---
# Cần thư mục certs/ (từ bước 02). Nếu bước 02 chạy trên cp1, copy certs/ về host:
#   scp -r debian@<IP-cp1>:~/LLMops/infra/harbor/certs infra/harbor/
cd infra/harbor
./04-trust-cert-nodes.sh         # cho 3 node tin cert + phân giải harbor.local

# --- Trên máy có docker (host dev, hoặc cp1 nếu có docker) ---
# Cần certs/ca.crt. Nếu ở host dev, copy certs/ từ cp1 về như trên.
cd infra/harbor
# Nếu máy này chưa phân giải harbor.local, truyền NODE_IP=<IP-cp1>:
NODE_IP=<IP-cp1> ./05-test-login-push.sh
```

## Thông số mặc định (đổi qua biến môi trường)

| Biến | Mặc định | Ghi chú |
|---|---|---|
| `HARBOR_HOST` | `harbor.local` | hostname + CN/SAN của cert |
| `HARBOR_PORT` | `30443` | NodePort HTTPS của ingress (script 01 ghim sẵn) |
| `HARBOR_NS` | `harbor` | namespace |
| `HARBOR_ADMIN_PW` | `Harbor12345` | mật khẩu admin — **đổi khi lên thật** |
| `HARBOR_CHART_VERSION` | `1.15.1` | app Harbor v2.11.x |

Đổi ví dụ:

```bash
HARBOR_HOST=registry.lab HARBOR_ADMIN_PW='MậtKhẩuMạnh!' ./03-install-harbor.sh
```

## Truy cập UI

`https://harbor.local:30443` — user `admin`, mật khẩu `Harbor12345` (hoặc `HARBOR_ADMIN_PW`).
Trình duyệt sẽ cảnh báo cert tự ký → bấm "Proceed anyway" (lab).

## Đẩy image gateway (Phase 1 § 1.2)

```bash
# Tạo project 'llmops' trong Harbor UI trước (hoặc để public).
docker build -t harbor.local:30443/llmops/llm-gateway:dev gateway/
docker push  harbor.local:30443/llmops/llm-gateway:dev
```

Rồi trong `k8s/base/deployment.yaml`: `image: harbor.local:30443/llmops/llm-gateway:dev`.
Project **private** → tạo `imagePullSecret` (xem phase-1 § 1.4).

## Gỡ rối

- **PVC `Pending`** → thiếu StorageClass mặc định. Chạy lại bước 01, kiểm tra
  `kubectl get storageclass` thấy `local-path (default)`.
- **`x509: certificate signed by unknown authority`** khi pod ImagePull → node chưa tin cert.
  Chạy lại `04-trust-cert-nodes.sh`; kiểm tra `config_path = "/etc/containerd/certs.d"` có
  trong `/etc/containerd/config.toml` và đã `systemctl restart containerd`.
- **`x509: ... relies on legacy Common Name field`** → cert thiếu SAN. Xóa `certs/` và chạy
  lại `02-gen-cert.sh` (script này đã thêm SAN).
- **docker login báo lỗi cert** → docker dùng `/etc/docker/certs.d/<host:port>/ca.crt`, KHÁC
  chỗ của containerd. Script 05 tự copy; nếu tay thì tạo đúng đường dẫn đó.
- **redirect sai cổng khi login/push** → `externalURL` phải kèm `:30443`. Đã set trong 03.
- **`harbor.local` không phân giải** → thêm `<IP-cp1> harbor.local` vào `/etc/hosts` máy client.
- **Ingress không lên / NodePort trùng** → `kubectl get svc -n ingress-nginx`; đổi
  `INGRESS_HTTPS_NODEPORT` trong 01 nếu 30443 đã bị chiếm.

## Gỡ Harbor để làm lại

```bash
helm uninstall harbor -n harbor
kubectl delete namespace harbor    # xóa cả PVC/PV (mất dữ liệu registry)
```
