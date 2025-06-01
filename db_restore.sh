#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# restore_postgres_from_r2.sh
#
# PostgreSQL Version: psql (PostgreSQL) 17.5 (Ubuntu 17.5-1.pgdg24.04+1)
#
# REQUIREMENTS:
#   1) PostgreSQL client tools (psql) version 17.5
#   2) AWS CLI v2 installed and configured
#   3) gzip for decompression
#   4) Proper PostgreSQL user permissions for restoration
#
# CONFIGURATION:
#   You must pass the full R2 S3‐style URI as $1:
#     s3://<bucket>/<path>/<filename>.sql.gz
#
# ENVIRONMENT VARIABLES (must be set before execution):
#   - AWS_ACCESS_KEY_ID: R2 access key
#   - AWS_SECRET_ACCESS_KEY: R2 secret key
#   - AWS_DEFAULT_REGION: Set to "auto" for R2
#   - R2_ACCOUNT_ID: Your Cloudflare account ID
#   - PGPASSWORD: (Optional) PostgreSQL password if not using .pgpass
#
# WHAT IT DOES:
#   1. Downloads the specified .sql.gz backup from R2
#   2. Decompresses and pipes the SQL into psql for restoration
#   3. Optionally removes the local copy after successful restoration
#
# USAGE EXAMPLE:
#   ./restore_postgres_from_r2.sh s3://db-backups/muslimdome/postgres/mydb_31-05-2025_02:00.sql.gz
#
# For automated restores, ensure all required environment variables are set in the calling environment.
# ------------------------------------------------------------------------------

set -euo pipefail

##### === USER CONFIGURATION SECTION === #####

# PostgreSQL connection details (edit before using):
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="mydb1"
DB_USER="myuser1"

# Local directory to store the downloaded dump temporarily:
# Make sure this exists or can be created, and is writable.
LOCAL_RESTORE_DIR="/home/ubuntu/backups/postgres/restore-tmp"

##### === NO EDITS BELOW THIS LINE (unless you know what you're doing) === #####

# 1. Verify the user provided exactly one argument (the full s3:// URI)
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 s3://<bucket>/<path>/<filename>.sql.gz"
  exit 1
fi

FULL_S3_URI="$1"

# 2. Verify R2 ENV vars are set
: "${AWS_ACCESS_KEY_ID:?Need to set AWS_ACCESS_KEY_ID for R2 access}"
: "${AWS_SECRET_ACCESS_KEY:?Need to set AWS_SECRET_ACCESS_KEY for R2 access}"
: "${AWS_DEFAULT_REGION:?Need to set AWS_DEFAULT_REGION (e.g. 'auto')}"
: "${R2_ACCOUNT_ID:?Need to set R2_ACCOUNT_ID (Cloudflare account ID)}"

# 3. Verify Postgres auth is available
if [ -z "${PGPASSWORD:-}" ] && [ ! -f "${HOME}/.pgpass" ]; then
  echo "[ERROR] Postgres password not set (PGPASSWORD) and ~/.pgpass not found."
  exit 2
fi

# 4. Build the R2 endpoint URL
R2_ENDPOINT_URL="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

# 5. Extract the filename from the supplied URI
#    Example: if FULL_S3_URI="s3://my-bucket/daily/mydb_31-05-2025_02:00.sql.gz",
#    then BACKUP_FILENAME="mydb_31-05-2025_02:00.sql.gz"
BACKUP_FILENAME="$(basename "${FULL_S3_URI}")"

# 6. Ensure the local restore directory exists
mkdir -p "${LOCAL_RESTORE_DIR}"

# 7. Define where to download the file
LOCAL_FILEPATH="${LOCAL_RESTORE_DIR}/${BACKUP_FILENAME}"

echo "[$(date +'%F %T')] Downloading '${FULL_S3_URI}' → '${LOCAL_FILEPATH}' ..."
aws s3 cp "s3://${R2_BUCKET}/${FULL_S3_URI}" "${LOCAL_FILEPATH}" \
    --endpoint-url "${R2_ENDPOINT_URL}" \
    --only-show-errors

if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to download '${FULL_S3_URI}'. Exiting."
  exit 3
fi

echo "[$(date +'%F %T')] Download succeeded."

# 8. Decompress & restore into PostgreSQL
echo "[$(date +'%F %T')] Restoring database '${DB_NAME}' from '${LOCAL_FILEPATH}' ..."
gunzip -c "${LOCAL_FILEPATH}" \
  | psql --host="${DB_HOST}" \
         --port="${DB_PORT}" \
         --username="${DB_USER}" \
         --dbname="${DB_NAME}"

if [ $? -ne 0 ]; then
  echo "[ERROR] Restore failed!"
  exit 4
fi

echo "[$(date +'%F %T')] Restore completed successfully."

# 9. (Optional) Remove the local downloaded file
#    Uncomment the next block if you want to delete the local .sql.gz afterward.
#
# echo "[$(date +'%F %T')] Removing local file '${LOCAL_FILEPATH}' ..."
# rm -f "${LOCAL_FILEPATH}"
# if [ $? -ne 0 ]; then
#   echo "[WARNING] Could not delete local file '${LOCAL_FILEPATH}'."
# else
#   echo "[$(date +'%F %T')] Local file deleted."
# fi

echo "[$(date +'%F %T')] Restore script finished."
exit 0
