#!/bin/bash
set -x  
set -e

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a /var/log/user-data.log
}

log "Starting user data script execution"

# Configure CloudWatch Agent
cat > /tmp/cloudwatch-config.json << 'EOL'
{
  "agent": {
    "metrics_collection_interval": 5,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/webapp.log",
            "log_group_name": "/webapp/logs",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/webapp/logs",
            "log_stream_name": "{instance_id}-user-data",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 5,
        "metrics_aggregation_interval": 5
      }
    }
  }
}
EOL

# Configure CloudWatch agent
log "Configuring CloudWatch agent"
sudo mv /tmp/cloudwatch-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl restart amazon-cloudwatch-agent

# Verify CloudWatch agent status
log "Verifying CloudWatch agent status"
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status

# Wait for RDS to be available
log "Waiting for database connection"
timeout=300
end_time=$((SECONDS + timeout))
while ! nc -z ${db_host} 3306; do
    if [ $SECONDS -ge $end_time ]; then
        log "Timeout waiting for database to become available"
        exit 1
    fi
    log "Waiting for database to be available..."
    sleep 10
done

log "Database is available, configuring application"

# Update the package list and install dependencies
log "Updating package list and installing dependencies"
sudo apt-get update -y
sudo apt-get install -y unzip curl jq

# Download and install AWS CLI v2
log "Downloading and installing AWS CLI v2"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --update

# Verify installation
log "Verifying AWS CLI installation"
aws --version

# Clean up installation files
log "Cleaning up installation files"
rm -rf awscliv2.zip aws/

# Create or update .env file with secrets from Secrets Manager
DB_PASS=$(aws secretsmanager get-secret-value --secret-id "${rds_db_password_name}" --query SecretString --output text | jq -r .DB_PASS)
if [ -z "$DB_PASS" ]; then
    log "Failed to retrieve DB_PASS from Secrets Manager."
fi

SENDGRID_API_KEY=$(aws secretsmanager get-secret-value --secret-id "${sendgrid_credentials_name}" --query SecretString --output text | jq -r .SENDGRID_API_KEY)
if [ -z "$SENDGRID_API_KEY" ]; then
    log "Failed to retrieve SENDGRID_API_KEY from Secrets Manager."
fi

sendgrid_verified_sender=$(aws secretsmanager get-secret-value --secret-id "${sendgrid_credentials_name}" --query SecretString --output text | jq -r .sendgrid_verified_sender)
if [ -z "$sendgrid_verified_sender" ]; then
    log "Failed to retrieve sendgrid_verified_sender from Secrets Manager."
fi

sudo bash -c "cat > /tmp/new_env << EOT
DB_HOST=${db_host}
DB_PORT=3306
DB_USER=${db_username}
DB_PASS=$DB_PASS
DB_DATABASE=${db_name}
PORT=${app_port}
S3_BUCKET=${s3_bucket}
AWS_REGION=${region}
SENDGRID_API_KEY=$SENDGRID_API_KEY
DOMAIN_NAME=${domain_name}
SENDGRID_VERIFIED_SENDER=$sendgrid_verified_sender
SNS_TOPIC_ARN=${sns_topic_arn}
EOT"

# Check if .env file exists and update it
if [ -f /opt/app/.env ]; then
    log "Existing .env file found, creating backup"
    sudo cp /opt/app/.env /opt/app/.env.bak
    sudo cp /tmp/new_env /opt/app/.env
else
    log "Creating new .env file"
    sudo mkdir -p /opt/app
    sudo cp /tmp/new_env /opt/app/.env
fi

# Set proper permissions for the .env file
log "Setting file permissions"
sudo chown csye6225:csye6225 /opt/app/.env || true # Adjust user/group as necessary or handle errors gracefully if they don't exist.
sudo chmod 600 /opt/app/.env

# Clean up temporary files used during setup.
sudo rm -f /tmp/new_env

# Restart application service.
log "Restarting webapp service"
sleep 5 # Allow some time before restarting services.
if sudo systemctl restart webapp; then 
    log "Webapp service restarted successfully"
else 
    log "Failed to restart webapp service" 
fi 

# Log final status of webapp service.
sudo systemctl status webapp | sudo tee -a /var/log/user-data.log 

log "User data script completed successfully"