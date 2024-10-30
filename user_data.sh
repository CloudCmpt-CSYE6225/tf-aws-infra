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
    "metrics_collection_interval": 60,
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
        "metrics_collection_interval": 60,
        "metrics_aggregation_interval": 60
      },
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "disk_used_percent"
        ],
        "metrics_collection_interval": 60
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

# Create or update .env file
log "Creating application environment file"
sudo bash -c "cat > /tmp/new_env << EOT
DB_HOST=${db_host}
DB_PORT=3306
DB_USER=${db_username}
DB_PASS=${db_password}
DB_DATABASE=${db_name}
PORT=${app_port}
S3_BUCKET=${s3_bucket}
AWS_REGION=${region}
SENDGRID_API_KEY=${sendgrid_api_key}
DOMAIN_NAME=${domain_name}
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

# Set proper permissions
log "Setting file permissions"
sudo chown csye6225:csye6225 /opt/app/.env
sudo chmod 600 /opt/app/.env

# Clean up
sudo rm -f /tmp/new_env

# Restart application
log "Restarting webapp service"
sleep 5
if sudo systemctl restart webapp; then
    log "Webapp service restarted successfully"
    sudo systemctl status webapp | sudo tee -a /var/log/user-data.log
else
    log "Failed to restart webapp service"
    sudo systemctl status webapp | sudo tee -a /var/log/user-data.log
    exit 1
fi

log "User data script completed successfully"