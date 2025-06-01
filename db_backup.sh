#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# backup_postgres_to_r2.sh
#
# PostgreSQL Version: psql (PostgreSQL) 17.5 (Ubuntu 17.5-1.pgdg24.04+1)
#
# This script:
#   1. Creates a timestamp (dd-mm-yyyy_hh:mm).
#   2. Runs pg_dump to export the specified PostgreSQL database.
#   3. Compresses the dump with gzip.
#   4. Uploads the .sql.gz file to Cloudflare R2 (S3-compatible).
#   5. Deletes the local .sql.gz after a successful upload (optional).
#
# Requirements:
#   - PostgreSQL client tools (pg_dump) version 17.5
#   - AWS CLI v2 installed and configured
#   - gzip for compression
#   - Proper PostgreSQL user permissions for pg_dump
#
# Usage:
#   1. Make this script executable: chmod +x backup_postgres_to_r2.sh
#   2. Configure the database connection details below
#   3. Set up required environment variables or .pgpass file
#   4. Test manually, then schedule via cron for regular backups
#
# Environment Variables Required:
#   - AWS_ACCESS_KEY_ID: R2 access key
#   - AWS_SECRET_ACCESS_KEY: R2 secret key
#   - AWS_DEFAULT_REGION: Set to "auto" for R2
#   - R2_ACCOUNT_ID: Your Cloudflare account ID
#   - R2_BUCKET: Your R2 bucket name
#   - R2_PATH: (Optional) Path within the bucket
#   - PGPASSWORD: (Optional) PostgreSQL password if not using .pgpass
#
# Example Cron Job (runs daily at 2:00 AM):
# 0 2 * * * /path/to/backup_postgres_to_r2.sh
# ------------------------------------------------------------------------------

##### === USER CONFIGURATION SECTION === #####

# PostgreSQL connection details:
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="mydb2"
DB_USER="myuser2"

#
# Authentication for pg_dump:
# • Either export PGPASSWORD in the environment before running this script
#   (recommended for cron), or set up ~/.pgpass with proper permissions (chmod 600).
#   If neither is present, pg_dump will prompt for a password (which fails under cron).

# Cloudflare R2 (S3-compatible) details:
# (These must be set as environment variables before running the script.)
#   export AWS_ACCESS_KEY_ID="R2ACCESSKEY..."
#   export AWS_SECRET_ACCESS_KEY="R2SECRETKEY..."
#   export AWS_DEFAULT_REGION="auto"
#   export R2_ACCOUNT_ID="0123456789abcdef0123456789abcdef"
#   export R2_BUCKET="my‐r2‐backups"
#   export R2_PATH="daily"       # optional; leave empty ("") for bucket root

# Local directory for temporary storage of dumps:
# Make sure this directory exists or script can create it; must be writable.
BACKUP_BASE_DIR="/home/ubuntu/backups/postgres"


##### === NO NEED TO EDIT BELOW THIS LINE === #####

# Ensure required ENV vars are set
if [ -z "${PGPASSWORD}" ] && [ ! -f "${HOME}/.pgpass" ]; then
  echo "[ERROR] PGPASSWORD not set and ~/.pgpass not found. Exiting."
  exit 1
fi
if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ]; then
  echo "[ERROR] AWS_ACCESS_KEY_ID and/or AWS_SECRET_ACCESS_KEY not set. Exiting."
  exit 2
fi
if [ -z "${R2_ACCOUNT_ID}" ] || [ -z "${R2_BUCKET}" ]; then
  echo "[ERROR] R2_ACCOUNT_ID and/or R2_BUCKET not set. Exiting."
  exit 3
fi

# Create the local backup directory if it doesn’t exist
mkdir -p "${BACKUP_BASE_DIR}"

# Generate timestamp in dd-mm-yyyy_hh:mm
TIMESTAMP=$(date +"%d-%m-%Y_%H:%M")

# Compose filename: e.g., mydb_31-05-2025_02:00.sql.gz
FILENAME="${DB_NAME}_${TIMESTAMP}.sql.gz"
LOCAL_FILEPATH="${BACKUP_BASE_DIR}/${FILENAME}"

# Build the R2 endpoint URL from your account ID
# e.g. https://<ACCOUNT_ID>.r2.cloudflarestorage.com
R2_ENDPOINT_URL="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Build the full “s3://”-style destination
# If R2_PATH is non-empty, we use “s3://bucket/path/filename”
# Otherwise, we write “s3://bucket/filename”
if [ -n "${R2_PATH}" ]; then
  R2_S3_URI="s3://${R2_BUCKET}/${R2_PATH}/${FILENAME}"
else
  R2_S3_URI="s3://${R2_BUCKET}/${FILENAME}"
fi

# ------------------------------------------------------------------------------
# 1. Dump & compress
# ------------------------------------------------------------------------------
echo "[$(date +'%F %T')] Starting pg_dump for database '${DB_NAME}'..."
pg_dump --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --format=plain \
        --no-owner \
        --no-privileges \
        "${DB_NAME}" \
  | gzip -c > "${LOCAL_FILEPATH}"

if [ $? -ne 0 ]; then
  echo "[$(date +'%F %T')] ERROR: pg_dump failed!"
  exit 10
else
  echo "[$(date +'%F %T')] pg_dump succeeded → ${LOCAL_FILEPATH}"
fi

# ------------------------------------------------------------------------------
# 2. Upload to Cloudflare R2 (S3-compatible)
# ------------------------------------------------------------------------------
echo "[$(date +'%F %T')] Uploading ${LOCAL_FILEPATH} → ${R2_S3_URI} (R2 endpoint: ${R2_ENDPOINT_URL})..."
aws s3 cp "${LOCAL_FILEPATH}" "${R2_S3_URI}" \
     --endpoint-url "${R2_ENDPOINT_URL}" \
     --only-show-errors

if [ $? -ne 0 ]; then
  echo "[$(date +'%F %T')] ERROR: R2 upload failed!"
  exit 20
else
  echo "[$(date +'%F %T')] Upload to R2 succeeded."
fi

# ------------------------------------------------------------------------------
# 3. Cleanup (optional)
# ------------------------------------------------------------------------------
# If you want to remove the local backup after a successful R2 upload, uncomment below:
#
# echo "[$(date +'%F %T')] Removing local backup file ${LOCAL_FILEPATH} ..."
rm -rf "${BACKUP_BASE_DIR}"
if [ $? -ne 0 ]; then
  echo "[$(date +'%F %T')] WARNING: Could not delete local file ${LOCAL_FILEPATH}"
else
  echo "[$(date +'%F %T')] Local file deleted."
fi

echo "[$(date +'%F %T')] Backup script completed successfully."
exit 0
