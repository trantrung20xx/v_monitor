# Tài liệu mô tả hệ thống VMonitor

## 1. Mục đích

VMonitor tiếp nhận vị trí từ thiết bị qua MQTT hoặc REST, lưu dữ liệu vào PostgreSQL/PostGIS và cập nhật giao diện Flutter qua WebSocket. Hệ thống hỗ trợ:

- Giám sát vị trí và trạng thái online/offline.
- Xem lịch sử hành trình, điểm dừng và sự kiện di chuyển.
- Quản lý thiết bị và thiết bị MQTT đã phát hiện.
- Quản lý tài khoản, vai trò và thiết lập hệ thống.
- Tra cứu địa chỉ từ tọa độ qua dịch vụ geocoding.

## 2. Kiến trúc và luồng dữ liệu

### 2.1. Sơ đồ kiến trúc production

```mermaid
flowchart LR
    Device["Thiết bị GPS / IoT"]
    Broker["MQTT Broker<br/>Dịch vụ bên ngoài"]
    Client["Trình duyệt / Flutter Desktop"]
    Geocoding["Dịch vụ geocoding<br/>Photon hoặc Nominatim"]

    subgraph Server["Máy chủ Docker"]
        direction LR
        Caddy["web<br/>Caddy + Flutter Web<br/>Cổng 80 / 443"]
        Backend["backend<br/>FastAPI + MQTT worker<br/>REST + WebSocket"]
        Database[("db<br/>PostgreSQL 16 + PostGIS")]
        Volume[("postgres_data<br/>Dữ liệu bền vững")]

        Caddy <-->|"/api/* · /health · WebSocket"| Backend
        Backend <-->|"SQL bất đồng bộ"| Database
        Database --- Volume
    end

    Device -->|"Publish: &lt;MQTT_TOPIC_PREFIX&gt;/&lt;device_code&gt;"| Broker
    Broker -->|"Subscribe: &lt;MQTT_TOPIC_PREFIX&gt;/#"| Backend
    Client <-->|"HTTPS / WSS"| Caddy
    Backend -->|"Reverse geocoding"| Geocoding
```

MQTT Broker và dịch vụ geocoding không nằm trong `compose.yaml`. Địa chỉ kết nối được khai báo qua `.env.docker`.

### 2.2. Vai trò của từng service

| Service | Vai trò | Phạm vi truy cập |
|---|---|---|
| `web` | Phục vụ Flutter Web, kết thúc HTTPS và chuyển tiếp API/WebSocket | Public cổng `80`, `443` |
| `backend` | Xử lý REST, WebSocket, MQTT, xác thực và nghiệp vụ | Chỉ trong mạng Docker, cổng `8000` |
| `db` | Lưu dữ liệu nghiệp vụ và tọa độ không gian | Chỉ trong mạng Docker, cổng `5432` |
| `postgres_data` | Giữ dữ liệu PostgreSQL khi container được tạo lại | Docker volume, không public |

Caddy là điểm truy cập public duy nhất. REST, WebSocket và Flutter Web sử dụng chung `${DOMAIN}`; backend và database không mở cổng trực tiếp ra Internet.

### 2.3. Luồng tiếp nhận telemetry

1. Thiết bị publish bản tin đến `<MQTT_TOPIC_PREFIX>/<device_code>` trên MQTT Broker.
2. Client MQTT của backend đăng ký `<MQTT_TOPIC_PREFIX>/#`. Thread mạng Paho nhận bản tin, chuyển qua `call_soon_threadsafe` vào hàng chờ RAM, mặc định tối đa 20.000 bản tin.
3. Mặc định 8 worker bất đồng bộ lấy bản tin. Mỗi worker xử lý lần lượt từng bản tin: kiểm tra topic, JSON, thiết bị và quyền nhận dữ liệu. Thiết bị chưa đăng ký được ghi vào MQTT discovery; thiết bị bị khóa nhận dữ liệu được bỏ qua.
4. Giao dịch thứ nhất lưu `telemetry_messages` ở trạng thái `PENDING`; cặp `(device_id, message_id)` chống trùng nếu có `message_id`. Bản tin thiếu tọa độ được đánh dấu `SKIPPED`; dữ liệu vị trí sai hoặc xử lý lỗi được đánh dấu `FAILED` nếu ghi nhận lỗi thành công.
5. Với mẫu vị trí hợp lệ, giao dịch thứ hai ghi `location_samples`, cập nhật `device_latest_state`, chuyển telemetry sang `PROCESSED`, đồng thời ghi các `device_events` phát sinh và thông báo tương ứng vào `realtime_outbox`. Commit lưu cả giao dịch; rollback hủy cả giao dịch này.
6. Sau commit, worker chỉ đánh dấu device ID cần cập nhật rồi tiếp tục bản tin kế tiếp. Tác vụ tạo trạng thái mới nhất và tác vụ phát outbox chạy độc lập; hàng chờ riêng của mỗi WebSocket đảm nhiệm gửi mạng.
7. Flutter gộp cập nhật dashboard theo device ID và nhịp đã cấu hình. Lịch sử đầy đủ được đọc qua REST; việc gộp cập nhật không bỏ bớt mẫu GPS trong DB.

```mermaid
flowchart TD
    MQTT["Thiết bị → MQTT Broker"] --> Paho["Thread mạng Paho"]
    Paho --> Queue["Hàng chờ RAM: 20.000 bản tin"]
    Queue --> Workers["8 worker async<br/>Mỗi worker xử lý tuần tự"]
    Workers --> Raw["Giao dịch 1<br/>Telemetry PENDING"]
    Raw --> GPS["Giao dịch nghiệp vụ, commit cùng nhau<br/>GPS + latest state + sự kiện + outbox<br/>Telemetry PROCESSED nếu từ MQTT"]
    REST["POST /tracking/<br/>Sau xác thực và kiểm tra dữ liệu"] --> GPS
    GPS --> Dirty["Đánh dấu device ID cần cập nhật"]
    Dirty --> Snapshot["Tác vụ đọc trạng thái mới nhất<br/>Gộp ID, tạo lô"]
    GPS --> Outbox["Tác vụ phát outbox<br/>Nhận lô → gửi → ghi kết quả / hẹn lại"]
    Snapshot --> Send["Mỗi WebSocket: hàng chờ + tác vụ gửi riêng"]
    Outbox --> Send
    Send --> UI["Flutter: gộp theo device ID<br/>250–1.000 ms, mặc định 500 ms"]
    UI --> Catchup["Khi reconnect: lấy bù qua REST"]
```

`POST /tracking/` gọi cùng nghiệp vụ lưu GPS sau xác thực và validation, nhưng không đi qua hàng chờ MQTT và không tạo nhật ký MQTT `telemetry_messages`.

Các worker có thể hoàn thành khác thứ tự lấy bản tin. Khóa `FOR UPDATE` trên dòng `device_latest_state` đã tồn tại buộc các giao dịch cùng thiết bị lần lượt cập nhật dòng đó; các thiết bị khác vẫn có thể xử lý đồng thời. Mẫu đo đến trễ vẫn được lưu lịch sử và cập nhật thời điểm liên lạc, nhưng không ghi đè vị trí mới hơn. Hai mẫu có cùng `measured_at` có thể cập nhật trạng thái theo thứ tự xử lý.

Mã nguồn: [mqtt_service.py](../backend/app/services/mqtt_service.py), [TrackingService.add_location](../backend/app/services/tracking_service.py).

### 2.4. Luồng truy cập từ Flutter

| Yêu cầu | Đường đi | Kết quả |
|---|---|---|
| Mở ứng dụng web | Client → Caddy → tệp Flutter Web | Tải giao diện |
| Đăng nhập, xem thiết bị và lịch sử | Flutter → Caddy → FastAPI → PostgreSQL | Trả dữ liệu JSON |
| Nhận cập nhật trực tiếp | Flutter ⇄ Caddy ⇄ FastAPI WebSocket | Cập nhật trạng thái không cần tải lại |
| Tra cứu địa chỉ | Flutter → FastAPI → dịch vụ geocoding | Trả địa chỉ từ tọa độ |

Dashboard giữ dữ liệu theo device ID và chỉ áp dụng giá trị mới nhất của mỗi ID trong một đợt cập nhật. Khi tải REST trùng lúc có dữ liệu realtime, các thay đổi đến trong thời gian tải được ghép lại để phản hồi REST không ghi đè dữ liệu vừa nhận. Nếu tải bù thất bại, giao diện giữ dữ liệu hiện có và lên lịch thử lại. Màn hình chi tiết tải lại trạng thái, sự kiện và lịch sử khi reconnect; sự kiện được loại trùng theo ID.

Danh sách dùng widget dựng theo vùng cuộn và theo dõi thẻ đang hiển thị, kể cả vùng đệm cuộn nhỏ. Dashboard chỉ yêu cầu địa chỉ cho các thẻ này. Bản đồ nhóm marker theo ô pixel trong vùng nhìn; chạm cụm để phóng tới nhóm, hoặc mở danh sách khi các thiết bị vẫn trùng vị trí ở mức zoom tối đa.

Mã nguồn: [DashboardCubit](../lib/features/dashboard/dashboard_cubit.dart), [VisibleDevice](../lib/features/dashboard/widgets/visible_device.dart), [DeviceClusterLayer](../lib/features/map/widgets/device_cluster_layer.dart), [DeviceDetailCubit](../lib/features/device_detail/device_detail_cubit.dart).

### 2.5. Thứ tự khởi động Docker

1. `db` khởi động và vượt qua healthcheck PostgreSQL.
2. `backend` chạy `alembic upgrade head`, khởi động FastAPI và kết nối MQTT Broker.
3. `web` khởi động sau khi backend healthy; Caddy phục vụ Flutter Web và reverse proxy.

Caddy tự cấp chứng chỉ HTTPS khi DNS trỏ đúng về server và firewall cho phép cổng `80`, `443`.

### 2.6. Phần chạy đồng thời và phần chạy tuần tự

Lệnh khởi chạy hiện tại trong [server.py](../backend/app/server.py) không đặt nhiều Uvicorn worker. Với cấu hình một tiến trình backend, luồng nhận MQTT có thread mạng Paho riêng; các worker nghiệp vụ là `asyncio.Task`, không phải 8 thread xử lý CPU.

| Thành phần | Cách thực hiện |
|---|---|
| MQTT worker | 8 tác vụ cùng tiến triển khi chờ I/O; từng tác vụ chờ xử lý xong một bản tin mới lấy bản tin tiếp |
| Snapshot realtime và outbox | Hai tác vụ nền độc lập với worker GPS; mỗi tác vụ xử lý các lô của mình lần lượt |
| Gửi WebSocket | Mỗi client có một tác vụ gửi tuần tự; các client gửi đồng thời khi chờ mạng |
| Quét offline | Tác vụ nền riêng, mặc định kiểm tra mỗi 30 giây; ghi trạng thái, sự kiện và outbox cùng giao dịch |
| REST | Nhiều request có thể cùng chờ DB hoặc mạng; dùng chung pool DB với các tác vụ nền |
| Flutter | Xử lý trạng thái, timer và phân cụm trên isolate giao diện; các yêu cầu mạng có thể cùng chờ, không đồng nghĩa tính toán CPU chạy trên nhiều thread |
| Dịch địa chỉ ở backend | Các yêu cầu có thể cùng chờ, nhưng khóa dịch vụ chỉ cho một lượt gọi nhà cung cấp tại một thời điểm trong mỗi tiến trình |

`await` nhường thời gian thực thi cho tác vụ khác trong lúc chờ I/O. Tính toán đồng bộ kéo dài vẫn có thể làm chậm event loop. Các giới hạn RAM, pool và danh sách WebSocket thuộc từng tiến trình; không thể suy ra chỉ cần tăng số tiến trình là toàn bộ MQTT/realtime tự đồng bộ giữa chúng.

### 2.7. Outbox, hàng chờ client và phát lại

Có hai loại dữ liệu gửi giao diện:

- **Trạng thái mới nhất:** RAM giữ danh sách device ID cần đọc lại, gộp ID trùng; mặc định tối đa 10.000 ID, đọc theo lô 250, nghỉ 0,1 giây giữa các vòng. Nếu vượt giới hạn, server gửi `RESYNC_REQUIRED` để client tải lại qua REST. Dữ liệu trung gian có thể được gộp khi hiển thị; lịch sử GPS vẫn nằm trong DB.
- **Sự kiện từ tracking/presence:** thông báo được ghi vào bảng `realtime_outbox` cùng giao dịch nghiệp vụ và được tác vụ riêng phát lại khi cần. Các thông báo khác, như thay đổi thiết lập hoặc xóa thiết bị, dùng hàng chờ realtime; không phải mọi frame WebSocket đều được lưu outbox.

Một lượt phát outbox thực hiện lần lượt:

1. Lấy tối đa 250 dòng đã tới `available_at`, dùng `FOR UPDATE SKIP LOCKED` để bỏ qua dòng đang bị giao dịch khác khóa. Gắn `claim_token` riêng và đặt hạn giữ bằng `3 × REALTIME_SEND_TIMEOUT_SECONDS + 10`, mặc định 25 giây; commit rồi đóng session DB.
2. Đặt lô vào hàng chờ của các client và chờ kết quả gửi, không giữ kết nối DB. Mỗi client có tối đa 32 lô đang chờ trong RAM, cộng thêm tối đa một lô đang gửi. Đầy hàng chờ hoặc lỗi/timeout gửi thì ngắt riêng client đó, đóng với mã `1013`.
3. Mỗi tác vụ gửi có timeout mặc định 5 giây tính từ lúc lấy lô ra gửi. Cả lượt outbox chờ tối đa `2 × timeout`, mặc định 10 giây, gồm thời gian xếp hàng. Các tác vụ gửi độc lập, nhưng lượt outbox kế tiếp vẫn phải chờ lượt hiện tại kết thúc.
4. Mở session mới và chỉ sửa các dòng còn thuộc `claim_token` của lượt này. Thành công thì xóa thông báo chờ trong outbox, giữ nguyên lịch sử GPS/sự kiện. Có lỗi thì bỏ token và hẹn thử lại sau 2 giây; hiện không giới hạn số lần thử. Khi rỗi hoặc lỗi vòng phát, tác vụ đợi mặc định 0,25 giây trước lần kiểm tra tiếp.
5. Nếu backend dừng giữa chừng, dòng đã commit vẫn còn trong DB và được nhận lại khi hết hạn giữ. Token ngăn lượt gửi cũ hoàn tất muộn xóa dòng đã được lượt khác nhận lại.

“Gửi thành công” là hoàn tất thao tác gửi phía server, chưa có xác nhận rằng Flutter đã xử lý hoặc hiển thị. Khi không có client, outbox cũng được phép dọn; client kết nối sau lấy dữ liệu qua REST. Nếu một client đã nhận nhưng client khác lỗi, lần thử lại có thể gửi trùng ID sự kiện. Outbox không phải hộp thư lưu riêng cho từng client và không thay thế cơ chế lấy bù.

Mã nguồn: [stage_device_events và RealtimeOutboxService](../backend/app/services/realtime_outbox_service.py), [RealtimeService](../backend/app/services/realtime_service.py), [PresenceService](../backend/app/services/presence_service.py).

### 2.8. Tra cứu địa chỉ không giữ kết nối DB

Luồng xử lý: **xác thực bằng session DB ngắn → đóng session, trả kết nối → kiểm tra cache/gộp tọa độ trùng → chờ dịch vụ địa chỉ → trả JSON**. Ví dụ dịch vụ địa chỉ mất 5 giây, yêu cầu HTTP vẫn chờ nhưng kết nối DB dùng xác thực đã được trả để các yêu cầu khác sử dụng.

Frontend mặc định có cache 512 tọa độ, tối đa 32 yêu cầu địa chỉ đang chạy hoặc chờ, tối đa 4 HTTP request đồng thời. Backend có cache 5.000 tọa độ, tối đa 32 tọa độ đang xử lý hoặc chờ; chỉ một lượt gọi nhà cung cấp tại một thời điểm. Hai cache độc lập, hết hạn sau 3.600 giây và loại mục ít được dùng gần đây khi đầy. Backend gộp yêu cầu có tọa độ trùng sau khi làm tròn 5 chữ số thập phân.

Deadline backend mặc định 10 giây bao gồm đợi khóa nhà cung cấp và các lần thử. Hàng chờ đầy, hết thời gian hoặc nhà cung cấp lỗi sẽ trả `503`; frontend vẫn có thể hiển thị tọa độ hoặc địa chỉ đã có. Trên dashboard, mỗi thiết bị đang xem có tối đa một yêu cầu địa chỉ đang chạy và khoảng nghỉ mặc định 15 giây trước lần lấy tiếp. Kết quả địa chỉ cũ không được gắn vào tọa độ mới hơn.

Mã nguồn: [require_viewer_with_short_session](../backend/app/api/auth_dependencies.py), [endpoint geocoding](../backend/app/api/v1/geocoding.py), [GeocodingService](../backend/app/services/geocoding_service.py), [GeocodingRepository](../lib/data/repositories/geocoding_repository.dart).

## 3. Cấu trúc mã nguồn

| Đường dẫn | Nội dung |
|---|---|
| `lib/app` | router, theme và khung ứng dụng Flutter |
| `lib/core` | cấu hình, REST client, WebSocket và widget dùng chung |
| `lib/features` | đăng nhập, dashboard, chi tiết thiết bị, hành trình, cài đặt |
| `backend/app/api/v1` | endpoint REST và WebSocket |
| `backend/app/services` | nghiệp vụ thiết bị, tracking, MQTT, realtime, auth |
| `backend/app/models` | model SQLAlchemy |
| `backend/app/schemas` | hợp đồng request/response Pydantic |
| `backend/alembic` | lịch sử migration database |
| `backend/tests` | unit test backend và script mô phỏng MQTT/DB/HTTP/WebSocket |
| `test` | unit và widget test Flutter |
| `config` | cấu hình frontend tại thời điểm build |
| `docker` | image backend, image Flutter Web và Caddy |

## 4. Cơ sở dữ liệu

Các bảng nghiệp vụ hiện hành:

| Bảng | Mục đích |
|---|---|
| `devices` | thông tin và quyền nhận dữ liệu của thiết bị |
| `device_latest_state` | trạng thái mới nhất và thời điểm xuất hiện gần nhất |
| `location_samples` | lịch sử tọa độ bất biến |
| `telemetry_messages` | nhật ký gói MQTT và chống trùng |
| `device_events` | sự kiện bắt đầu/dừng di chuyển và sự kiện thiết bị |
| `realtime_outbox` | thông báo sự kiện đã commit đang chờ phát hoặc thử lại; tách khỏi lịch sử sự kiện |
| `mqtt_device_sightings` | thiết bị MQTT đã thấy nhưng chưa đăng ký |
| `user_accounts` | tài khoản, vai trò, khóa đăng nhập và phiên bản token |
| `user_settings` | thiết lập riêng của tài khoản |
| `system_settings` | thiết lập dùng chung toàn hệ thống |
| `audit_logs` | nhật ký thao tác quản trị |

`alembic_version` và `spatial_ref_sys` là dữ liệu hạ tầng của Alembic/PostGIS, không phải bảng nghiệp vụ để xóa.

Migration mới phải được tạo thành revision mới. Không sửa hoặc xóa migration đã chạy trên production. Trước mọi thay đổi schema phải sao lưu database và thử trên bản sao.

Database cũ có bảng nghiệp vụ nhưng thiếu hoặc rỗng `alembic_version` phải được sao lưu và thử nâng cấp trên bản sao trước. Không tự chạy `alembic stamp` trên production khi chưa xác định chính xác revision tương ứng với schema hiện có.

Revision mới nhất trong mã nguồn là [`c8e0f2a4b6d8`](../backend/alembic/versions/c8e0f2a4b6d8_add_realtime_outbox_and_dashboard_interval.py), kế tiếp `d8e9f0a1b2c3`. Revision này thêm `realtime_outbox` và `system_settings.dashboard_update_interval_ms`, mặc định 500, ràng buộc 250–1.000 ms. Đây là revision trong source; cần kiểm tra `alembic current` tại môi trường triển khai để biết DB đã nâng cấp hay chưa.

### 4.1. Kho kết nối DB dùng chung

[database.py](../backend/app/core/database.py) tạo một engine và pool cho mỗi tiến trình. Mặc định `DATABASE_POOL_SIZE=10`, `DATABASE_MAX_OVERFLOW=10`: tối đa 20 kết nối được mở theo nhu cầu, không phải luôn có sẵn 20 kết nối. REST, MQTT, outbox và presence dùng chung pool này.

Session là phạm vi làm việc của một request hoặc tác vụ, không phải khóa cho phép toàn hệ thống chỉ ghi một lần. Khi cần SQL, session mượn kết nối; kết thúc giao dịch bằng commit/rollback sẽ trả kết nối, câu SQL sau có thể mượn lại. Thoát `async with AsyncSessionLocal()` đóng session và giải phóng tài nguyên còn giữ. Không chia sẻ một session để nhiều tác vụ cùng thực hiện SQL.

Khi cả 20 kết nối đều bận, tác vụ mới chờ tối đa `DATABASE_POOL_TIMEOUT_SECONDS=30`, rồi báo lỗi nếu vẫn không mượn được. `pool_pre_ping` kiểm tra kết nối trước khi cấp; recycle mặc định 1.800 giây thay kết nối quá tuổi khi mượn lại, không cắt giao dịch đang chạy. PostgreSQL có thể xử lý nhiều giao dịch đồng thời; những giao dịch cùng khóa một dòng mới phải chờ nhau. Số kết nối đang dùng thực tế cần quan sát ở runtime, không suy ra từ giới hạn cấu hình.

## 5. Xác thực và phân quyền

- `AUTH_REQUIRED=true` là cấu hình production bắt buộc.
- `JWT_SECRET` phải có ít nhất 32 ký tự và phải được giữ bí mật.
- Vai trò `ADMIN` quản trị tài khoản, thiết bị và thiết lập hệ thống.
- Vai trò `USER` sử dụng chức năng giám sát được cấp phép.
- `user_accounts.is_active` là quyền đăng nhập của tài khoản, không phải trạng thái thiết bị.
- Trạng thái thiết bị sử dụng `is_online`, được cập nhật khi nhận GPS hợp lệ và khi tác vụ presence phát hiện quá hạn liên lạc. Ngưỡng đang dùng lấy từ thiết lập hệ thống `offline_timeout_seconds`; `DEVICE_OFFLINE_TIMEOUT_SECONDS` là giá trị dự phòng khi khởi tạo thiết lập.
- Thay đổi mật khẩu, vai trò hoặc trạng thái tài khoản làm tăng `token_version`, từ đó thu hồi token cũ.

Không có API đăng ký công khai. Tài khoản quản trị đầu tiên được tạo bằng script dòng lệnh.

## 6. API và WebSocket

Tiền tố mặc định: `/api/v1`.

| Nhóm | Endpoint chính |
|---|---|
| Auth | `POST /auth/login`, `GET /auth/me`, `POST /auth/change-password`, `GET/PATCH /auth/settings` |
| Devices | `GET/POST /devices/`, `GET/PATCH/DELETE /devices/{device_id}` và danh sách MQTT discovery |
| Tracking | `POST /tracking/`, `GET /tracking/{device_id}/history`, `/history/range`, `/events` |
| Geocoding | `GET /geocoding/reverse` |
| Users | `GET/POST /users/`, `PATCH /users/{user_id}`, `POST /users/{user_id}/reset-password` |
| System | `GET/PATCH /system/settings` |
| Realtime | `WS /ws` |
| Health | `GET /health`, không có tiền tố `/api/v1` |

REST sử dụng header:

```http
Authorization: Bearer <access_token>
```

Khi mở WebSocket với xác thực bật, frame đầu tiên phải được gửi trong 10 giây:

```json
{"type":"AUTH","access_token":"<access_token>"}
```

Server trả `{"type":"AUTH_OK"}` khi hợp lệ. Heartbeat sử dụng `PING` và `PONG`. Client cũ dùng frame `AUTH` như trên tiếp tục nhận `DEVICE_UPDATE` và `DEVICE_EVENT` riêng lẻ. Flutter hiện tại đăng ký khả năng nhận lô:

```json
{"type":"AUTH","access_token":"<access_token>","realtime_batches":true}
```

Khi tắt xác thực trong môi trường thử nghiệm, client có thể gửi `{"type":"CLIENT_CAPABILITIES","realtime_batches":true}`. Server chỉ gửi định dạng gộp cho client đã đăng ký:

| Frame | Nội dung và cách xử lý |
|---|---|
| `DEVICE_UPDATES` | Mảng `devices` chứa trạng thái mới nhất; WebsocketClient tách thành các cập nhật theo device ID |
| `REALTIME_BATCH` | Mảng `messages` chứa các frame sự kiện; WebsocketClient chuyển tiếp từng sự kiện tới luồng nghiệp vụ |
| `RESYNC_REQUIRED` | Yêu cầu tải lại dữ liệu qua REST |

Sau `AUTH_OK` hoặc tín hiệu lấy bù, dashboard tải lại danh sách, màn hình chi tiết đang mở tải lại dữ liệu của thiết bị và repository thiết lập tải lại cấu hình. Reconnect bù bằng trạng thái/lịch sử trong DB, không yêu cầu server giữ mọi frame bị lỡ. Mã nguồn: [WebsocketClient](../lib/core/network/websocket_client.dart), [endpoint WebSocket](../backend/app/api/v1/websocket.py).

## 7. Hợp đồng MQTT

Topic:

```text
<MQTT_TOPIC_PREFIX>/<device_code>
```

Ví dụ payload:

```json
{
  "message_id": "a0b1c2d3-e4f5-4678-9012-3456789abcde",
  "latitude": 10.7769,
  "longitude": 106.7009,
  "altitude_m": 12.5,
  "speed_mps": 4.2,
  "heading_deg": 180.0,
  "measured_at": "2026-09-04T08:00:00Z"
}
```

Quy ước:

- `message_id` phải duy nhất cho mỗi lần đo để chống xử lý trùng khi dùng QoS 1.
- `latitude` và `longitude` bắt buộc để tạo mẫu vị trí.
- `altitude_m`, `speed_mps`, `heading_deg`, `measured_at` là dữ liệu tùy chọn được hỗ trợ.
- `heading_deg` nằm trong khoảng từ `0` đến nhỏ hơn `360`; `speed_mps` không âm.
- `device_code` phải trùng thiết bị đã đăng ký. Thiết bị chưa đăng ký được ghi nhận vào danh sách MQTT discovery.

Gửi dữ liệu thử:

```powershell
$env:DEVICE_CODE="DEVICE_CODE_THAT"
.\.venv\Scripts\python.exe scripts\test_mqtt.py
```

Script đọc cấu hình MQTT từ `backend/.env` và phát QoS 1.

## 8. Cấu hình

### 8.1 Frontend Flutter

Flutter nhận cấu hình tại thời điểm build qua `--dart-define-from-file`:

| File | Mục đích |
|---|---|
| `config/development.json` | backend cục bộ |
| `config/cloudflare.json` | backend qua Cloudflare Tunnel |
| `config/production.json` | domain production |

Biến quan trọng:

- `API_BASE_URL`: URL đầy đủ, gồm `/api/v1`.
- `WS_PATH`: mặc định `/api/v1/ws`.
- `WS_BASE_URL`: chỉ khai báo khi WebSocket dùng host khác REST.
- `CONNECT_TIMEOUT_SECONDS`: timeout mở kết nối HTTP.

Khi `WS_BASE_URL` để trống, ứng dụng tự suy ra `ws://` hoặc `wss://` từ `API_BASE_URL`. Thay đổi file JSON không ảnh hưởng bản đã build; phải build lại Flutter.

Các biến hiệu năng tùy chọn trong [AppConfig](../lib/core/config/app_config.dart) có thể thêm vào file JSON hoặc truyền bằng `--dart-define` khi build Flutter độc lập:

| Biến frontend | Mặc định | Ý nghĩa |
|---|---|---|
| `GEOCODING_CACHE_SIZE` | 512 | Số tọa độ giữ trong cache địa chỉ |
| `GEOCODING_CACHE_TTL_SECONDS` | 3.600 | Tuổi cache, tính bằng giây |
| `GEOCODING_MAX_PENDING` | 32 | Tổng yêu cầu địa chỉ đang chạy và chờ |
| `GEOCODING_CONCURRENCY` | 4 | Số HTTP request địa chỉ đồng thời tới backend |
| `GEOCODING_REFRESH_SECONDS` | 15 | Khoảng nghỉ giữa các lần tra địa chỉ của thiết bị trên dashboard |
| `DASHBOARD_STATUS_REFRESH_SECONDS` | 5 | Chu kỳ tính lại trạng thái theo thời gian và thử tải bù còn lỗi |
| `MAP_CLUSTER_CELL_PIXELS` | 80 | Kích thước ô nhóm marker; lớp bản đồ giới hạn trong 40–200 pixel |

Các biến này thuộc bản dựng Flutter, độc lập với biến cùng tên của backend. Riêng nhịp gộp cập nhật dashboard được lưu trong DB và chỉnh khi ứng dụng đang chạy, xem mục 8.4; không dùng `DASHBOARD_STATUS_REFRESH_SECONDS` để chỉnh nhịp đó.

### 8.2 Backend chạy cục bộ

Backend đọc biến môi trường và `backend/.env`. File này không được commit.

| Nhóm | Biến cần kiểm tra |
|---|---|
| API | `API_HOST`, `API_PORT`, `API_RELOAD`, `CORS_ORIGINS` |
| Database | `DATABASE_URL`, `DATABASE_POOL_*` |
| MQTT | `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD`, `MQTT_USE_TLS`, `MQTT_TOPIC_PREFIX` |
| Auth | `AUTH_REQUIRED`, `JWT_SECRET`, giới hạn đăng nhập sai |
| Presence | `DEVICE_OFFLINE_TIMEOUT_SECONDS`, `DEVICE_OFFLINE_SCAN_INTERVAL_SECONDS` |
| Geocoding | `GEOCODING_PROVIDER`, `GEOCODING_BASE_URL`, `GEOCODING_USER_AGENT` |
| Realtime | `REALTIME_*`, xem bảng dưới |

`DATABASE_URL` bắt buộc dùng dạng:

```text
postgresql+asyncpg://USER:PASSWORD@HOST:5432/DATABASE
```

`CORS_ORIGINS` là origin frontend, ví dụ `https://monitor.example.com`; không phải địa chỉ bind của backend. Production không dùng `*`.

Các giá trị dưới đây là mặc định trong [config.py](../backend/app/core/config.py), không phải số kết nối hay mức tải đang đo được. Khi chạy backend trực tiếp, có thể khai báo trong `backend/.env` hoặc môi trường tiến trình rồi khởi động lại:

| Biến backend | Mặc định | Ý nghĩa |
|---|---|---|
| `DATABASE_POOL_SIZE` / `DATABASE_MAX_OVERFLOW` | 10 / 10 | Pool cơ bản và số kết nối được tăng tạm; tổng tối đa 20 mỗi tiến trình |
| `DATABASE_POOL_TIMEOUT_SECONDS` | 30 | Hạn chờ mượn kết nối DB |
| `DATABASE_POOL_RECYCLE_SECONDS` | 1.800 | Tuổi kết nối trước khi thay lúc mượn lại |
| `DATABASE_CONNECT_TIMEOUT_SECONDS` | 10 | Hạn mở kết nối DB |
| `MQTT_WORKER_COUNT` / `MQTT_QUEUE_SIZE` | 8 / 20.000 | Số worker async và sức chứa hàng chờ bản tin trong RAM |
| `REALTIME_FLUSH_INTERVAL_SECONDS` | 0,1 | Khoảng nghỉ giữa các vòng tạo trạng thái gửi giao diện |
| `REALTIME_BATCH_SIZE` | 250 | Số thiết bị hoặc sự kiện tối đa mỗi lô |
| `REALTIME_PENDING_DEVICE_LIMIT` | 10.000 | Số device ID khác nhau chờ tạo trạng thái; vượt giới hạn yêu cầu client lấy bù |
| `REALTIME_CLIENT_QUEUE_SIZE` | 32 | Số lô chờ tối đa cho mỗi WebSocket |
| `REALTIME_SEND_TIMEOUT_SECONDS` | 5 | Hạn gửi một lô cho từng client; cũng là cơ sở tính hạn chờ outbox và hạn giữ dòng |
| `REALTIME_OUTBOX_POLL_SECONDS` | 0,25 | Khoảng nghỉ khi vòng phát chưa có dữ liệu hoặc gặp lỗi |
| `REALTIME_OUTBOX_RETRY_SECONDS` | 2 | Khoảng chờ hẹn phát lại sau khi ghi nhận gửi thất bại |
| `GEOCODING_CACHE_SIZE` / `GEOCODING_CACHE_TTL_SECONDS` | 5.000 / 3.600 | Số tọa độ cache backend và thời gian sống tính bằng giây |
| `GEOCODING_MAX_PENDING` | 32 | Số tọa độ đang xử lý hoặc chờ ở backend |
| `GEOCODING_REQUEST_TIMEOUT_SECONDS` | 10 | Deadline tổng cho một tác vụ tra địa chỉ, gồm chờ và thử lại |
| `GEOCODING_TIMEOUT_SECONDS` | 8 | Timeout HTTP tới nhà cung cấp; deadline tổng vẫn giới hạn toàn tác vụ |
| `GEOCODING_RETRY_ATTEMPTS` / `GEOCODING_RETRY_DELAY_SECONDS` | 2 / 0,5 | Tổng số lần gọi tối đa, gồm lần đầu, và khoảng nghỉ giữa các lần |

Khi khai báo số thập phân trong `.env`, dùng dấu chấm, ví dụ `REALTIME_FLUSH_INTERVAL_SECONDS=0.1`.

### 8.3 Docker production

Cấu hình vận hành thường xuyên nằm trong `.env.docker`. [compose.yaml](../compose.yaml) chỉ chuyển các biến đã khai báo trong `backend.environment` vào container; thêm tên biến tùy ý trong file `.env.docker` không tự làm biến đó xuất hiện trong backend. Không sửa source khi chỉ đổi domain, mật khẩu hoặc broker.

Compose hiện truyền toàn bộ 7 biến `REALTIME_*` trong bảng trên và 4 biến `GEOCODING_CACHE_SIZE`, `GEOCODING_CACHE_TTL_SECONDS`, `GEOCODING_MAX_PENDING`, `GEOCODING_REQUEST_TIMEOUT_SECONDS`. Có thể thêm chúng vào `.env.docker` để ghi đè mặc định rồi chạy lại `docker compose --env-file .env.docker up -d`. File mẫu chỉ liệt kê cấu hình vận hành cơ bản, không bắt buộc có sẵn tất cả các biến này.

Các biến pool DB, số worker/hàng chờ MQTT và timeout/retry HTTP tới nhà cung cấp chưa được Compose truyền riêng; container dùng mặc định backend. Muốn thay chúng trong Docker phải bổ sung ánh xạ môi trường ở Compose hoặc file override. Docker Web hiện chỉ truyền một số `--dart-define` trong [docker/web.Dockerfile](../docker/web.Dockerfile), nên thêm biến hiệu năng Flutter vào `.env.docker` cũng không thay bản dựng web.

### 8.4 Thiết lập thay đổi ngay khi đang chạy

Quản trị viên chỉnh **Nhịp cập nhật giao diện** trong cài đặt hệ thống. Trường API là `dashboard_update_interval_ms`, mặc định **500 ms**, chỉ nhận **250–1.000 ms**. `PATCH /system/settings` yêu cầu quyền `ADMIN`, lưu DB và nhật ký quản trị theo luồng thiết lập hiện có; giá trị ngoài khoảng bị từ chối với `422`.

```json
{"dashboard_update_interval_ms":750}
```

Đây là thiết lập chung cho dashboard của hệ thống, không phải tùy chọn riêng từng người dùng. Flutter áp dụng nhịp mới khi nhận thay đổi thiết lập và tải lại thiết lập khi reconnect; không cần build lại. Giá trị này điều khiển thời gian gộp hiển thị, không đổi tần suất thiết bị gửi GPS, không cắt mẫu lịch sử và không phải cam kết độ trễ đầu cuối luôn dưới 1 giây. Độ trễ thực tế còn gồm hàng chờ MQTT, xử lý DB, phát mạng và tải thiết bị chạy Flutter.

Mã nguồn: [schema](../backend/app/schemas/system_settings.py), [SystemSettingsService](../backend/app/services/system_settings_service.py), [TrackingSettingsCard](../lib/features/settings/widgets/tracking_settings_card.dart).

## 9. Quy trình triển khai Docker từ đầu

### 9.1 Chuẩn bị server

```bash
docker --version
docker compose version
git --version
```

`docker version` phải hiển thị cả `Client` và `Server`. Chỉ có phần `Client` nghĩa là Docker daemon chưa chạy.

Yêu cầu DNS `A` trỏ về server và firewall cho phép TCP `80`, `443`.

### 9.2 Tạo cấu hình

```bash
cp .env.docker.example .env.docker
openssl rand -hex 24
openssl rand -hex 32
nano .env.docker
```

Các giá trị bắt buộc:

- `DOMAIN`: domain thật đã trỏ DNS về server; phải thay giá trị mẫu `monitor.example.com`.
- `POSTGRES_DB`, `POSTGRES_USER`: tên database và tài khoản PostgreSQL.
- `POSTGRES_PASSWORD`: kết quả `openssl rand -hex 24`.
- `JWT_SECRET`: kết quả `openssl rand -hex 32`.
- `MQTT_*`: host, cổng, xác thực, TLS và topic prefix của broker production.

`DOMAIN` chỉ chứa hostname, không có `http://`, `https://`, đường dẫn hoặc dấu `/` cuối. Mật khẩu PostgreSQL trong cấu hình hiện tại chỉ nên chứa chữ và số vì được ghép trực tiếp vào `DATABASE_URL`.

Kiểm tra cấu hình trước khi chạy:

```bash
docker compose --env-file .env.docker config --quiet
```

### 9.3 Khởi động và xác nhận

```bash
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
docker compose --env-file .env.docker logs backend --tail=100
```

Kiểm tra lần lượt:

1. Service `db`, `backend`, `web` ở trạng thái chạy; `db` và `backend` đạt `healthy`.
2. `https://<DOMAIN>/health` trả HTTP `200`, `"status":"ok"`, `"database":"connected"`, `mqtt.connected: true` và `mqtt.subscribed: true`.
3. Trang `https://<DOMAIN>` tải được giao diện đăng nhập.
4. Log backend không có lỗi migration, database hoặc MQTT lặp liên tục.

Endpoint `/health` vẫn có thể trả HTTP `200` khi `"status":"degraded"`; trạng thái này chỉ xác nhận API còn phản hồi, chưa xác nhận pipeline database và MQTT đã sẵn sàng đầy đủ.

Tạo quản trị viên đầu tiên:

```bash
docker compose --env-file .env.docker exec backend \
  python scripts/create_admin.py --username admin --full-name "Quản trị viên"
```

Tên đăng nhập dài tối thiểu 3 ký tự. Mật khẩu được nhập ẩn, dài từ 8 đến 128 ký tự.

### 9.4 Cập nhật

```bash
git pull
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
```

### 9.5 Sao lưu database

```bash
mkdir -p backups
docker compose --env-file .env.docker exec -T db sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "backups/v_monitor-$(date +%F-%H%M).dump"
```

Kiểm tra file sao lưu có dung lượng lớn hơn `0` trước khi cập nhật schema hoặc server.

### 9.6 Dừng hệ thống

```bash
docker compose --env-file .env.docker down
```

Lệnh trên giữ nguyên volume dữ liệu. Không thêm `--volumes` trên production nếu không có kế hoạch xóa toàn bộ database và chứng chỉ.

### 9.7 Chạy thử Docker trên Windows

Quy trình này chạy Flutter Web, FastAPI và PostgreSQL/PostGIS bằng Docker Desktop. Docker Desktop phải dùng Linux containers và hiển thị `Engine running`.

Kiểm tra Docker:

```powershell
docker version
docker compose version
```

`docker version` phải có cả `Client` và `Server`. Lỗi đường dẫn `dockerDesktopLinuxEngine` hoặc `The system cannot find the file specified` nghĩa là Docker Engine chưa chạy. Khôi phục theo thứ tự:

```powershell
wsl --shutdown
```

Sau đó mở lại Docker Desktop, chờ `Engine running` và kiểm tra lại `docker version`.

Tạo cấu hình local tại thư mục gốc:

```powershell
Copy-Item .env.docker.example .env.docker
[guid]::NewGuid().ToString("N")
[guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
notepad .env.docker
```

Thay các giá trị sau và giữ nguyên các biến còn lại:

```env
DOMAIN=localhost
POSTGRES_PASSWORD=<kết quả lệnh tạo chuỗi thứ nhất>
JWT_SECRET=<kết quả lệnh tạo chuỗi thứ hai>
MQTT_HOST=broker.emqx.io
MQTT_PORT=1883
MQTT_USE_TLS=false
MQTT_TOPIC_PREFIX=v_monitor/windows_test
```

Khởi động:

```powershell
docker compose --env-file .env.docker config --quiet
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
```

Ba container `v-monitor-db-1`, `v-monitor-backend-1`, `v-monitor-web-1` phải xuất hiện; `db` và `backend` phải đạt `healthy`.

Kiểm tra bằng URL thô, không thêm dấu `[]` hoặc `()`:

```powershell
curl.exe -k https://localhost/health
```

Kết quả sẵn sàng phải có `"status":"ok"`. Caddy dùng chứng chỉ HTTPS nội bộ cho `localhost`, vì vậy trình duyệt có thể hiển thị cảnh báo chứng chỉ trong môi trường thử nghiệm.

Tạo tài khoản quản trị và mở giao diện:

```powershell
docker compose --env-file .env.docker exec backend python scripts/create_admin.py --username admin --full-name "Quản trị viên"
Start-Process https://localhost
```

Dừng nhưng giữ dữ liệu:

```powershell
docker compose --env-file .env.docker down
```

`docker compose --env-file .env.docker down -v` xóa database, tài khoản, lịch sử và chứng chỉ local; chỉ dùng khi cần tạo lại toàn bộ môi trường thử nghiệm.

## 10. Chạy cục bộ

### 10.1 Windows

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
Copy-Item backend\.env.example backend\.env
```

Sửa `backend/.env`, tạo database PostgreSQL có PostGIS, sau đó chạy:

```powershell
.\run_backend.bat
```

Mở terminal khác:

```powershell
flutter pub get
flutter run -d windows --dart-define-from-file=config/development.json
```

Tạo tài khoản quản trị cục bộ sau khi backend và database đã khởi động:

```powershell
.\.venv\Scripts\python.exe backend\scripts\create_admin.py --username admin --full-name "Quản trị viên"
```

### 10.2 Linux hoặc macOS

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r backend/requirements.txt
cp backend/.env.example backend/.env
cd backend
../.venv/bin/python -m alembic upgrade head
../.venv/bin/python -m app.server
```

Mở terminal khác tại thư mục gốc:

```bash
flutter pub get
flutter run --dart-define-from-file=config/development.json
```

## 11. Kiểm thử và build

Chạy tại thư mục gốc sau mọi thay đổi:

```powershell
flutter analyze
flutter test
.\.venv\Scripts\python.exe -m unittest discover -s backend\tests -v
docker compose --env-file .env.docker.example config --quiet
```

Build production:

Trước khi build Flutter độc lập, thay `API_BASE_URL` trong `config/production.json` bằng `https://<DOMAIN>/api/v1`. Giá trị trong file mẫu `https://api.example.com/api/v1` không phải endpoint sử dụng thật.

```powershell
flutter build web --release --dart-define-from-file=config/production.json
flutter build windows --release --dart-define-from-file=config/production.json
```

Docker Web không đọc `config/production.json`; `docker/web.Dockerfile` tạo `API_BASE_URL` từ `DOMAIN` trong `.env.docker` khi build image.

Phân phối Windows bằng toàn bộ thư mục `build/windows/x64/runner/Release`. File `v_monitor.exe` không chạy độc lập nếu thiếu DLL, plugin và thư mục `data` đi kèm.

### 11.1 Mô phỏng bằng MQTT, DB, HTTP và WebSocket thật

[integration_realtime_performance.py](../backend/tests/integration_realtime_performance.py) tạo database mới tên `vmonitor_perf_test_<id>` trên PostgreSQL cục bộ, chạy migration upgrade → downgrade revision mới → upgrade trên DB thử nghiệm, rồi mở broker AMQTT và backend qua TCP loopback. Script kiểm tra dữ liệu lưu, WebSocket nhận lô và client cũ nhận frame riêng, outbox commit/rollback/phát lại, địa chỉ chậm và nhịp dashboard lưu qua API.

Điều kiện: môi trường Python đã cài `backend/requirements.txt`, có lệnh `uv` trong PATH để chạy AMQTT bằng Python 3.13, và `DATABASE_URL` trỏ PostgreSQL cục bộ có PostGIS. Tài khoản DB cần quyền tạo database và tạo extension cho DB thử nghiệm. Broker thử được mở riêng, không phát tải mô phỏng vào broker MQTT đang vận hành. Nhà cung cấp địa chỉ là HTTP stub có điều khiển độ trễ; đây không phải đo tốc độ Photon/Nominatim thật.

Chạy tại thư mục gốc:

```powershell
.\.venv\Scripts\python.exe backend\tests\integration_realtime_performance.py --devices 5000
```

Mỗi lần chạy ghi kết quả và log tại `build/performance/vmonitor_perf_test_<id>/`. Database thử được giữ lại; script không sửa schema hay dữ liệu của database gốc. `environment.json` trong thư mục kết quả chứa thông tin kết nối và bí mật thử nghiệm, không đưa file này vào Git hoặc báo cáo chia sẻ.

Để kiểm tra thêm mất kết nối và hết hạn giữ outbox, chạy mô phỏng với `--keep-server`, chờ `REAL_INTEGRATION_CHECKS_PASSED`, sau đó dùng terminal thứ hai:

```powershell
$runDir = 'build/performance/vmonitor_perf_test_<id thực tế của lần chạy>'
.\.venv\Scripts\python.exe backend\tests\verify_realtime_recovery.py $runDir
New-Item -ItemType File -Path (Join-Path $runDir 'stop-server') -Force
```

Script recovery ghi thêm một mẫu GPS vào DB thử trong lúc WebSocket ngắt, kiểm tra trạng thái lấy bù và lịch sử qua REST sau reconnect; đồng thời tạo một thông báo đang được giữ để kiểm tra phát lại sau hết hạn. File `stop-server` yêu cầu harness kết thúc backend và broker thử nghiệm.

### 11.2 Kết quả mô phỏng đã lưu và giới hạn kết luận

Kết quả ngày **07/09/2026** được ghi tại `build/performance/vmonitor_perf_test_a562b9358026/results.json` và `recovery_results.json` trên máy kiểm thử. Các file thuộc `build/`, không được đưa vào Git; khi chạy lại cần dùng thư mục kết quả mới. Đây là kết quả của lần mô phỏng đó, không phải trạng thái kiểm thử được cập nhật tự động theo tài liệu.

| Hạng mục | Kết quả đã ghi nhận |
|---|---|
| Dữ liệu vào | Một MQTT publisher đại diện 5.000 device ID, mỗi ID gửi 2 mẫu: tổng 10.000 bản tin |
| Dữ liệu DB | 10.000 telemetry, 10.000 mẫu GPS, 10.000 sự kiện của kịch bản và 5.000 trạng thái mới nhất đúng |
| Thời gian xử lý đầu vào | 102,964 giây; tốc độ quan sát 97,1 bản tin/giây; MQTT `dropped_count = 0` |
| Hai client WebSocket | Client nhận lô và client cũ đều nhận đủ 10.000 ID sự kiện; trạng thái cuối của 5.000 thiết bị đúng |
| Outbox | Thông báo đã commit được phát sau khi bật lại tác vụ; thông báo rollback không phát; dòng hết hạn giữ được phát lại |
| Dịch vụ địa chỉ chậm | 20 request trả `503` có kiểm soát; API danh sách vẫn trả `200` trong 0,431 giây; không còn transaction xác thực bị giữ lúc chờ địa chỉ |
| Thiết lập runtime | Giá trị 750 ms lưu được; giá trị 1 ms bị từ chối |
| Reconnect | REST lấy bù đúng trạng thái mới nhất; lịch sử thiết bị kiểm tra đủ 3 mẫu sau mẫu bổ sung; `/health` trả `ok` |

Harness dùng timeout rút ngắn để kiểm tra nhánh lỗi: gửi WebSocket 0,5 giây, retry outbox 0,1 giây, poll 0,05 giây; địa chỉ tối đa 4 tác vụ chờ/chạy, deadline 0,4 giây và một lần gọi provider. Vì vậy kết quả timeout của mô phỏng không phải phép đo với toàn bộ cấu hình production mặc định.

Các ca unit/widget liên quan nằm trong `backend/tests` và `test`: client chậm/hàng chờ đầy, gộp 25.000 cập nhật của 5.000 ID, cache/hàng chờ địa chỉ, session xác thực đã đóng, lấy bù khi REST trùng realtime, danh sách dựng theo vùng cuộn, nhịp cấu hình, cụm bản đồ và bố cục ở màn hình hẹp/chữ lớn. Widget test kiểm tra không overflow trong các kích thước được thử; chưa phải đo FPS hoặc kiểm tra tương tác trên mọi trình duyệt/thiết bị thật.

Trong lần đồng bộ tài liệu ngày 07/09/2026, đã chạy lại và đạt **71 test backend**, **161 test Flutter**, `flutter analyze` không có vấn đề và `docker compose --env-file .env.docker.example config --quiet` hợp lệ. Không chạy lại mô phỏng mạng hoặc dựng stack Docker trong lần sửa tài liệu này.

Mô phỏng này chứng minh luồng chức năng trong điều kiện đã chạy, **chưa chứng minh 5.000 kết nối MQTT đồng thời, tải duy trì nhiều giờ hoặc 5.000 bản tin/giây**. Số bản tin/giây cần xử lý phụ thuộc chu kỳ gửi: 5.000 thiết bị gửi mỗi 60 giây tương ứng trung bình khoảng 83,3 bản tin/giây; gửi mỗi giây tương ứng 5.000 bản tin/giây. Tải dồn cùng thời điểm còn khác tải phân bố đều.

### 11.3 Giới hạn ổn định cần theo dõi khi vận hành

- Hàng chờ MQTT vẫn ở RAM. Khi đầy, bản tin mới bị bỏ và tăng `dropped_count`; Paho chưa dùng ACK thủ công sau commit DB. Outbox bảo vệ thông báo sự kiện đã commit, không bảo vệ mọi bản tin từ lúc broker chuyển tới backend. Chưa có tác vụ tự xử lý lại telemetry `PENDING`/`FAILED`.
- Outbox có thể tích lũy trong DB khi phát liên tục lỗi; chưa có giới hạn số lần thử. Cần theo dõi số dòng và tuổi thông báo chờ lâu nhất, dung lượng DB, thời gian xử lý và lỗi phát. Đây là chỉ số cần bổ sung giám sát vận hành, không phải toàn bộ đã có sẵn trong `/health`.
- `/health` hiện có các số liệu MQTT như `queue_size`, `queue_capacity`, `received_count`, `processed_count`, `dropped_count` và thời điểm nhận/xử lý cuối. `status=ok` phản ánh sức khỏe kết nối tại lúc kiểm tra, không xác nhận còn đủ năng lực cho mọi mức tải.
- Trước khi cam kết tải production, cần đo trên cấu hình máy triển khai với số kết nối thật, chu kỳ gửi thật, số dashboard đồng thời, tải dồn và thử chạy dài; theo dõi độ trễ, mức hàng chờ, pool DB, CPU/RAM và khả năng phục hồi sau lỗi. Với yêu cầu không mất đầu vào khi backend dừng, cần thiết kế tiếp cơ chế tiếp nhận bền vững và ACK sau khi lưu an toàn.

## 12. Xử lý lỗi thường gặp

| Hiện tượng | Kiểm tra |
|---|---|
| Docker chỉ hiện `Client`, không có `Server` | Docker Desktop phải ở trạng thái `Engine running`; chạy `wsl --shutdown`, sau đó mở lại Docker Desktop |
| Lỗi `dockerDesktopLinuxEngine` hoặc thiếu named pipe | Docker Desktop chưa chạy Linux Engine; chưa chạy lệnh Compose cho tới khi `docker version` có phần `Server` |
| Caddy xin chứng chỉ cho `monitor.example.com` | `.env.docker` vẫn dùng domain mẫu; production thay domain thật, local Windows đặt `DOMAIN=localhost`, sau đó build lại `web` |
| `/health` trả `status: degraded` | Xem riêng `database`, `mqtt.connected`, `mqtt.subscribed` và log backend |
| `curl` local báo lỗi chứng chỉ | Dùng đúng `curl.exe -k https://localhost/health`; URL không chứa định dạng Markdown `[]()` |
| Backend không khởi động | `DATABASE_URL`, PostGIS, `JWT_SECRET`, log Alembic |
| Web mở được nhưng API lỗi | DNS, HTTPS, `DOMAIN`, trạng thái backend, log Caddy |
| Flutter không kết nối | `API_BASE_URL` phải gồm `/api/v1`; build lại sau khi sửa JSON |
| WebSocket bị đóng mã `4401` | token hết hiệu lực, tài khoản bị khóa hoặc frame `AUTH` sai |
| WebSocket bị đóng mã `1013` | client gửi chậm, lỗi mạng hoặc hàng chờ đầy; kiểm tra tải client và timeout, xác nhận lấy bù REST sau reconnect |
| Dashboard cập nhật chậm | nhịp `dashboard_update_interval_ms`, hàng chờ MQTT, thời gian DB và phát realtime; nhịp giao diện không phải độ trễ toàn hệ thống |
| Thiết bị không xuất hiện | topic prefix, `device_code`, quyền nhận dữ liệu, log MQTT |
| Thiết bị hiển thị offline | `last_seen_at`, timeout presence, đồng hồ server và kết nối MQTT |
| Địa chỉ không hiển thị | cấu hình geocoding, internet, hạn mức nhà cung cấp |
| Geocoding trả `503` | hàng chờ/deadline backend hoặc nhà cung cấp lỗi; kiểm tra log, giới hạn cache/hàng chờ và thiết bị đang được xem |
| Lỗi chờ pool DB | kết nối đang bị giữ lâu, giao dịch chờ khóa và số tác vụ đồng thời; kiểm tra trước khi tăng giới hạn pool |
| Windows báo thiếu DLL | phân phối toàn bộ thư mục Release, không sao chép riêng EXE |
