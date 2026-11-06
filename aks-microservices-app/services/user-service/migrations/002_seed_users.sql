INSERT INTO users (email, full_name) VALUES
    ('ada.lovelace@example.com', 'Ada Lovelace'),
    ('alan.turing@example.com', 'Alan Turing'),
    ('grace.hopper@example.com', 'Grace Hopper')
ON CONFLICT (email) DO NOTHING;
