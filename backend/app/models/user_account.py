import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, CheckConstraint, Enum, ForeignKey, Index, Integer, String, func, true
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.domain.enums import UserRole
from app.models.base import Base, TimestampMixin, UUIDMixin


class UserAccount(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "user_accounts"

    username: Mapped[str] = mapped_column(String(50), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    email: Mapped[Optional[str]] = mapped_column(String(320), nullable=True)
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole),
        default=UserRole.USER,
        server_default=UserRole.USER.value,
        nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        server_default=true(),
        nullable=False,
    )
    last_login_at: Mapped[Optional[datetime]] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True,
    )
    password_changed_at: Mapped[Optional[datetime]] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True,
    )
    failed_login_count: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default="0",
        nullable=False,
    )
    locked_until: Mapped[Optional[datetime]] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True,
    )
    token_version: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default="0",
        nullable=False,
    )

    settings = relationship(
        "UserSetting",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )

    __table_args__ = (
        CheckConstraint(
            "length(btrim(username)) >= 3",
            name="ck_user_accounts_username_length",
        ),
        CheckConstraint(
            "length(btrim(full_name)) >= 1",
            name="ck_user_accounts_full_name_not_blank",
        ),
        CheckConstraint(
            "username = btrim(username)",
            name="ck_user_accounts_username_trimmed",
        ),
        CheckConstraint(
            "length(btrim(password_hash)) >= 20",
            name="ck_user_accounts_password_hash",
        ),
        CheckConstraint(
            "email IS NULL OR (email = btrim(email) AND length(email) >= 3)",
            name="ck_user_accounts_email",
        ),
        CheckConstraint(
            "failed_login_count >= 0",
            name="ck_user_accounts_failed_login_count",
        ),
        CheckConstraint(
            "token_version >= 0",
            name="ck_user_accounts_token_version",
        ),
        Index("uq_user_accounts_username_ci", func.lower(username), unique=True),
        Index(
            "uq_user_accounts_email_ci",
            func.lower(email),
            unique=True,
            postgresql_where=email.is_not(None),
        ),
    )


class UserSetting(Base, TimestampMixin):
    __tablename__ = "user_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("user_accounts.id", ondelete="CASCADE"),
        primary_key=True,
    )
    theme: Mapped[str] = mapped_column(
        String(20),
        default="system",
        server_default="system",
        nullable=False,
    )
    language: Mapped[str] = mapped_column(
        String(10),
        default="vi",
        server_default="vi",
        nullable=False,
    )
    timezone: Mapped[str] = mapped_column(
        String(64),
        default="Asia/Ho_Chi_Minh",
        server_default="Asia/Ho_Chi_Minh",
        nullable=False,
    )
    notifications_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        server_default=true(),
        nullable=False,
    )
    preferences: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)

    user = relationship("UserAccount", back_populates="settings")

    __table_args__ = (
        CheckConstraint(
            "theme IN ('system', 'light', 'dark')",
            name="ck_user_settings_theme",
        ),
        CheckConstraint(
            "language = btrim(language) AND length(language) >= 2",
            name="ck_user_settings_language",
        ),
        CheckConstraint(
            "timezone = btrim(timezone) AND length(timezone) >= 1",
            name="ck_user_settings_timezone",
        ),
    )
