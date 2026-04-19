#!/bin/bash

set -e  # stop on error

APP_DIR="/home/ec2-user/app"
LOG_FILE="$APP_DIR/app.log"

echo "🚀 Starting deployment..."

cd $APP_DIR || { echo "❌ App directory not found"; exit 1; }

# Install dependencies only if missing
if ! command -v python3 &> /dev/null
then
    echo "📦 Installing Python3..."
    sudo yum install python3 -y
fi

if ! python3 -c "import flask" &> /dev/null
then
    echo "📦 Installing Flask..."
    pip3 install flask
fi

# Kill old app safely
echo "🧹 Stopping old app (if running)..."
sudo pkill -f app.py || true

# Start app with logging
echo "▶️ Starting Flask app..."
nohup python3 app.py > "$LOG_FILE" 2>&1 &

sleep 2

# Verify app is running
if pgrep -f app.py > /dev/null
then
    echo "✅ App started successfully!"
    echo "🌐 Access: http://<EC2-IP>:5000"
else
    echo "❌ App failed to start. Check logs:"
    echo "cat $LOG_FILE"
    exit 1
fi