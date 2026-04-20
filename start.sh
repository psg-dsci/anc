#!/bin/bash
set -euo pipefail  # -u catches undefined vars, -o pipefail catches pipe failures

# ── Config ────────────────────────────────────────────────────────────────────
APP_DIR="/home/ec2-user/app"
APP_FILE="app.py"
LOG_FILE="$APP_DIR/app.log"
PORT=5000
STARTUP_WAIT=3
PIP_CMD=""

# ── Helpers ───────────────────────────────────────────────────────────────────
log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
ok()    { log "✅ $*"; }
info()  { log "ℹ️  $*"; }
fail()  { log "❌ $*" >&2; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
log "🚀 Starting deployment..."

[[ -d "$APP_DIR" ]]       || fail "App directory '$APP_DIR' not found."
[[ -f "$APP_DIR/$APP_FILE" ]] || fail "App file '$APP_DIR/$APP_FILE' not found."

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || fail "Cannot write to log file: $LOG_FILE"

cd "$APP_DIR"

# ── Python check ──────────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    info "Python3 not found. Installing..."
    sudo yum install python3 -y || fail "Failed to install Python3."
fi

PYTHON_VERSION=$(python3 --version 2>&1)
ok "Using $PYTHON_VERSION"

# ── Resolve pip ───────────────────────────────────────────────────────────────
if command -v pip3 &>/dev/null; then
    PIP_CMD="pip3"
elif python3 -m pip --version &>/dev/null; then
    PIP_CMD="python3 -m pip"
else
    fail "pip not found. Install it with: sudo yum install python3-pip -y"
fi

# ── Install Flask ─────────────────────────────────────────────────────────────
if ! python3 -c "import flask" &>/dev/null; then
    info "Flask not found. Installing..."
    $PIP_CMD install flask --quiet || fail "Failed to install Flask."
fi

FLASK_VERSION=$(python3 -c "import flask; print(flask.__version__)" 2>/dev/null)
ok "Flask $FLASK_VERSION ready."

# ── Stop old instance ─────────────────────────────────────────────────────────
if pgrep -f "$APP_FILE" &>/dev/null; then
    info "Stopping existing instance of $APP_FILE..."
    sudo pkill -f "$APP_FILE" || true
    sleep 1
    # Force kill if still alive
    if pgrep -f "$APP_FILE" &>/dev/null; then
        sudo pkill -9 -f "$APP_FILE" || true
        sleep 1
    fi
    ok "Old instance stopped."
else
    info "No running instance found. Skipping stop."
fi

# Check if port is still in use by another process
if ss -tlnp "sport = :$PORT" 2>/dev/null | grep -q ":$PORT"; then
    fail "Port $PORT is still in use. Free it and retry."
fi

# ── Launch app ────────────────────────────────────────────────────────────────
info "Starting Flask app..."
nohup python3 "$APP_FILE" > "$LOG_FILE" 2>&1 &
APP_PID=$!

# Wait and verify
sleep "$STARTUP_WAIT"

if ! kill -0 "$APP_PID" 2>/dev/null; then
    fail "App process (PID $APP_PID) died on startup. Logs:\n$(tail -20 "$LOG_FILE")"
fi

if ! pgrep -f "$APP_FILE" &>/dev/null; then
    fail "App not running after ${STARTUP_WAIT}s. Logs:\n$(tail -20 "$LOG_FILE")"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
EC2_IP=$(curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "<EC2-IP>")

ok "App started! PID: $APP_PID"
log "🌐 Access: http://${EC2_IP}:${PORT}"
log "📄 Logs:   tail -f $LOG_FILE"
