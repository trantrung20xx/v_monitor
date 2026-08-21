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
    pass


class LastAdministratorError(ValueError):
    pass


class UserService:
    @staticmethod
    def _safe_user_value(user: UserAccount) -> dict:
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
        query = select(UserAccount).where(
            func.lower(UserAccount.username) == username.strip().lower()
        )
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
        user = await UserService._find_by_username(
            db,
            username,
            for_update=True,
        )
        if user is None:
            verify_dummy_password(password)
            return None

        now = datetime.now(timezone.utc)
        is_locked = user.locked_until is not None and user.locked_until > now
        password_valid = False if is_locked else verify_password(
            password,
            user.password_hash,
        )
        if not password_valid or not user.is_active:
            if not is_locked:
                user.failed_login_count += 1
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
        existing = await UserService._find_by_username(db, account_in.username)
        if existing is not None:
            raise DuplicateAccountError("Username đã tồn tại")
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
        db.add(UserSetting(user_id=user.id))
        UserService._add_audit(
            db,
            actor_user_id=actor_user_id,
            action="USER_CREATED",
            entity_id=user.id,
            new_value=UserService._safe_user_value(user),
        )
        try:
            await db.commit()
        except IntegrityError as exc:
            await db.rollback()
            raise DuplicateAccountError("Username hoặc email đã tồn tại") from exc
        await db.refresh(user)
        return user

    @staticmethod
    async def list_accounts(
        db: AsyncSession,
        *,
        skip: int,
        limit: int,
    ) -> list[UserAccount]:
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
        result = await db.execute(
            select(UserAccount).where(UserAccount.id == user_id).with_for_update()
        )
        user = result.scalar_one_or_none()
        if user is None:
            return None

        changes = account_in.model_dump(exclude_unset=True)
        if "email" in changes and changes["email"]:
            email_result = await db.execute(
                select(UserAccount.id).where(
                    func.lower(UserAccount.email) == changes["email"].lower(),
                    UserAccount.id != user.id,
                )
            )
            if email_result.scalar_one_or_none() is not None:
                raise DuplicateAccountError("Email đã tồn tại")
        removes_active_admin = (
            user.role == UserRole.ADMIN
            and user.is_active
            and (
                changes.get("role", UserRole.ADMIN) != UserRole.ADMIN
                or changes.get("is_active", True) is False
            )
        )
        if removes_active_admin:
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

        old_value = UserService._safe_user_value(user)
        authorization_changed = False
        for field_name, value in changes.items():
            if field_name in {"role", "is_active"} and getattr(user, field_name) != value:
                authorization_changed = True
            setattr(user, field_name, value)
        if authorization_changed:
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
            await db.commit()
        except IntegrityError as exc:
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
        user = await db.get(UserAccount, user_id)
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
        result = await db.execute(
            select(UserSetting).where(UserSetting.user_id == user_id)
        )
        user_settings = result.scalar_one_or_none()
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
        user_settings = await UserService.get_settings(db, user.id)
        changes = settings_in.model_dump(exclude_unset=True)
        preferences_patch = changes.pop("preferences", None)
        for field_name, value in changes.items():
            setattr(user_settings, field_name, value)
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
