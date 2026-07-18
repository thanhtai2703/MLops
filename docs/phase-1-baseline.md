# Phase 1 — Đường đi cơ bản (Baseline)

> **Mục tiêu một câu:** một request đi thông từ client → gateway (FastAPI) → hosted LLM API →
> trả về câu trả lời, chạy trong cluster `kind` local.

Đây là phase "dựng khung". Chưa cần metrics, chưa cần eval, chưa cần GitOps. Mục tiêu là có một
thứ **chạy được** và được deploy đúng cách (container + Kubernetes + config trong git), làm nền
cho các phase sau.

---

## Điều kiện cần trước

- Cài: Docker, `kind`, `kubectl`, `kustomize` (hoặc `kubectl -k`), Python 3.11+.
- Một API key của hosted LLM (Anthropic / OpenAI / Gemini). Chọn **model rẻ nhất** ở phase này.
- Một repo git rỗng.

---

## Các bước

### 1.1 — Gateway FastAPI tối giản

Viết một service có một endpoint `POST /chat` nhận `{"question": "..."}` và trả `{"answer": "..."}`.
Bên trong: đọc prompt từ file, ghép với câu hỏi, gọi hosted API, trả kết quả.

Nguyên tắc quan trọng ngay từ đầu:
- **Prompt nằm trong file** `prompts/qa_v1.txt`, *không* hard-code trong `app.py`.
- **API key đọc từ biến môi trường**, *không* commit vào git.
- Thêm endpoint `GET /healthz` trả `200` để Kubernetes probe.

### 1.2 — Đóng gói Docker

Viết `gateway/Dockerfile` (multi-stage, base image slim, chạy bằng user non-root). Build và test
local bằng `docker run` trước khi đụng tới Kubernetes.

### 1.3 — Cluster local

```bash
kind create cluster --name llmops
kubectl cluster-info --context kind-llmops
```

Load image vào kind (không cần registry ở phase này):

```bash
kind load docker-image llm-gateway:dev --name llmops
```

### 1.4 — Manifest Kubernetes (Kustomize base)

Trong `k8s/base/` tạo: `deployment.yaml`, `service.yaml`, `kustomization.yaml`.

- Deployment: 1 replica, đặt `readinessProbe`/`livenessProbe` trỏ `/healthz`, đặt `resources.requests/limits`.
- API key nạp qua `Secret` (ở phase này tạo secret bằng tay; phase 3 sẽ bàn cách quản lý tốt hơn).
- Service kiểu `ClusterIP`.

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
- **Không commit secret:** dùng `.gitignore` + `.env.example` làm mẫu.

---

## Bẫy thường gặp

- Quên `kind load docker-image` → pod báo `ErrImagePull` vì kind không thấy image local.
- Đặt API key thẳng trong manifest rồi commit → lộ key. Dùng Secret + biến môi trường.
- Không đặt `resources` → pod bị evict hoặc chạy lộn xộn về sau.

---

## Definition of Done

- [ ] `curl` tới gateway trong cluster trả về câu trả lời từ LLM.
- [ ] Prompt nằm trong `prompts/qa_v1.txt`, được commit vào git.
- [ ] API key **không** có trong git; nạp qua Secret/biến môi trường.
- [ ] Deploy hoàn toàn bằng `kubectl apply -k k8s/base` (không thao tác tay trên cluster).
- [ ] `GET /healthz` trả 200 và probe hoạt động.

## Bằng chứng để lưu

- Screenshot `kubectl get pods` (pod Running) + output `curl` trả lời.
- Link commit chứa `Dockerfile`, `k8s/base/`, `prompts/qa_v1.txt`.

---

➡️ Tiếp theo: [Phase 2 — Observability](phase-2-observability.md)
