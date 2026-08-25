# Nghiệp vụ tài khoản: đăng nhập có khóa tạm, CRUD quản trị, đổi/reset mật khẩu,
# tăng token_version để thu hồi token cũ và hợp nhất preferences mà không mất khóa khác.
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.security import hash_password, verify_dummy_password, verify_password
from app.domain.enums import UserRole
from app.models.audit_log import AuditLog
from app.models.user_account import UserAccount, UserSetting
from app.schemas.auth import UserCreate, UserSettingsUpdate, UserUpdate


class DuplicateAccountError(ValueError):
    # Router ánh xạ lỗi trùng username/email thành phản hồi HTTP phù hợp.
    pass


class LastAdministratorError(ValueError):
    # Bảo vệ hệ thống luôn còn ít nhất một quản trị viên đang hoạt động.
    pass


class UserService:
    # Mọi thao tác ghi tài khoản đều tạo audit và commit cùng transaction với thay đổi.
    @staticmethod
    def _safe_user_value(user: UserAccount) -> dict:
        # Chỉ đưa trường quản trị an toàn vào audit; tuyệt đối không ghi password_hash.
        return {
            "username": user.username,
            "full_name": user.full_name,
            "email": user.email,
            "role": user.role.value,
            "is_active": user.is_active,
        }

    @staticmethod
    def _add_audit(
        db: AsyncSession,
        *,
        actor_user_id: Optional[uuid.UUID],
        action: str,
        entity_id: uuid.UUID,
        old_value: Optional[dict] = None,
        new_value: Optional[dict] = None,
        metadata: Optional[dict] = None,
    ) -> None:
        # Chỉ add vào session; caller chịu trách nhiệm commit cùng thay đổi nghiệp vụ.
        db.add(
            AuditLog(
                actor_user_id=actor_user_id,
                action=action,
                entity_type="user_account",
                entity_id=entity_id,
                occurred_at=datetime.now(timezone.utc),
                old_value=old_value,
                new_value=new_value,
                metadata_=metadata,
            )
        )

    @staticmethod
    async def _find_by_username(
        db: AsyncSession,
        username: str,
        *,
        for_update: bool = False,
    ) -> Optional[UserAccount]:
        # Username được so sánh không phân biệt hoa thường; for_update dùng cho login
        # để số lần sai và thời điểm khóa không bị hai request cập nhật đè nhau.
        query = select(UserAccount).where(
            func.lower(UserAccount.username) == username.strip().lower()
        )
        # Khóa chỉ được thêm ở luồng ghi như login; các luồng đọc không giữ lock dư.
        if for_update:
            query = query.with_for_update()
        result = await db.execute(query)
        return result.scalar_one_or_none()

    @staticmethod
    async def authenticate(
        db: AsyncSession,
        username: str,
        password: str,
    ) -> Optional[UserAccount]:
        # Trả cùng một kết quả None cho sai mật khẩu, bị khóa hoặc inactive để không
        # tiết lộ trạng thái tài khoản cho người chưa xác thực.
        user = await UserService._find_by_username(
            db,
            username,
            for_update=True,
        )
        # Không tồn tại vẫn chạy hash giả rồi kết thúc mà không mở transaction ghi.
        if user is None:
            # Vẫn thực hiện phép kiểm tra hash giả để giảm khác biệt thời gian giữa
            # username tồn tại và không tồn tại.
            verify_dummy_password(password)
            return None

        now = datetime.now(timezone.utc)
        # locked_until chỉ có hiệu lực khi còn nằm trong tương lai; mốc cũ được xóa khi login đúng.
        is_locked = user.locked_until is not None and user.locked_until > now
        # Không tính hash thật khi đang khóa để tránh cho phép login trước thời hạn.
        password_valid = False if is_locked else verify_password(
            password,
            user.password_hash,
        )
        # Inactive và sai mật khẩu dùng cùng nhánh phản hồi nhằm không lộ trạng thái tài khoản.
        if not password_valid or not user.is_active:
            # Tài khoản đang trong thời gian khóa không tăng thêm bộ đếm hoặc kéo dài
            # khóa; chỉ lần sai khi chưa khóa mới tham gia ngưỡng.
            if not is_locked:
                user.failed_login_count += 1
                # Chạm ngưỡng mới đặt locked_until; các lần sai trước chỉ tăng bộ đếm.
                if user.failed_login_count >= settings.login_max_failed_attempts:
                    user.locked_until = now + timedelta(
                        minutes=settings.login_lock_minutes
                    )
            UserService._add_audit(
                db,
                actor_user_id=user.id,
                action="LOGIN_FAILED",
                entity_id=user.id,
                metadata={"reason": "invalid_credentials_or_inactive"},
            )
            await db.commit()
            return None

        user.failed_login_count = 0
        # Đăng nhập thành công xóa lịch sử khóa tạm và lưu thời điểm gần nhất.
        user.locked_until = None
        user.last_login_at = now
        UserService._add_audit(
            db,
            actor_user_id=user.id,
            action="LOGIN_SUCCESS",
            entity_id=user.id,
        )
        await db.commit()
        await db.refresh(user)
        return user

    @staticmethod
    async def create_account(
        db: AsyncSession,
        account_in: UserCreate,
        *,
        actor_user_id: Optional[uuid.UUID],
    ) -> UserAccount:
        # Kiểm tra sớm để trả thông báo rõ; unique constraint database vẫn là lớp
        # bảo vệ cuối cùng khi hai request tạo trùng chạy đồng thời.
        existing = await UserService._find_by_username(db, account_in.username)
        # Username được kiểm tra không phân biệt hoa/thường tại helper.
        if existing is not None:
            raise DuplicateAccountError("Username đã tồn tại")
        # Email là tùy chọn; chỉ truy vấn trùng khi request thật sự cung cấp giá trị.
        if account_in.email:
            email_result = await db.execute(
                select(UserAccount.id).where(
                    func.lower(UserAccount.email) == account_in.email.lower()
                )
            )
            if email_result.scalar_one_or_none() is not None:
                raise DuplicateAccountError("Email đã tồn tại")

        now = datetime.now(timezone.utc)
        user = UserAccount(
            username=account_in.username,
            password_hash=hash_password(account_in.password),
            password_changed_at=now,
            full_name=account_in.full_name,
            email=account_in.email,
            role=account_in.role,
            is_active=account_in.is_active,
        )
        db.add(user)
        await db.flush()
        # Mỗi tài khoản có một dòng cài đặt mặc định ngay từ transaction tạo mới.
        db.add(UserSetting(user_id=user.id))
        UserService._add_audit(
            db,
            actor_user_id=actor_user_id,
            action="USER_CREATED",
            entity_id=user.id,
            new_value=UserService._safe_user_value(user),
        )
        try:
            # Commit chung user, settings mặc định và audit như một đơn vị nguyên tử.
            await db.commit()
        except IntegrityError as exc:
            # Unique constraint xử lý cuộc đua giữa hai request vượt qua kiểm tra sớm.
            await db.rollback()
            raise DuplicateAccountError("Username hoặc email đã tồn tại") from exc
        # Refresh lấy timestamp/default do database cấp.
        await db.refresh(user)
        return user

    @staticmethod
    async def list_accounts(
        db: AsyncSession,
        *,
        skip: int,
        limit: int,
    ) -> list[UserAccount]:
        # Phân trang và sắp theo username để danh sách ổn định giữa các lần tải.
        result = await db.execute(
            select(UserAccount)
            .order_by(UserAccount.username.asc())
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def update_account(
        db: AsyncSession,
        user_id: uuid.UUID,
        account_in: UserUpdate,
        *,
        actor_user_id: uuid.UUID,
    ) -> Optional[UserAccount]:
        # Khóa tài khoản đang sửa để kiểm tra quyền và tăng token_version nguyên tử.
        result = await db.execute(
            select(UserAccount).where(UserAccount.id == user_id).with_for_update()
        )
        user = result.scalar_one_or_none()
        # PATCH không tự tạo user khi UUID không tồn tại.
        if user is None:
            return None

        changes = account_in.model_dump(exclude_unset=True)
        # Chỉ kiểm tra email khi trường có trong PATCH và không phải null/rỗng.
        if "email" in changes and changes["email"]:
            email_result = await db.execute(
                select(UserAccount.id).where(
                    func.lower(UserAccount.email) == changes["email"].lower(),
                    UserAccount.id != user.id,
                )
            )
            if email_result.scalar_one_or_none() is not None:
                raise DuplicateAccountError("Email đã tồn tại")
        # Biểu thức chỉ đúng khi user hiện là admin active và bản cập nhật làm mất
        # một trong hai điều kiện đó.
        removes_active_admin = (
            user.role == UserRole.ADMIN
            and user.is_active
            and (
                changes.get("role", UserRole.ADMIN) != UserRole.ADMIN
                or changes.get("is_active", True) is False
            )
        )
        if removes_active_admin:
            # Chỉ chặn thao tác thật sự làm mất quản trị viên active cuối cùng; sửa tên,
            # email hoặc cập nhật một admin khi còn admin khác vẫn được phép.
            count_result = await db.execute(
                select(func.count(UserAccount.id)).where(
                    UserAccount.role == UserRole.ADMIN,
                    UserAccount.is_active.is_(True),
                )
            )
            if (count_result.scalar_one() or 0) <= 1:
                raise LastAdministratorError(
                    "Không thể vô hiệu hóa hoặc hạ quyền quản trị viên cuối cùng"
                )

        # Snapshot cũ được lấy trước setattr để audit phản ánh đúng hai phía thay đổi.
        old_value = UserService._safe_user_value(user)
        authorization_changed = False
        for field_name, value in changes.items():
            # Chỉ role/is_active tác động quyền; thay tên/email không cần thu hồi token.
            if field_name in {"role", "is_active"} and getattr(user, field_name) != value:
                authorization_changed = True
            # Tên trường đã được giới hạn bởi UserUpdate nên setattr không nhận khóa ngoài schema.
            setattr(user, field_name, value)
        if authorization_changed:
            # Token JWT mang token_version cũ sẽ bị dependency từ chối ở request sau,
            # giúp thay đổi quyền/vô hiệu hóa có hiệu lực mà không cần blacklist token.
            user.token_version += 1

        UserService._add_audit(
            db,
            actor_user_id=actor_user_id,
            action="USER_UPDATED",
            entity_id=user.id,
            old_value=old_value,
            new_value=UserService._safe_user_value(user),
        )
        try:
            # Thay đổi user và audit cùng commit để không có lịch sử không khớp dữ liệu.
            await db.commit()
        except IntegrityError as exc:
            # Race condition email trùng được constraint database bắt ở lớp cuối.
            await db.rollback()
            raise DuplicateAccountError("Email đã tồn tại") from exc
        await db.refresh(user)
        return user

    @staticmethod
    async def reset_password(
        db: AsyncSession,
        user_id: uuid.UUID,
        new_password: str,
        *,
        actor_user_id: uuid.UUID,
    ) -> Optional[UserAccount]:
        # Reset của quản trị viên xóa khóa tạm và thu hồi toàn bộ token cũ của tài khoản.
        user = await db.get(UserAccount, user_id)
        # UUID không tồn tại được báo bằng None để router trả 404.
        if user is None:
            return None
        user.password_hash = hash_password(new_password)
        user.password_changed_at = datetime.now(timezone.utc)
        user.failed_login_count = 0
        user.locked_until = None
        user.token_version += 1
        UserService._add_audit(
            db,
            actor_user_id=actor_user_id,
            action="PASSWORD_RESET",
            entity_id=user.id,
        )
        await db.commit()
        await db.refresh(user)
        return user

    @staticmethod
    async def change_own_password(
        db: AsyncSession,
        user: UserAccount,
        current_password: str,
        new_password: str,
    ) -> bool:
        # Chỉ đổi khi mật khẩu hiện tại đúng; token hiện tại cũng hết hiệu lực sau commit.
        # Nhánh sai không ghi audit hay thay đổi token_version vì chưa có thao tác hợp lệ.
        if not verify_password(current_password, user.password_hash):
            return False
        user.password_hash = hash_password(new_password)
        user.password_changed_at = datetime.now(timezone.utc)
        user.token_version += 1
        UserService._add_audit(
            db,
            actor_user_id=user.id,
            action="PASSWORD_CHANGED",
            entity_id=user.id,
        )
        await db.commit()
        return True

    @staticmethod
    async def get_settings(
        db: AsyncSession,
        user_id: uuid.UUID,
    ) -> UserSetting:
        # Tự bổ sung dòng mặc định cho tài khoản cũ chưa có user_settings.
        result = await db.execute(
            select(UserSetting).where(UserSetting.user_id == user_id)
        )
        user_settings = result.scalar_one_or_none()
        # Nhánh tạo bù hỗ trợ tài khoản được tạo trước khi bảng user_settings xuất hiện.
        # Dòng mặc định được commit ngay để request tiếp theo đọc cùng một cấu hình.
        if user_settings is None:
            user_settings = UserSetting(user_id=user_id)
            db.add(user_settings)
            await db.commit()
            await db.refresh(user_settings)
        return user_settings

    @staticmethod
    async def update_settings(
        db: AsyncSession,
        user: UserAccount,
        settings_in: UserSettingsUpdate,
    ) -> UserSetting:
        # Các trường được gửi trực tiếp thay thế giá trị; riêng preferences JSONB được
        # patch theo khóa để chỉnh một tùy chọn không xóa các tùy chọn còn lại.
        user_settings = await UserService.get_settings(db, user.id)
        changes = settings_in.model_dump(exclude_unset=True)
        # preferences cần merge riêng nên được tách khỏi các cột thông thường.
        preferences_patch = changes.pop("preferences", None)
        # Các cột theme/language/timezone chỉ thay khi client gửi trong PATCH.
        for field_name, value in changes.items():
            setattr(user_settings, field_name, value)
        # Object rỗng vẫn là một patch hợp lệ; None mới có nghĩa không gửi preferences.
        if preferences_patch is not None:
            # preferences là JSONB dùng chung cho nhiều lựa chọn giao diện. Chỉ
            # merge các khóa được gửi để một PATCH không xóa cấu hình còn lại.
            user_settings.preferences = {
                **(user_settings.preferences or {}),
                **preferences_patch,
            }
        UserService._add_audit(
            db,
            actor_user_id=user.id,
            action="USER_SETTINGS_UPDATED",
            entity_id=user.id,
        )
        await db.commit()
        await db.refresh(user_settings)
        return user_settings
