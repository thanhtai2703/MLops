# Giai đoạn 0 — Dựng 3 VM (KVM/libvirt) cho cluster kubeadm

Tạo 3 VM Debian 13 trên máy host (Debian) làm `cp1` (control-plane) + `worker1` + `worker2`
bằng **net-install** (virt-install tự tải kernel+initrd rồi cài tự động qua preseed).

> **Vì sao net-install thay vì cloud image?** Debian genericcloud image liên tục kẹt boot trên
> máy này (kernel không nạp sau GRUB). Net-install dựng máy ảo theo kiểu cài đặt chuẩn nên khớp
> firmware, ổn định. Đổi lại không dùng cloud-init — việc chuẩn bị node làm qua SSH ở bước 05.

## Cấu hình mặc định

| Node | Vai trò | RAM | vCPU | Disk |
|---|---|---|---|---|
| `cp1` | control-plane | 3GB | 2 | 20GB |
| `worker1` | worker | 3GB | 2 | 20GB |
| `worker2` | worker | 3GB | 2 | 20GB |

Mạng: libvirt NAT `default` (192.168.122.0/24), IP qua DHCP.
Đăng nhập: user `debian`, SSH bằng key `~/.ssh/id_ed25519.pub` (mật khẩu cứu hộ: `debian`).

## Các bước

```bash
cd infra/kvm

# 1) Cài công cụ + tạo network/pool libvirt (chạy một lần)
./01-prereqs.sh

# 2) Net-install 3 VM (mỗi VM cài ~5-15 phút tùy mạng, tự reboot khi xong)
sudo bash 02-create-vms.sh
#    theo dõi cài đặt trực tiếp (tùy chọn):
sudo virsh console cp1        # thoát: Ctrl+]

# 3) Khi cài xong + reboot, lấy IP
./04-show-ips.sh

# 4) Cài containerd + kubeadm lên cả 3 node qua SSH (thay cho cloud-init)
./05-prepare-nodes.sh

# 5) Kiểm tra 1 node đã sẵn sàng
ssh debian@<IP-cp1> 'ls -l /var/lib/kubeadm-node-ready && kubeadm version -o short'
```

Xong 5 bước này là **hết Giai đoạn 0**. Tiếp theo quay lại
[phase-1-baseline.md § 1.3b](../../docs/phase-1-baseline.md) để `kubeadm init` trên `cp1`,
cài Calico, rồi `join` 2 worker.

## Làm lại từ đầu

```bash
./03-teardown.sh          # xóa 3 VM + disk + preseed
```

## Các file

| File | Vai trò |
|---|---|
| `01-prereqs.sh` | cài công cụ, tạo libvirt network + pool |
| `02-create-vms.sh` | net-install 3 VM (dùng preseed) |
| `03-teardown.sh` | xóa sạch 3 VM để làm lại |
| `04-show-ips.sh` | hiện IP + lệnh SSH |
| `05-prepare-nodes.sh` | cài containerd + kubeadm lên 3 node qua SSH |
| `preseed/preseed.cfg.tmpl` | file trả lời tự động cho Debian installer |

## Ghi chú / gỡ rối

- **Theo dõi cài đặt:** `sudo virsh console cp1` (thoát `Ctrl+]`). Thấy log installer chạy = OK.
- **RAM host:** 3 VM × 3GB = 9GB. Đóng bớt app nặng khi Phase 2-3 thêm ArgoCD/Prometheus.
- **Mọi lệnh virsh dùng `sudo`** vì VM nằm trong libvirt system session (`qemu:///system`).
- **Điều chỉnh tài nguyên / mirror / version K8s:** sửa phần CẤU HÌNH đầu `02-create-vms.sh`
  và `05-prepare-nodes.sh` (kênh `v1.31`).
- **Không commit khóa/bí mật:** chỉ nhúng *public* SSH key; preseed sinh ra ở /tmp và
  /var/lib/libvirt/images (không nằm trong git).
