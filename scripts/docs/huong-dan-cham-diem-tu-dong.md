# Hướng dẫn chấm điểm tự động theo bộ tiêu chí đề thi PVNSkills

## 1. Mục đích

Bộ script trong thư mục [scripts/test](../scripts/test) được thiết kế để tự động kiểm tra toàn bộ tiêu chí đề thi theo mục II. Tiêu chí chấm điểm. Mỗi task thực hiện một kiểm tra cụ thể trên các máy ảo hoặc thông qua cấu hình DNS, firewall, reverse proxy, mail, LDAP, SSH, VPN và web service.

## 2. Điều kiện tiên quyết

Trước khi chạy chấm điểm, đảm bảo:

- Môi trường đề thi đã được triển khai đúng theo cấu hình của bài thi.
- Các host trong inventory đã sẵn sàng và có thể SSH vào được.
- Từ máy chấm điểm, bạn có khả năng truy cập các máy trong đề thi theo cấu hình trong [scripts/test/inventory/hosts.yaml](../scripts/test/inventory/hosts.yaml).
- Python và môi trường ảo đã được cài đặt đúng.

## 3. Cấu trúc chính của bộ chấm điểm

- [scripts/test/grading.py](../scripts/test/grading.py): điểm vào và orchestrate toàn bộ bộ tiêu chí.
- [scripts/test/tasks](../scripts/test/tasks): các task kiểm tra từng tiêu chí theo từng phần A1 đến A16.
- [scripts/test/processors/score_report.py](../scripts/test/processors/score_report.py): in báo cáo kết quả chấm điểm.
- [scripts/test/runner/tag_runner.py](../scripts/test/runner/tag_runner.py): cho phép chạy từng tiêu chí theo tag.

## 4. Chạy toàn bộ bộ chấm điểm

Từ thư mục gốc của project, chạy lệnh sau:

```bash
python scripts/test/grading.py
```

Nếu muốn hiển thị thêm thông tin chi tiết của từng lệnh và kết quả thực thi, dùng:

```bash
python scripts/test/grading.py -v
```

Nếu chạy trực tiếp trên máy đích (không qua SSH), dùng:

```bash
python scripts/test/grading.py --local
```

## 5. Chạy từng tiêu chí hoặc từng nhóm tiêu chí

Script hỗ trợ tùy chọn `-t/--tags` để chạy một hoặc nhiều task riêng lẻ. Cú pháp dùng tên task tương ứng với định nghĩa trong từng file, ví dụ:

```bash
python scripts/test/grading.py -t A01_01 A01_02
```

hoặc chạy từng phần lớn hơn:

```bash
python scripts/test/grading.py -t A04_01 A04_02 A04_03 A04_04 A04_05
```

Giải thích:

- `A01_01` tương ứng với task `task_A01_01` trong [scripts/test/tasks/criterion_a1.py](../scripts/test/tasks/criterion_a1.py).
- `A16_01` tương ứng với task `task_A16_01` trong [scripts/test/tasks/criterion_a16.py](../scripts/test/tasks/criterion_a16.py).

## 6. Quy trình chấm điểm chuẩn

### Bước 1: Kiểm tra môi trường

- Xác nhận inventory đã đúng tên host.
- Kiểm tra SSH tới từng host.
- Đảm bảo các máy `int-srv01`, `fw`, `mail`, `ha-prx01`, `ha-prx02`, `web01`, `web02`, `jamie-ws01` đều đang hoạt động.

### Bước 2: Chạy kiểm tra từng nhóm tiêu chí

Bộ script được tổ chức theo từng phần:

- A1–A4: LDAP, DNS, Samba, domain và service cấu hình ban đầu.
- A5–A8: Firewall, SNAT, WireGuard, transparent proxy.
- A9–A11: Mail, backup, SSH certificate auth.
- A12–A16: Reverse proxy, DNS DMZ, web server, Ansible, port forwarding và VPN.

Ví dụ:

```bash
python scripts/test/grading.py -t A01_01 A01_02 A01_03 A01_04
python scripts/test/grading.py -t A05_01 A06_01 A07_01 A07_02 A08_01
python scripts/test/grading.py -t A09_01 A09_02 A10_01 A10_02 A11_01 A11_02
python scripts/test/grading.py -t A12_01 A12_02 A12_03 A12_04 A12_05 A12_06 A12_07
python scripts/test/grading.py -t A13_01 A13_02 A13_03 A13_04 A13_05 A13_06
python scripts/test/grading.py -t A14_01 A14_02 A15_01 A15_02 A16_01 A16_02 A16_03 A16_04 A16_05
```

### Bước 3: Đọc báo cáo điểm

Sau khi chạy, script sẽ in ra từng task với trạng thái đạt/không đạt và trọng số tương ứng. Kết quả sẽ theo kiểu:

- `0.0` khi thất bại
- `full max_score` khi đạt đủ tiêu chí
- `verbose` sẽ in thêm lệnh thực thi và output tương ứng

### Bước 4: Ghi nhận thành tích

- Tổng điểm của từng tiêu chí được tính từ `max_score` của task.
- Nếu không đạt một task, cần kiểm tra cấu hình tương ứng và chạy lại task đó riêng lẻ.

## 7. Khắc phục khi chấm sai hoặc không đạt

### Vấn đề 1: Một số task luôn trả về 0 dù cấu hình đúng

- Kiểm tra logic điều kiện so sánh trong từng task, đặc biệt với chuỗi và giá trị thực tế trả về bởi lệnh.
- Ví dụ: một số task trước đây đang đánh giá sai vì dùng `and` trên chuỗi, dẫn tới điều kiện luôn true hoặc luôn false.

### Vấn đề 2: Một task không in đúng kết quả

- Đảm bảo mỗi `Result` trả về `result`, không dùng `msg` khi script báo cáo đọc `res.result`.
- Điều này đã được sửa ở task SNAT của A06.

### Vấn đề 3: Email echo chưa kiểm tra nội dung đúng

- Với mail phản hồi, cần kiểm tra toàn bộ các chuỗi quan trọng như địa chỉ `From`, `To` và header `report-type=delivery-status`.
- Điều này đã được bổ sung ở task A09_02.

### Vấn đề 4: Port forwarding WAN không phân biệt đúng UDP/TCP

- Cần đánh giá cả hai luồng: UDP/53 và TCP/53, đồng thời phân biệt trạng thái “udp ok”, “tcp ok”, hoặc “cả hai ok”.
- Điều này đã được sửa ở task A16_01.

## 8. Gợi ý chạy kiểm tra hiệu quả

- Chạy từng tiêu chí riêng để debug nhanh hơn.
- Dùng `-v` khi cần xem lệnh thực thi và output gốc.
- Nếu cần xác nhận cấu hình DNS hoặc firewall, hãy chụp output từ task liên quan rồi đối chiếu với thiết kế đề thi.

## 9. Kết luận

Bộ script đã được chỉnh lại để khớp với tiêu chí đề thi hơn, giảm sai lệch logic và đảm bảo chấm điểm tự động phản ánh chính xác trạng thái thực tế của hệ thống. Chạy đúng theo các bước trên sẽ giúp giám khảo và người học theo dõi tiến độ và điểm số một cách nhất quán.

## 10. Lưu ý

Kiểm tra xem đã cài xong chưa

Bạn có thể kiểm tra ngay:

python3 -c "import nornir; print(nornir.__version__)"

Nếu lệnh này chạy được, nghĩa là dependency đã được cài thành công.

---

## Tóm tắt

Lỗi là:

* [ModuleNotFoundError: No module named &#39;nornir&#39;](<vscode-file://vscode-app/c:/Users/Senyuwu/AppData/Local/Programs/Microsoft%20VS%20Code/8a7abeba6e/resources/app/out/vs/code/electron-browser/workbench/workbench.html>)

Khắc phục là:

```shell
cd /root/PVNSkills_2026-2
python3 -m pip install -r scripts/test/requirements.txt
python3 scripts/test/grading.py
```
