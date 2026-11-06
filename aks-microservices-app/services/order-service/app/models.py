from datetime import datetime

from sqlalchemy import BigInteger, CheckConstraint, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from svc_common.db import Base

PK = BigInteger().with_variant(Integer, "sqlite")
STATUSES = ("PENDING", "PROCESSED", "FAILED")


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (CheckConstraint("status IN ('PENDING','PROCESSED','FAILED')", name="orders_status_valid"),)

    id: Mapped[int] = mapped_column(PK, primary_key=True, autoincrement=True)
    # user_id/product_id reference other services' databases: integrity is
    # enforced through their APIs, not foreign keys (database per service).
    user_id: Mapped[int] = mapped_column(BigInteger, nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="PENDING", index=True)
    total_cents: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    notification_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    items: Mapped[list["OrderItem"]] = relationship(back_populates="order", cascade="all, delete-orphan", lazy="selectin")


class OrderItem(Base):
    __tablename__ = "order_items"
    __table_args__ = (CheckConstraint("quantity > 0", name="order_items_quantity_positive"),)

    id: Mapped[int] = mapped_column(PK, primary_key=True, autoincrement=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_price_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    order: Mapped[Order] = relationship(back_populates="items")
