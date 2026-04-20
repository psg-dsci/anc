#!/bin/bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
APP_DIR="/home/ec2-user/app"
APP_FILE="app.py"
LOG_FILE="$APP_DIR/app.log"
PORT=80
STARTUP_WAIT=3
PIP_CMD=""

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
ok()   { log "✅ $*"; }
info() { log "ℹ️  $*"; }
fail() { log "❌ $*" >&2; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
log "🚀 Starting deployment..."

[[ -d "$APP_DIR" ]]           || fail "App directory '$APP_DIR' not found."
[[ -f "$APP_DIR/$APP_FILE" ]] || fail "App file '$APP_DIR/$APP_FILE' not found."

touch "$LOG_FILE" 2>/dev/null || fail "Cannot write to log file: $LOG_FILE"

cd "$APP_DIR"

# ── Python check ──────────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    info "Python3 not found. Installing..."
    sudo yum install python3 -y || fail "Failed to install Python3."
fi
ok "Using $(python3 --version 2>&1)"

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
ok "Flask $(python3 -c 'import flask; print(flask.__version__)') ready."

# ── Stop old instance ─────────────────────────────────────────────────────────
if pgrep -f "$APP_FILE" &>/dev/null; then
    info "Stopping existing instance..."
    sudo pkill -f "$APP_FILE" || true
    sleep 1
    sudo pkill -9 -f "$APP_FILE" 2>/dev/null || true
    sleep 1
    ok "Old instance stopped."
else
    info "No running instance found. Skipping stop."
fi

# ── Launch app fully detached from this shell ─────────────────────────────────
info "Starting Flask app in background..."

# setsid + redirects fully detach from the CodeDeploy agent's process group
# so the agent doesn't wait for this process to finish
sudo setsid bash -c "
    cd $APP_DIR
    python3 $APP_FILE >> $LOG_FILE 2>&1
" &

disown $!
sleep "$STARTUP_WAIT"

# ── Verify ────────────────────────────────────────────────────────────────────
if pgrep -f "$APP_FILE" &>/dev/null; then
    ok "App is running! PID: $(pgrep -f $APP_FILE)"
    log "🌐 Access: http://$(curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo '<EC2-IP>'):${PORT}"
    log "📄 Logs:   tail -f $LOG_FILE"
else
    fail "App failed to start. Last logs:\n$(tail -20 $LOG_FILE)"
fi
