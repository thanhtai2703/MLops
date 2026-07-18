# LLM Inference Gateway trên Kubernetes — Eval-Gated GitOps

> Project LLMOps nhỏ, không phản ánh production 100% nhưng bám sát best practices.
> Trọng tâm là **lớp vận hành** (ops), tận dụng nền tảng DevOps sẵn có:
> Kubernetes, ArgoCD/GitOps, Terraform, Prometheus/Grafana, GitHub Actions.

---

## Ý tưởng cốt lõi

Dựng một **gateway** đứng trước (các) backend model và biến toàn bộ vòng đời của nó thành một
pipeline GitOps. Điểm khác biệt đặc trưng của **LLMOps** là **eval làm cổng chặn deploy**
(eval-as-gate): giống unit test chặn merge trong DevOps, ở đây một bộ eval về *chất lượng câu
trả lời* sẽ chặn việc promote lên môi trường cao hơn nếu chất lượng tụt.

Bản thân "app" chỉ cần đơn giản (một endpoint hỏi–đáp). **App không phải trọng tâm — lớp ops mới là.**

### Vì sao hướng này hợp với hồ sơ DevOps

| Skill sẵn có | Được tái sử dụng ở đâu |
|---|---|
| Kubernetes / EKS | Cluster chạy gateway + observability |
| ArgoCD + GitOps overlays (dev/prod) | Deploy config-as-code, promote qua git |
| Terraform | (Tùy chọn) provision cluster cloud cho demo cuối |
| Prometheus + Grafana | Đo metrics đặc thù LLM (token, cost, latency) |
| GitHub Actions | Chạy eval và **chặn deploy** nếu chất lượng giảm |
| Python / FastAPI | Viết gateway (routing, metrics, cache) |

---

## Các phase

Mỗi phase là một file riêng trong thư mục `phases/`. Làm tuần tự; mỗi phase kết thúc bằng một
"vòng lặp" chạy được và một bằng chứng (screenshot / log / config) để đưa vào portfolio.

| Phase | Tên | Mục tiêu một câu | File |
|---|---|---|---|
| 1 | Đường đi cơ bản | Một request đi thông client → gateway → model | [phase-1-baseline.md](phases/phase-1-baseline.md) |
| 2 | Observability | Nhìn thấy cost / token / latency của từng request | [phase-2-observability.md](phases/phase-2-observability.md) |
| 3 | Ops loop | Eval gate + ArgoCD GitOps kiểm soát deploy | [phase-3-ops-loop.md](phases/phase-3-ops-loop.md) |
| 4 | Đánh bóng + nâng cao | Cache, alert, README, tùy chọn self-host | [phase-4-polish.md](phases/phase-4-polish.md) |

---

## Kiến trúc tổng thể

```
                         ┌─────────────────────────────────────────────┐
                         │                Git repository                │
                         │  prompts/  routing rules  eval thresholds     │
                         │  k8s manifests (Kustomize: base + overlays)   │
                         └───────────────┬───────────────┬───────────────┘
                                         │               │
                            GitHub Actions │               │ ArgoCD (GitOps)
                            (eval gate)   │               │ sync dev/prod
                                         ▼               ▼
   ┌──────────┐      ┌──────────────────────────────────────────────┐
   │  Client  │─────▶│         LLM Gateway (FastAPI)                 │
   └──────────┘      │  routing • cache • đo token/cost/latency     │
                     │  gắn version model + prompt vào mỗi request  │
                     └───────┬───────────────────────┬──────────────┘
                    /metrics │                       │ trace mỗi request
                             ▼                       ▼
                  ┌────────────────────┐   ┌──────────────────────┐
                  │ Prometheus+Grafana │   │ Langfuse / Phoenix   │
                  └────────────────────┘   └──────────────────────┘
                             │
              backend model  ▼
      ┌──────────────────────────────────────┐
      │ Hosted API (đầu) → Ollama/vLLM (sau)  │
      └──────────────────────────────────────┘
```

---

## Tech stack

| Lớp | Công cụ |
|---|---|
| Ngôn ngữ | Python |
| Gateway | FastAPI (hoặc LiteLLM proxy) |
| Model backend | Hosted LLM API → (tùy chọn) Ollama / vLLM |
| Container | Docker |
| Orchestration | Kubernetes — `kind` local, EKS chỉ cho demo cuối |
| Deploy config | Kustomize (base + overlays dev/prod) |
| GitOps | ArgoCD |
| Metrics | Prometheus + Grafana |
| Tracing LLM | Langfuse (khuyên dùng) hoặc Arize Phoenix |
| CI/CD | GitHub Actions |
| IaC (tùy chọn) | Terraform (chỉ khi lên EKS) |

---

## Cấu trúc thư mục repo (đích đến cuối cùng)

```
llm-gateway/
├── README.md                  # sơ đồ + hướng dẫn + mục "nếu lên prod thật"
├── gateway/
│   ├── app.py                 # FastAPI: routing, cache, metrics, tracing
│   ├── routing.py             # logic chọn model dễ/khó
│   ├── cache.py               # semantic cache
│   └── Dockerfile
├── prompts/
│   └── qa_v1.txt              # prompt được version bằng git
├── eval/
│   ├── dataset.jsonl          # golden/regression dataset
│   ├── run_eval.py            # chạy eval, xuất điểm
│   ├── judge_rubric.md        # rubric cho LLM-as-judge
│   └── thresholds.yaml        # ngưỡng pass/fail
├── k8s/
│   ├── base/                  # manifest chung
│   └── overlays/{dev,prod}/
├── argocd/
│   └── application.yaml       # ArgoCD App trỏ vào overlays
├── observability/
│   ├── prometheus/
│   └── grafana/               # dashboard JSON
├── .github/workflows/
│   └── ci.yaml                # build + eval gate
└── terraform/                 # (tùy chọn) provision EKS cho demo cuối
```

---

## Lưu ý chi phí

- Chạy chủ yếu trên **`kind` local** để khỏi tốn tiền AWS.
- Chỉ dựng EKS cho **một lần demo cuối** nếu muốn, rồi teardown ngay.
- Dùng **model rẻ/nhỏ** cho hosted API, đặt giới hạn chi tiêu; eval dataset giữ nhỏ (vài chục câu).
- Self-host: ưu tiên Ollama trên CPU cho model nhỏ; chỉ dùng GPU spot khi thật cần.

---

## Tiêu chí "làm xong" toàn dự án

- [ ] Một PR làm tệ prompt/model bị **CI eval gate chặn** (có log fail) — ảnh chụp đáng giá nhất.
- [ ] Grafana hiển thị cost / latency / chất lượng theo từng cặp `model + prompt version`.
- [ ] ArgoCD chỉ promote dev → prod **sau khi** eval pass.
- [ ] Mỗi trace trong Langfuse tái lập được (biết rõ prompt + model version).
- [ ] Semantic cache hoạt động, có số liệu cache hit rate.
- [ ] README có sơ đồ kiến trúc và mục "nếu lên production thật thì tôi sẽ thêm gì".
