CREATE TABLE IF NOT EXISTS orders (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT      NOT NULL,
    status           VARCHAR(16) NOT NULL DEFAULT 'PENDING'
                     CONSTRAINT orders_status_valid CHECK (status IN ('PENDING', 'PROCESSED', 'FAILED')),
    total_cents      INTEGER     NOT NULL DEFAULT 0,
    notification_id  VARCHAR(64),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS ix_orders_status ON orders (status);

CREATE TABLE IF NOT EXISTS order_items (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id          BIGINT  NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    product_id        BIGINT  NOT NULL,
    quantity          INTEGER NOT NULL CONSTRAINT order_items_quantity_positive CHECK (quantity > 0),
    unit_price_cents  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_order_items_order_id ON order_items (order_id);
