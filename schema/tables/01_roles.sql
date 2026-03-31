-- Table: roles
-- Doc:   docs/database/tables/01_roles.md
--
-- Lookup table for user roles.
-- Referenced by users.role_id (FK).
-- role_id = 1 → user (default)
-- role_id = 2 → creator (set via is_creator SP)

CREATE TABLE IF NOT EXISTS public.roles (
    role_id   int8 PRIMARY KEY,
    role_name text NULL
);

-- Seed data
INSERT INTO public.roles (role_id, role_name) VALUES
    (1, 'user'),
    (2, 'creator')
ON CONFLICT (role_id) DO NOTHING;
