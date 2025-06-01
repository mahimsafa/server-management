#!/usr/bin/env bash

# Usage:
#   sudo bash secure_create_db_user.sh <DB_USERNAME> <DB_PASSWORD> <DB_NAME>

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: sudo bash $0 <DB_USERNAME> <DB_PASSWORD> <DB_NAME>"
  exit 1
fi

DB_USER="$1"
DB_PASS="$2"
DB_NAME="$3"

echo "----- Creating PostgreSQL role and secure database setup -----"

sudo -u postgres psql <<EOF
-- Create role if it doesn't exist
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';
   END IF;
END
\$\$;

-- Create database owned by this user
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};

-- Restrict public access inside the new database
\c ${DB_NAME}
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO ${DB_USER};

-- Optional: prevent access to other DBs (you may need to add each manually)
REVOKE CONNECT ON DATABASE postgres FROM ${DB_USER};
REVOKE CONNECT ON DATABASE template1 FROM ${DB_USER};

EOF

echo "✅ PostgreSQL user '${DB_USER}' and isolated database '${DB_NAME}' created securely."
