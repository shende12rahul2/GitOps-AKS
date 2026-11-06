-- Read-only access for the products_db_readonly role created by db-bootstrap
-- (granted to QA/developer Entra groups in non-production environments).
GRANT SELECT ON ALL TABLES IN SCHEMA public TO products_db_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO products_db_readonly;
