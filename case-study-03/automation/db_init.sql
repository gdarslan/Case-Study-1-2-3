-- Employee table for Innovatech HR application
-- Run once after RDS is provisioned to initialize the schema

CREATE TABLE IF NOT EXISTS employees (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100)  NOT NULL,
    email       VARCHAR(150)  NOT NULL UNIQUE,
    department  VARCHAR(100)  NOT NULL,
    role        VARCHAR(100)  NOT NULL,
    status      VARCHAR(20)   NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active', 'inactive', 'pending')),
    sso_user_id VARCHAR(200),
    created_at  TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_updated_at ON employees;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Seed data for testing
INSERT INTO employees (name, email, department, role, status) VALUES
    ('Alice Johnson',  'alice.johnson@example.com',  'Engineering',  'developer',  'active'),
    ('Bob Martinez',   'bob.martinez@example.com',   'HR',           'hr',         'active'),
    ('Carol Smith',    'carol.smith@example.com',    'IT',           'admin',      'active')
ON CONFLICT (email) DO NOTHING;
