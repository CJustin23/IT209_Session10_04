# Bài 4: Thiết lập Custom Network & Named Volume bằng Docker CLI

**Học viên:** Nguyễn Trường An — **Lớp:** HN-KS24-CNTT3 — **Môn:** IT209, Session 10
**Repository:** https://github.com/CJustin23/IT209_Session10_04

## 1. Mục tiêu bài tập
- **Custom Bridge Network**: Tạo mạng cầu nối tùy biến `app-net` cho phép các container giao tiếp nội bộ thông qua tên service/container (**DNS Resolution**) thay vì phụ thuộc vào địa chỉ IP động.
- **Named Volume**: Tạo và gắn Named Volume `db-data` vào thư mục `/var/lib/postgresql/data` của PostgreSQL container nhằm bảo toàn dữ liệu độc lập với vòng đời container.
- **Data Persistence**: Kiểm chứng tính toàn vẹn của dữ liệu sau khi xóa cứng container (`docker rm -f`) và tái tạo lại container mới gắn cùng volume.

---

## 2. Cấu trúc thư mục
Đường dẫn nộp bài trên GitHub: `homework/session_10/ex4/`

```text
homework/session_10/ex4/
├── commands.sh            # Script bash tự động hóa toàn bộ thao tác Docker CLI
└── README.md              # Báo cáo kỹ thuật và nhật ký kiểm tra chi tiết
```

---

## 3. Các bước thực hiện chi tiết

### 3.1. Tạo Custom Bridge Network & Named Volume
```bash
# Tạo mạng bridge nội bộ
docker network create app-net

# Tạo named volume lưu trữ dữ liệu DB
docker volume create db-data
```

### 3.2. Khởi chạy Database Container (PostgreSQL 15 Alpine)
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=app_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secretpassword123 \
  postgres:15-alpine
```

### 3.3. Khởi chạy Backend Container tham gia mạng
```bash
docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -p 3000:3000 \
  hw-backend:multistage
```

---

## 4. Kiểm tra và xác minh kết quả

### 4.1. Kiểm tra Network & Volume
```bash
# Kiểm tra network app-net đã tồn tại
docker network ls | grep app-net
# Output: def97b2ec0a6   app-net   bridge   local

# Kiểm tra volume db-data đã tồn tại
docker volume ls | grep db-data
# Output: local   db-data

# Kiểm tra các container tham gia network app-net
docker network inspect app-net
```

### 4.2. Kiểm tra DNS Resolution (Ping từ Backend sang DB)
```bash
docker exec -it app-container ping -c 2 db-server
```
**Kết quả thực tế:**
```text
PING db-server (172.20.0.2): 56 data bytes
64 bytes from 172.20.0.2: seq=0 ttl=64 time=0.119 ms
64 bytes from 172.20.0.2: seq=1 ttl=64 time=0.072 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.072/0.095/0.119 ms
```
> **Đánh giá:** Lệnh ping giải mã thành công hostname `db-server` sang địa chỉ IP nội bộ `172.20.0.2` của Database container nhờ cơ chế Docker Embedded DNS.

### 4.3. Kiểm tra Data Persistence (Lưu trữ bền vững)

**Bước 1: Tạo bảng và thêm dữ liệu mẫu vào DB:**
```bash
docker exec -i db-server psql -U postgres -d app_db -c "
CREATE TABLE IF NOT EXISTS test_data (
    id SERIAL PRIMARY KEY,
    content VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_data (content) VALUES ('Session 10 Persistent Data Verification');
SELECT * FROM test_data;
"
```
Output:
```text
 id |                content                 |         created_at         
----+----------------------------------------+----------------------------
  1 | Session 10 Persistent Data Verification| 2026-10-12 16:44:58.213456
(1 row)
```

**Bước 2: Xóa cứng Database Container:**
```bash
docker rm -f db-server
```

**Bước 3: Khởi chạy container mới gắn lại Volume `db-data`:**
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=app_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secretpassword123 \
  postgres:15-alpine
```

**Bước 4: Xác minh dữ liệu không bị mất:**
```bash
docker exec -i db-server psql -U postgres -d app_db -c "SELECT * FROM test_data;"
```
Output:
```text
 id |                content                 |         created_at         
----+----------------------------------------+----------------------------
  1 | Session 10 Persistent Data Verification| 2026-10-12 16:44:58.213456
(1 row)
```
> **Đánh giá:** Dữ liệu hoàn toàn nguyên vẹn sau khi container bị xóa cứng và tạo mới, chứng minh cơ chế Named Volume bảo toàn dữ liệu độc lập với vòng đời container.

---

## 5. Thực thi tự động bằng script
Chạy toàn bộ kịch bản bằng lệnh:
```bash
bash commands.sh
```

**Điều kiện trước khi chạy:**
- Docker daemon đang chạy, user thường truy cập được socket (không cần `sudo`).
- Script dùng image backend `hw-backend:multistage` (kết quả Bài 3). Nếu chưa có, script tự `docker build` từ thư mục `../ex3` tính theo vị trí của `commands.sh`; hãy đổi tên image trong biến `BACKEND_IMAGE` nếu bạn dùng image khác (ví dụ `hw-backend:v1` của Bài 2).
- Script thăm dò bằng `docker exec db-server pg_isready` (tối đa 60s) thay vì `sleep` cố định, vì lần khởi tạo đầu tiên Postgres phải chạy `initdb`.
- Bước 1 của script **xóa** container/network/volume cũ cùng tên (`app-container`, `db-server`, `app-net`, `db-data`) để chạy lại từ đầu — dữ liệu trong `db-data` sẽ mất khi chạy lại script.

## 6. Dọn dẹp tài nguyên
```bash
docker rm -f app-container db-server
docker network rm app-net
docker volume rm db-data
```
