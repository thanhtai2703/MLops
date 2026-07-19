# Phase 1 — Đường đi cơ bản (Baseline)

> **Mục tiêu một câu:** một request đi thông từ client → gateway (FastAPI) → hosted LLM API →
> trả về câu trả lời, chạy trong cluster **kubeadm** tự dựng (1 control-plane + 2 worker).

Đây là phase "dựng khung". Chưa cần metrics, chưa cần eval, chưa cần GitOps. Mục tiêu là có một
thứ **chạy được** và được deploy đúng cách (container + Kubernetes + config trong git), làm nền
cho các phase sau.

---

## Điều kiện cần trước

- **3 máy Linux** (VM/bare-metal) làm node: 1 control-plane + 2 worker. Tối thiểu control-plane
  2 vCPU / 2GB; tính cả observability + ArgoCD ở các phase sau nên chuẩn bị ~4GB+ RAM trống.
  Các node **thông nhau qua mạng** (đặt IP tĩnh, hostname riêng, phân giải được lẫn nhau).
- Trên máy dev: Docker (để build image), `kubectl`, `kustomize` (hoặc `kubectl -k`), Python 3.11+.
- Trên mỗi node: container runtime **containerd** (sẽ cài ở 1.3).
- Một **Harbor registry** truy cập được từ cả 3 node (self-host bằng Docker Compose trên một máy
  riêng, hoặc dùng Harbor có sẵn). Cần một project để đẩy image gateway vào.
- Một API key của hosted LLM (Anthropic / OpenAI / Gemini). Chọn **model rẻ nhất** ở phase này.
- Một repo git rỗng.

> **Vì sao kubeadm thay vì `kind`?** Ta muốn chứng minh kỹ năng vận hành cluster thật — đúng trọng
> tâm "lớp ops" của project. Toàn bộ phần còn lại (Kustomize, Secret, ArgoCD, Prometheus, probe)
> chạy y hệt; chỉ khác **cách dựng cluster** và **cách nạp image** (registry thay cho `kind load`).

---

## Các bước

### 1.1 — Gateway FastAPI tối giản

Viết một service có một endpoint `POST /chat` nhận `{"question": "..."}` và trả `{"answer": "..."}`.
Bên trong: đọc prompt từ file, ghép với câu hỏi, gọi hosted API, trả kết quả.

Nguyên tắc quan trọng ngay từ đầu:
- **Prompt nằm trong file** `prompts/qa_v1.txt`, *không* hard-code trong `app.py`.
- **API key đọc từ biến môi trường**, *không* commit vào git.
- Thêm endpoint `GET /healthz` trả `200` để Kubernetes probe.

### 1.2 — Đóng gói Docker + push lên Harbor

Viết `gateway/Dockerfile` (multi-stage, base image slim, chạy bằng user non-root). Build và test
local bằng `docker run` trước khi đụng tới Kubernetes.

Vì cluster có **nhiều node**, không thể "nạp image local vào một node" như `kind`. Mọi node phải
**pull được image từ một registry chung** → đẩy image lên **Harbor**:

```bash
# Đăng nhập Harbor (một lần)
docker login harbor.example.com

# Tag theo project Harbor và push
docker build -t harbor.example.com/llmops/llm-gateway:dev gateway/
docker push harbor.example.com/llmops/llm-gateway:dev
```

> Thay `harbor.example.com/llmops` bằng địa chỉ + project Harbor thật của bạn. Từ đây trở đi,
> trường `image:` trong manifest luôn trỏ tới đường dẫn Harbor này, **không** dùng `:latest`
> (tag cố định để deploy tái lập được).

### 1.3 — Cluster kubeadm (1 control-plane + 2 worker)

Toàn bộ việc **dựng 3 VM + chuẩn bị node** đã được đóng gói thành script trong
[`infra/kvm/`](../infra/kvm/) — xem [`infra/kvm/README.md`](../infra/kvm/README.md) để chạy tuần
tự. Tóm tắt những gì các script làm và các bước cluster còn lại làm bằng tay:

**a) Dựng 3 VM Debian + chuẩn bị node (qua script `infra/kvm/`):**

```bash
cd infra/kvm
./01-prereqs.sh          # công cụ + libvirt network/pool
sudo bash 02-create-vms.sh   # net-install 3 VM Debian (cp1, worker1, worker2)
./04-show-ips.sh         # lấy IP các VM (DHCP, dải 192.168.122.0/24)
./05-prepare-nodes.sh    # SSH vào 3 node: swap off, sysctl, containerd, kubeadm/kubelet/kubectl
```

`05-prepare-nodes.sh` làm đúng "chuẩn bị node kubeadm": tắt swap, nạp module + sysctl bridge, cài
containerd (`SystemdCgroup=true`), cài & ghim `kubeadm/kubelet/kubectl`.

> **Dùng net-install thay cloud image:** Debian cloud image kẹt boot trên máy dev này nên
> `02-create-vms.sh` dùng `virt-install --location` (net-install) + preseed. Chi tiết trong
> `infra/kvm/README.md`.
>
> **Bẫy Debian 13 + repo Kubernetes:** Debian 13 (`sqv`) từ chối chữ ký GPG kiểu cũ (v3) của repo
> K8s → `apt` báo *"repository is not signed"*. Script khắc phục bằng `deb [trusted=yes]` cho riêng
> repo K8s (tải qua HTTPS từ `pkgs.k8s.io` chính thức). Dùng kênh **v1.33**.

**b) Khởi tạo control-plane (trên `cp1`):**

`--apiserver-advertise-address` = IP của cp1; `--pod-network-cidr` phải **khớp** manifest Calico.

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<IP-cp1> \
  --pod-network-cidr=192.168.0.0/16

# Cấu hình kubectl cho user thường (bắt buộc, nếu không kubectl trỏ localhost:8080 và fail)
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

`kubeadm init` in ra một lệnh `kubeadm join ...` kèm token — **lưu lại** cho worker. (Token hết hạn
sau 24h; tạo lại bằng `kubeadm token create --print-join-command` trên cp1.)

**c) Cài CNI Calico (trên `cp1`):**

Node ở trạng thái `NotReady` cho tới khi có CNI. `custom-resources.yaml` mặc định dùng CIDR
`192.168.0.0/16` — khớp đúng bước init nên không cần sửa.

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml
kubectl get pods -n calico-system -w   # đợi Running; sau đó cp1 chuyển Ready
```

**d) Join 2 worker (chạy trên từng worker, kèm `sudo`):**

```bash
sudo kubeadm join <IP-cp1>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

**e) Kiểm tra cluster (trên `cp1`):**

```bash
kubectl get nodes -o wide   # cả 3 node phải Ready (worker mới join NotReady vài chục giây)
kubectl cluster-info
```

> Vì có 2 worker, **không cần** gỡ taint control-plane — workload tự schedule lên worker.
> (Chỉ single-node mới phải `kubectl taint nodes --all node-role.kubernetes.io/control-plane-`.)

### 1.4 — Manifest Kubernetes (Kustomize base)

Trong `k8s/base/` tạo: `deployment.yaml`, `service.yaml`, `kustomization.yaml`.

- Deployment: 1 replica, `image:` trỏ tới Harbor (`harbor.example.com/llmops/llm-gateway:dev`),
  đặt `readinessProbe`/`livenessProbe` trỏ `/healthz`, đặt `resources.requests/limits`.
- API key nạp qua `Secret` (ở phase này tạo secret bằng tay; phase 3 sẽ bàn cách quản lý tốt hơn).
- Service kiểu `ClusterIP`.

**Credential để pull từ Harbor:** nếu project Harbor **private**, cần một `docker-registry` secret và
tham chiếu nó qua `imagePullSecrets` trong Deployment (nếu project **public** thì bỏ qua bước này):

```bash
kubectl create secret docker-registry harbor-cred \
  --docker-server=harbor.example.com \
  --docker-username='<user>' \
  --docker-password='<password-hoặc-robot-token>'
```

```yaml
# trong spec.template.spec của Deployment
imagePullSecrets:
  - name: harbor-cred
```

> Nếu Harbor dùng chứng chỉ TLS tự ký, mỗi node phải tin cert đó (cấu hình
> `/etc/containerd/certs.d/harbor.example.com/hosts.toml`), nếu không pod sẽ báo lỗi `x509`.

Deploy:

```bash
kubectl apply -k k8s/base
kubectl port-forward svc/llm-gateway 8080:80
```

### 1.5 — Kiểm thử end-to-end

```bash
curl -X POST localhost:8080/chat \
  -H 'content-type: application/json' \
  -d '{"question":"Giải thích GitOps trong một câu."}'
```

Thấy câu trả lời hợp lý → phase 1 xong.

---

## Best practices áp dụng ở phase này

- **Config-as-code từ đầu:** prompt trong file, không hard-code.
- **12-factor:** cấu hình (API key, tên model) qua biến môi trường.
- **Container an toàn cơ bản:** non-root, image slim, có health probe.
- **Registry là nguồn image chung:** mọi node pull từ Harbor bằng tag cố định (không `:latest`).
- **Không commit secret:** dùng `.gitignore` + `.env.example` làm mẫu.

---

## Bẫy thường gặp

- **Node `NotReady` sau `kubeadm init`** → chưa cài CNI. Cài Calico xong node mới `Ready`.
- **Còn swap** hoặc **`SystemdCgroup = false`** → kubelet không lên / pod CrashLoop khó hiểu.
  Kiểm tra lại bước chuẩn bị node (1.3a).
- **`kubeadm join` fail vì token hết hạn** (token mặc định sống 24h) → tạo lại bằng
  `kubeadm token create --print-join-command` trên control-plane.
- **`ErrImagePull` / `ImagePullBackOff`** → image chưa push lên Harbor, sai đường dẫn `image:`,
  thiếu `imagePullSecrets` (project private), hoặc node chưa tin cert TLS của Harbor (`x509`).
- **`pod-network-cidr` không khớp** giữa `kubeadm init` và manifest Calico → mạng pod hỏng.
- Đặt API key thẳng trong manifest rồi commit → lộ key. Dùng Secret + biến môi trường.
- Không đặt `resources` → pod bị evict hoặc chạy lộn xộn về sau.

---

## Definition of Done

- [ ] Cluster kubeadm 3 node (1 CP + 2 worker) đều `Ready`, CNI Calico hoạt động.
- [ ] Image gateway được push lên Harbor; pod pull image thành công từ registry.
- [ ] `curl` tới gateway trong cluster trả về câu trả lời từ LLM.
- [ ] Prompt nằm trong `prompts/qa_v1.txt`, được commit vào git.
- [ ] API key **không** có trong git; nạp qua Secret/biến môi trường.
- [ ] Deploy hoàn toàn bằng `kubectl apply -k k8s/base` (không thao tác tay trên cluster).
- [ ] `GET /healthz` trả 200 và probe hoạt động.

## Bằng chứng để lưu

- Screenshot `kubectl get nodes -o wide` (3 node Ready) + `kubectl get pods -o wide`
  (pod Running, thấy nó schedule lên worker).
- Screenshot Harbor hiển thị image `llm-gateway` đã push + output `curl` trả lời.
- Link commit chứa `Dockerfile`, `k8s/base/`, `prompts/qa_v1.txt`.

---

➡️ Tiếp theo: [Phase 2 — Observability](phase-2-observability.md)
