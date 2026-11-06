CREATE TABLE IF NOT EXISTS products (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku          VARCHAR(64)  NOT NULL UNIQUE,
    name         VARCHAR(200) NOT NULL,
    description  TEXT         NOT NULL DEFAULT '',
    price_cents  INTEGER      NOT NULL CONSTRAINT products_price_non_negative CHECK (price_cents >= 0),
    stock        INTEGER      NOT NULL DEFAULT 0 CONSTRAINT products_stock_non_negative CHECK (stock >= 0),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);
