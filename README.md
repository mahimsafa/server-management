# Server Setup Scripts Documentation

This directory contains scripts to set up and manage a production-ready server with PostgreSQL, Node.js, and other essential services. Below is the documentation for each script.

## Table of Contents
1. [setup_server.sh](#setupserversh) - Main server setup script
2. [create_db_user.sh](#createdbusersh) - Database user and database creation
3. [db_backup.sh](#dbbackupsh) - PostgreSQL database backup to Cloudflare R2
4. [db_restore.sh](#dbrestoresh) - Restore PostgreSQL database from Cloudflare R2 backup

---

## setup_server.sh

### Description
Sets up a production-ready Linux server with:
- Node.js 22
- PostgreSQL 17
- Valkey 8.1.1 (Redis-compatible)
- Nginx with SSL (Let's Encrypt)
- UFW firewall configuration

### Prerequisites
- Ubuntu/Debian-based system
- Sudo privileges
- Domain name pointing to your server

### Usage
```bash
sudo bash setup_server.sh <YOUR_DOMAIN> <YOUR_EMAIL> <APP_DIR>
```

### Parameters
- `YOUR_DOMAIN`: Your domain name (e.g., example.com)
- `YOUR_EMAIL`: Your email for Let's Encrypt SSL certificates
- `APP_DIR`: Directory where your Node.js application will be deployed (e.g., /var/www/myapp)

### Example
```bash
sudo bash setup_server.sh example.com admin@example.com /var/www/myapp
```

### What it does:
1. Updates system packages and installs essential tools
2. Installs Node.js 22
3. Installs and configures PostgreSQL 17
4. Installs Valkey (Redis-compatible)
5. Sets up Nginx with SSL using Let's Encrypt
6. Configures UFW firewall
7. Creates a systemd service for your Node.js application

---

## create_db_user.sh

### Description
Creates a secure PostgreSQL user and database with restricted permissions.

### Prerequisites
- PostgreSQL installed
- Sudo privileges

### Usage
```bash
sudo bash create_db_user.sh <DB_USERNAME> <DB_PASSWORD> <DB_NAME>
```

### Parameters
- `DB_USERNAME`: Username for the new database user
- `DB_PASSWORD`: Password for the new database user
- `DB_NAME`: Name of the database to create

### Example
```bash
sudo bash create_db_user.sh myuser mypassword mydatabase
```

### What it does:
1. Creates a new PostgreSQL role if it doesn't exist
2. Creates a new database owned by the new user
3. Restricts public access to the database
4. Revokes unnecessary permissions

---

## db_backup.sh

### Description
Creates a compressed backup of a PostgreSQL database and uploads it to Cloudflare R2 storage.

### Prerequisites
- PostgreSQL client tools (pg_dump)
- AWS CLI v2 configured with R2 credentials
- gzip
- Proper PostgreSQL user permissions

### Required Environment Variables
```bash
export AWS_ACCESS_KEY_ID="your-r2-access-key"
export AWS_SECRET_ACCESS_KEY="your-r2-secret-key"
export AWS_DEFAULT_REGION="auto"
export R2_ACCOUNT_ID="your-cloudflare-account-id"
export R2_BUCKET="your-bucket-name"
# Optional:
export R2_PATH="backups"
```

### Usage
1. Make the script executable:
   ```bash
   chmod +x db_backup.sh
   ```
2. Configure the database connection details in the script
3. Run the script:
   ```bash
   ./db_backup.sh
   ```

### Cron Example (daily at 2:00 AM)
```
0 2 * * * /path/to/db_backup.sh
```

### What it does:
1. Creates a timestamped backup of the specified database
2. Compresses the backup using gzip
3. Uploads the backup to Cloudflare R2
4. Optionally removes the local backup file after upload

---

## db_restore.sh

### Description
Restores a PostgreSQL database from a backup stored in Cloudflare R2.

### Prerequisites
- PostgreSQL client tools (psql)
- AWS CLI v2 configured with R2 credentials
- gzip
- Proper PostgreSQL user permissions

### Required Environment Variables
```bash
export AWS_ACCESS_KEY_ID="your-r2-access-key"
export AWS_SECRET_ACCESS_KEY="your-r2-secret-key"
export AWS_DEFAULT_REGION="auto"
export R2_ACCOUNT_ID="your-cloudflare-account-id"
export R2_BUCKET="your-bucket-name"
```

### Usage
```bash
./db_restore.sh s3://<bucket>/<path>/<filename>.sql.gz
```

### Example
```bash
./db_restore.sh s3://my-backups/production/mydb_31-05-2025_02:00.sql.gz
```

### What it does:
1. Downloads the specified backup file from Cloudflare R2
2. Decompresses the backup
3. Restores it to the specified PostgreSQL database
4. Optionally removes the downloaded backup file after restoration

---

## Security Notes

1. Always store sensitive information (passwords, API keys) in environment variables, not in scripts
2. Use strong, unique passwords for database users
3. Regularly rotate your R2 access keys
4. Ensure proper file permissions on all scripts (e.g., `chmod 700 *.sh`)
5. Regularly test your backup and restore procedures

## Setting Up Daily Backups at 11:30 PM

To automatically run the backup script every day at 11:30 PM, follow these steps:

### 1. Make the backup script executable (if not already):
```bash
chmod +x /path/to/db_backup.sh
```

### 2. Set up environment variables
Create a file to store your environment variables (e.g., `/etc/backup_env`):
```bash
# Edit with your actual values
export AWS_ACCESS_KEY_ID="your-r2-access-key"
export AWS_SECRET_ACCESS_KEY="your-r2-secret-key"
export AWS_DEFAULT_REGION="auto"
export R2_ACCOUNT_ID="your-cloudflare-account-id"
export R2_BUCKET="your-bucket-name"
# Optional: Set a specific path within the bucket
export R2_PATH="daily-backups"
# PostgreSQL connection details
export PGPASSWORD="your-db-password"
```

Secure the file:
```bash
sudo chmod 600 /etc/backup_env
```

### 3. Create a wrapper script (recommended)
Create a wrapper script that loads the environment and runs the backup:

```bash
#!/bin/bash
# /usr/local/bin/run_backup.sh

# Load environment variables
source /etc/backup_env

# Run the backup script
/path/to/db_backup.sh

# Log the backup completion
echo "[$(date)] Backup completed with status $?" >> /var/log/backup.log
```

Make it executable:
```bash
sudo chmod +x /usr/local/bin/run_backup.sh
```

### 4. Set up the cron job
Edit the root user's crontab:
```bash
sudo crontab -e
```

Add the following line to run the backup daily at 11:30 PM:
```
30 23 * * * /usr/local/bin/run_backup.sh
```

### 5. Verify the cron job
Check that the cron job was added successfully:
```bash
sudo crontab -l
```

### 6. Monitor the backup logs
Check the log file to ensure backups are running as expected:
```bash
tail -f /var/log/backup.log
```

### 7. Test the backup (recommended)
Before relying on the automated backup, test it manually:
```bash
sudo /usr/local/bin/run_backup.sh
```

### 8. Regular Maintenance
- Monitor disk space to ensure you have enough storage for backups
- Periodically test restoring from backups to ensure they're working
- Rotate logs to prevent them from growing too large

## License
This project is licensed under the MIT License - see the LICENSE file for details.