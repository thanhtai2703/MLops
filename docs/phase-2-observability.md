# Phase 2 — Observability

> **Mục tiêu một câu:** mở Grafana/Langfuse là *nhìn thấy* cost, token, latency và hành vi của
> từng request.

LLM app khác web service thường ở chỗ: nó tốn tiền theo token và chất lượng khó nhìn bằng mắt.
Phase này biến gateway từ "hộp đen" thành "hộp kính" — điều kiện tiên quyết để phase 3 có thể
*đo* và *chặn* dựa trên dữ liệu.

---

## Điều kiện cần trước

- Hoàn tất Phase 1 (gateway chạy trong cluster kubeadm).
- Nắm cơ bản Prometheus exposition format (`/metrics`).

---

## Các bước

### 2.1 — Instrument gateway

Thêm endpoint `GET /metrics` (dùng `prometheus-client` cho Python). Xuất tối thiểu:

| Metric | Kiểu | Ý nghĩa |
|---|---|---|
| `llm_requests_total` | Counter (label: model, status) | Số request theo model và kết quả |
| `llm_tokens_total` | Counter (label: model, direction=in/out) | Tổng token vào/ra |
| `llm_cost_usd_total` | Counter (label: model) | Cost ước tính = token × đơn giá |
| `llm_request_latency_seconds` | Histogram (label: model) | Phân bố latency |
| `llm_errors_total` | Counter (label: type) | Lỗi theo loại (timeout, rate-limit, ...) |

Cost tính trong code: giữ một bảng đơn giá `{model: (giá_in, giá_out)}` rồi nhân với token.
Không cần chính xác tuyệt đối — cần *nhất quán* để so sánh giữa các version.

### 2.2 — Cài Prometheus + Grafana

Cách gọn nhất: dùng Helm chart `kube-prometheus-stack`. Thêm một `ServiceMonitor`
(hoặc annotation scrape) để Prometheus tự thu `/metrics` của gateway.

> Trên cluster kubeadm nhiều node, Prometheus/Grafana có thể bị schedule lên bất kỳ worker nào.
> Nếu muốn dữ liệu bền qua restart, cấp `PersistentVolume` (ví dụ dùng `local-path-provisioner`
> hoặc một StorageClass sẵn có) — `kind` mặc định có provisioner, kubeadm thì bạn tự lo.

### 2.3 — Dashboard Grafana

Tạo ít nhất một dashboard (`observability/grafana/*.json`, commit vào git) gồm:
- Cost tích lũy theo thời gian (và cost theo từng model).
- Latency p50/p95.
- Request rate + error rate.
- Tổng token in/out.

Export dashboard ra JSON và commit — **dashboard cũng là config-as-code.**

### 2.4 — Tracing per-request (Langfuse)

Cài Langfuse (self-host bằng Docker Compose ngoài cluster cũng được ở giai đoạn này, hoặc deploy
vào cluster). Trong gateway, bọc mỗi lời gọi LLM bằng một trace, ghi lại:
- Câu hỏi + câu trả lời.
- **`model_version` và `prompt_version`** (cực kỳ quan trọng cho tái lập).
- Token, cost, latency của lần gọi đó.

Từ giờ, mỗi request có thể truy ngược: nó chạy với prompt nào, model nào, tốn bao nhiêu.

---

## Best practices áp dụng ở phase này

- **Cost là first-class metric**, không chỉ đo latency.
- **Gắn version vào mọi trace** → nền tảng cho reproducibility ở phase 3.
- **Dashboard-as-code:** JSON dashboard nằm trong git, không vẽ tay rồi để đó.
- **Label có kỷ luật:** dùng label `model`, `prompt_version` nhất quán để về sau so sánh được.

---

## Bẫy thường gặp

- Nhét quá nhiều giá trị vào label (ví dụ label = nội dung câu hỏi) → nổ cardinality của Prometheus.
  Chỉ dùng label có tập giá trị hữu hạn (model, status, version).
- Đo latency toàn bộ request mà quên tách riêng thời gian gọi model → khó biết nút cổ chai ở đâu.
- Log cả câu hỏi/câu trả lời chứa dữ liệu nhạy cảm vào trace mà không cân nhắc — ghi chú điều này
  trong README (ở prod thật sẽ cần scrub PII).

---

## Definition of Done

- [ ] `GET /metrics` xuất token, cost, latency, error theo label `model`.
- [ ] Prometheus scrape được gateway; Grafana có dashboard cost/latency (JSON đã commit).
- [ ] Langfuse ghi trace mỗi request, kèm `model_version` + `prompt_version`.
- [ ] Nhìn một trace bất kỳ là biết nó chạy với prompt/model nào và tốn bao nhiêu.

## Bằng chứng để lưu

- Screenshot dashboard Grafana có dữ liệu cost + latency.
- Screenshot một trace Langfuse hiển thị model/prompt version + token/cost.

---

⬅️ Trước đó: [Phase 1 — Baseline](phase-1-baseline.md) &nbsp;|&nbsp; ➡️ Tiếp theo: [Phase 3 — Ops loop](phase-3-ops-loop.md)
