#!/bin/bash
set -e

# ========================================================
# Bài 4: Thiết lập Custom Network & Named Volume bằng Docker CLI
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Postgres ở lại trạng thái "starting" khá lâu ở lần khởi tạo đầu tiên (initdb),
# nên phải thăm dò bằng pg_isready thay vì chờ một khoảng thời gian cố định.
wait_db_ready() {
  for i in $(seq 1 30); do
    if docker exec db-server pg_isready -U postgres -d app_db >/dev/null 2>&1; then
      echo "PostgreSQL đã sẵn sàng (lần thăm dò thứ $i)."
      return 0
    fi
    sleep 2
  done
  echo "Lỗi: PostgreSQL chưa sẵn sàng sau 60 giây." >&2
  return 1
}

echo "=========================================================="
echo "BƯỚC 1: Dọn dẹp tài nguyên cũ nếu có"
echo "=========================================================="
docker rm -f app-container db-server 2>/dev/null || true
docker network rm app-net 2>/dev/null || true
docker volume rm db-data 2>/dev/null || true

echo "=========================================================="
echo "BƯỚC 2: Tạo Custom Bridge Network: app-net"
echo "=========================================================="
docker network create app-net
docker network ls | grep app-net

echo "=========================================================="
echo "BƯỚC 3: Tạo Named Volume: db-data"
echo "=========================================================="
docker volume create db-data
docker volume ls | grep db-data

echo "=========================================================="
echo "BƯỚC 4: Khởi chạy Database Container (PostgreSQL 15 Alpine)"
echo "=========================================================="
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=app_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secretpassword123 \
  postgres:15-alpine

echo "Đang đợi PostgreSQL khởi động sẵn sàng..."
wait_db_ready

echo "=========================================================="
echo "BƯỚC 5: Khởi chạy Backend Container tham gia app-net"
echo "=========================================================="
# Image backend dùng chung với Bài 3; đổi thành hw-backend:v1 (Bài 2) nếu bạn không có bản multistage
BACKEND_IMAGE="${BACKEND_IMAGE:-hw-backend:multistage}"

# Kiểm tra nếu chưa có image backend thì tự động build từ ex3
if ! docker image inspect "$BACKEND_IMAGE" >/dev/null 2>&1; then
  echo "Chưa tìm thấy image $BACKEND_IMAGE, tiến hành build từ ../ex3..."
  docker build -t "$BACKEND_IMAGE" "$SCRIPT_DIR/../ex3"
fi

docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -p 3000:3000 \
  "$BACKEND_IMAGE"

echo "=========================================================="
echo "BƯỚC 6: Kiểm tra DNS Resolution (Ping từ app-container sang db-server)"
echo "=========================================================="
docker exec app-container ping -c 2 db-server

echo "=========================================================="
echo "BƯỚC 7: Test Data Persistence (Lưu trữ dữ liệu bền vững)"
echo "=========================================================="
echo "7.1. Tạo bảng và thêm dữ liệu vào db-server:"
docker exec -i db-server psql -U postgres -d app_db -c "
CREATE TABLE IF NOT EXISTS test_data (
    id SERIAL PRIMARY KEY,
    content VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_data (content) VALUES ('Session 10 Persistent Data Verification');
SELECT * FROM test_data;
"

echo "7.2. Xóa cứng container db-server (docker rm -f db-server):"
docker rm -f db-server

echo "7.3. Khởi chạy lại container DB mới gắn cùng Volume db-data:"
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=app_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secretpassword123 \
  postgres:15-alpine

echo "Đang đợi container DB mới khởi động sẵn sàng..."
wait_db_ready

echo "7.4. Xác minh dữ liệu vẫn nguyên vẹn:"
docker exec -i db-server psql -U postgres -d app_db -c "SELECT * FROM test_data;"

echo "=========================================================="
echo "HOÀN TẤT: Kiểm tra Bài 4 thành công 100%!"
echo "=========================================================="
