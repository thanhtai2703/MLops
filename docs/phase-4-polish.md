# Phase 4 — Đánh bóng + Nâng cao (tùy chọn)

> **Mục tiêu một câu:** biến project chạy được thành project *trình bày được* — thêm cache, alert,
> README chỉn chu, và (tùy chọn) khoe khả năng self-host model.

Đến đây vòng lặp vận hành đã đủ. Phase này tăng độ hoàn thiện và giá trị portfolio. Các mục dưới
đây **độc lập** — làm cái nào trước cũng được, có thể bỏ bớt tùy thời gian.

---

## 4.1 — Semantic cache

Thêm cache trong gateway: nếu câu hỏi tương tự một câu đã hỏi (so khớp embedding trên ngưỡng
tương đồng), trả lại kết quả cũ thay vì gọi model.

- Đo `cache_hit_rate` và bổ sung vào dashboard Grafana.
- Cho thấy **cost giảm bao nhiêu** nhờ cache — con số cụ thể luôn gây ấn tượng.
- Lưu ý trade-off: cache có thể trả lời cũ khi nội dung cần cập nhật; ghi chú trong README.

## 4.2 — Alerting

Cấu hình Prometheus Alertmanager để cảnh báo khi:
- Cost tăng đột biến (ví dụ cost/giờ vượt ngưỡng).
- Error rate hoặc latency p95 vượt ngưỡng.
- (Nếu chạy eval định kỳ) điểm chất lượng tụt dưới ngưỡng — *quality drift*.

Không cần gửi ra ngoài thật; alert hiện trong Alertmanager UI là đủ để demo cơ chế.

## 4.3 — README chỉn chu (quan trọng cho phỏng vấn)

README phải có:
- Sơ đồ kiến trúc (ảnh, không chỉ ASCII).
- Hướng dẫn chạy từ đầu (`kind` → deploy → curl).
- Ảnh chụp: PR bị eval gate chặn, dashboard Grafana, ArgoCD synced.
- **Mục "Nếu lên production thật thì tôi sẽ thêm gì".** Xem 4.4.

## 4.4 — Mục "Production gap" (đừng bỏ qua)

Liệt kê thẳng thắn những gì project *chưa* làm và ở prod thật sẽ cần, ví dụ:
- Secrets management đúng cách (External Secrets / Vault) thay vì Secret thủ công.
- Scrub PII trước khi log vào trace.
- Autoscaling theo tải, rate limiting per-tenant, budget guardrails.
- Eval phong phú hơn (adversarial, safety, red-team), human-in-the-loop.
- HA cho observability, retention/cost cho log & trace.

Mục này cho thấy bạn **hiểu khoảng cách** với production — nhà tuyển dụng đánh giá điều này cao hơn
việc giả vờ project đã hoàn hảo.

---

## Tùy chọn nâng cao (chọn 0–1 cái, đừng ôm hết)

### A. Self-host model (khoe serving)
Swap hosted API sang model nhỏ chạy bằng **Ollama** (CPU) hoặc **vLLM** (GPU spot). Giữ nguyên
gateway và eval → cho thấy kiến trúc không phụ thuộc backend. So sánh cost/latency hosted vs self-host.

### B. Model routing thông minh
Phân loại độ khó câu hỏi → câu dễ dùng model rẻ, câu khó dùng model mạnh. *Đo* mức tiết kiệm cost
và kiểm tra eval score không tụt.

### C. Canary / A-B giữa hai prompt hoặc hai model
Chạy song song hai version, so sánh eval score + cost, rồi mới "promote" version thắng.

### D. Demo trên cloud thật
Provision EKS bằng **Terraform** cho một lần demo cuối (tái dùng đúng kỹ năng trong CV), quay video,
rồi `terraform destroy` để khỏi tốn tiền.

---

## Best practices áp dụng ở phase này

- **Đo tác động của tối ưu** (cache/routing) bằng số liệu, không nói suông.
- **Trung thực về giới hạn** qua mục production gap.
- **Tài liệu là một phần của sản phẩm:** README rõ ràng, có bằng chứng trực quan.

---

## Definition of Done

- [ ] Semantic cache hoạt động; dashboard có `cache_hit_rate` và mức tiết kiệm cost.
- [ ] Có ít nhất một alert rule hoạt động (hiện trong Alertmanager).
- [ ] README hoàn chỉnh: sơ đồ + hướng dẫn + ảnh chụp + mục production gap.
- [ ] (Nếu làm) một tùy chọn nâng cao được hoàn thành và có số liệu so sánh.

## Bằng chứng để lưu

- Screenshot dashboard trước/sau khi bật cache (cost giảm).
- Screenshot alert kích hoạt.
- Link README hoàn chỉnh trên GitHub.

---

⬅️ Trước đó: [Phase 3 — Ops loop](phase-3-ops-loop.md) &nbsp;|&nbsp; 🏁 Kết thúc dự án
