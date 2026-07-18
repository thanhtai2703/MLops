# Phase 3 — Ops Loop (Eval Gate + GitOps)

> **Mục tiêu một câu:** mọi thay đổi đi qua git, bị **eval kiểm soát**, và ArgoCD tự deploy —
> một PR làm tệ prompt/model sẽ bị CI chặn lại.

Đây là **trái tim của project** và là điểm khác biệt lớn nhất so với một RAG demo thông thường.
Cũng là phần dễ làm ẩu nhất, nên đầu tư nhiều thời gian ở đây.

---

## Điều kiện cần trước

- Hoàn tất Phase 2 (đã có version model/prompt trong trace, đã đo được chất lượng vận hành).
- Repo đã cấu trúc `k8s/base` + chuẩn bị tách `overlays/`.

---

## Phần A — Eval harness

### 3.1 — Golden / regression dataset

Tạo `eval/dataset.jsonl`, mỗi dòng một case:

```json
{"id": "q1", "question": "GitOps là gì?", "expected_points": ["khai báo trạng thái mong muốn trong git", "công cụ tự đồng bộ"]}
```

Giữ nhỏ (20–40 case là đủ để thể hiện cơ chế). Bao gồm vài case "khó" để prompt tệ sẽ trượt.
Dataset **nằm trong git** và được version cùng repo.

### 3.2 — LLM-as-judge theo rubric

Viết `eval/judge_rubric.md`: một thang điểm rõ ràng (ví dụ 0–5) theo các tiêu chí như *đúng trọng
tâm*, *không bịa*, *đủ ý*. `run_eval.py` sẽ: với mỗi case → gọi gateway lấy câu trả lời → gọi
một model làm "giám khảo" chấm theo rubric → tổng hợp điểm trung bình.

Nguyên tắc: **rubric cố định**, không chấm cảm tính. Ghi lại điểm theo cặp `model + prompt version`.

### 3.3 — Ngưỡng pass/fail

`eval/thresholds.yaml`:

```yaml
min_avg_score: 3.8
max_regression: 0.3   # không được tụt quá 0.3 so với baseline đã lưu
```

`run_eval.py` trả **exit code ≠ 0** nếu dưới ngưỡng — đây là cơ chế để CI "fail".

---

## Phần B — CI eval gate (GitHub Actions)

### 3.4 — Workflow `.github/workflows/ci.yaml`

Trên mỗi PR/push:
1. Build image gateway.
2. Chạy gateway tạm (hoặc trỏ tới một môi trường eval) và chạy `run_eval.py`.
3. **Nếu eval fail → job fail → PR không merge được.**
4. In bảng điểm ra job summary để review nhìn thấy ngay.
5. Chỉ khi eval **pass** trên nhánh chính → `docker login` vào **Harbor** rồi push image với tag
   cố định (ví dụ theo git SHA). Đây là image mà ArgoCD sẽ deploy ở Phần C.

> Runner phải tới được Harbor. Nếu Harbor nằm trong mạng nội bộ, dùng **self-hosted runner** trong
> cùng mạng; lưu `HARBOR_USER`/`HARBOR_TOKEN` (nên dùng **robot account** của Harbor) trong GitHub
> Secrets, đừng hard-code.

Đây chính là bản LLMOps của "unit test chặn merge": prompt/model kém không lọt được vào nhánh chính.

> Mẹo tiết kiệm: dùng model rẻ cho cả gateway lẫn judge trong CI; cache dependency; giới hạn dataset.

---

## Phần C — GitOps deploy (ArgoCD)

### 3.5 — Tách overlay dev/prod (Kustomize)

`k8s/overlays/dev/` và `k8s/overlays/prod/` kế thừa `base` và khác nhau ở: số replica, tên model
(dev dùng model rẻ), tài nguyên, **tag image Harbor** (dev/prod trỏ tag khác nhau). Cấu hình
(prompt version, model) khác nhau qua ConfigMap.

> Nếu project Harbor là private, mỗi **namespace** deploy (dev, prod) cần secret `harbor-cred`
> riêng cho `imagePullSecrets` — Secret không xuyên namespace. Tạo trước bằng tay, hoặc quản lý
> qua External Secrets ở phase sau (xem [phase-4](phase-4-polish.md) mục production gap).

### 3.6 — ArgoCD Application

Cài ArgoCD vào cluster. Tạo `argocd/application.yaml` trỏ vào overlay. ArgoCD tự đồng bộ trạng
thái cluster theo git — thay đổi merge vào git là được deploy, và **rollback = git revert.**

### 3.7 — Promote có kiểm soát

Luồng đề xuất:
- Merge vào `main` → CI eval pass → ArgoCD sync **dev** tự động.
- Promote **dev → prod** chỉ diễn ra khi eval đã pass (ví dụ qua một PR cập nhật tag/overlay prod,
  hoặc ArgoCD sync-wave/approval). Không deploy thẳng lên prod.

---

## Best practices áp dụng ở phase này

- **Eval-as-gate:** chất lượng câu trả lời chặn deploy, giống test chặn merge.
- **Regression dataset được version:** so sánh có cơ sở giữa các thay đổi.
- **Prompt gắn với deploy:** đổi prompt = commit = deploy có thể rollback.
- **Judge theo rubric cố định:** đánh giá lặp lại được, không cảm tính.
- **GitOps thuần:** không sửa tay trên cluster; git là nguồn sự thật duy nhất.
- **Tách môi trường + promote có kiểm soát.**

---

## Bẫy thường gặp

- **Judge nhiễu:** cùng câu trả lời chấm hai lần ra điểm khác nhau nhiều. Giảm nhiễu bằng
  temperature thấp cho judge, rubric cụ thể, và lấy trung bình nhiều case thay vì tin một case.
- **Dataset quá dễ:** mọi thứ đều pass → gate vô dụng. Cố tình thêm case mà prompt tệ sẽ trượt.
- **Eval gate quá đắt/chậm** làm CI ì ạch: giữ dataset nhỏ, model rẻ, chạy song song.
- **Quên baseline:** không lưu điểm baseline thì không phát hiện được "regression". Lưu điểm mỗi
  lần chạy trên `main` để so sánh.

---

## Definition of Done

- [ ] `run_eval.py` chấm dataset theo rubric và trả exit code theo `thresholds.yaml`.
- [ ] GitHub Actions chạy eval trên PR; **một PR làm tệ prompt bị chặn** (có log fail) — *ảnh chụp
  đáng giá nhất của cả dự án*.
- [ ] ArgoCD sync dev tự động sau khi eval pass; prod chỉ promote có kiểm soát.
- [ ] Toàn bộ thay đổi (prompt, model, config) đi qua git; rollback được bằng git revert.

## Bằng chứng để lưu

- Screenshot PR bị **CI eval gate chặn** + bảng điểm trong job summary.
- Screenshot ArgoCD UI hiển thị app synced/healthy cho dev và prod.
- Link commit chứa `eval/`, `.github/workflows/ci.yaml`, `k8s/overlays/`, `argocd/`.

---

⬅️ Trước đó: [Phase 2 — Observability](phase-2-observability.md) &nbsp;|&nbsp; ➡️ Tiếp theo: [Phase 4 — Đánh bóng](phase-4-polish.md)
