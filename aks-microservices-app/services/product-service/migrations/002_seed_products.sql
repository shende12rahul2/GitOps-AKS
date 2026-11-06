INSERT INTO products (sku, name, description, price_cents, stock) VALUES
    ('KB-001', 'Mechanical keyboard', 'Tenkeyless, brown switches', 8900, 50),
    ('MS-001', 'Wireless mouse', 'Ergonomic, 2.4 GHz', 3900, 120),
    ('MN-027', '27-inch monitor', '4K IPS', 32900, 15),
    ('HS-010', 'Headset', 'Noise cancelling', 12900, 40)
ON CONFLICT (sku) DO NOTHING;
