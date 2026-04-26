#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$ROOT_DIR/vless-reality.env}"
TEMPLATE_FILE="$ROOT_DIR/templates/sing-box-server.json.tmpl"
SING_BOX_CLIENT_TEMPLATE="$ROOT_DIR/templates/sing-box-client.json.tmpl"
SING_BOX_MOBILE_TEMPLATE="$ROOT_DIR/templates/sing-box-mobile.json.tmpl"
CLASH_VERGE_TEMPLATE="$ROOT_DIR/templates/clash-verge.yaml.tmpl"
REMOTE_INSTALL_TEMPLATE="$ROOT_DIR/templates/remote-install.sh.tmpl"
REMOTE_APPLY_TEMPLATE="$ROOT_DIR/templates/remote-apply.sh.tmpl"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy $ROOT_DIR/vless-reality.env.example to $ENV_FILE and edit it."
  exit 1
fi
ENV_DIR="$(cd "$(dirname "$ENV_FILE")" && pwd)"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Missing template file: $TEMPLATE_FILE"
  exit 1
fi

if [[ ! -f "$SING_BOX_CLIENT_TEMPLATE" ]]; then
  echo "Missing template file: $SING_BOX_CLIENT_TEMPLATE"
  exit 1
fi

if [[ ! -f "$SING_BOX_MOBILE_TEMPLATE" ]]; then
  echo "Missing template file: $SING_BOX_MOBILE_TEMPLATE"
  exit 1
fi

if [[ ! -f "$CLASH_VERGE_TEMPLATE" ]]; then
  echo "Missing template file: $CLASH_VERGE_TEMPLATE"
  exit 1
fi

if [[ ! -f "$REMOTE_INSTALL_TEMPLATE" ]]; then
  echo "Missing template file: $REMOTE_INSTALL_TEMPLATE"
  exit 1
fi

if [[ ! -f "$REMOTE_APPLY_TEMPLATE" ]]; then
  echo "Missing template file: $REMOTE_APPLY_TEMPLATE"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

required_vars=(
  SERVER_HOST
  SSH_USER
  SERVER_PORT
  REALITY_SERVER_NAME
  REALITY_SERVER_PORT
  REMOTE_CONFIG_PATH
  REMOTE_SERVICE_NAME
)

for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required variable: $name"
    exit 1
  fi
done

SSH_PORT="${SSH_PORT:-22}"
INSTALL_DEPENDENCIES="${INSTALL_DEPENDENCIES:-true}"
CLIENT_NAME="${CLIENT_NAME:-default-client}"
UUID="${UUID:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
SING_BOX_VERSION="${SING_BOX_VERSION:-}"
LOCAL_MIXED_PORT="${LOCAL_MIXED_PORT:-7777}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output}"

if [[ -z "${SSH_KEY_PATH:-}" && -z "${SSH_PASSWORD:-}" ]]; then
  echo "Configure SSH_KEY_PATH or SSH_PASSWORD in $ENV_FILE"
  exit 1
fi

if [[ -n "${SSH_KEY_PATH:-}" && -n "${SSH_PASSWORD:-}" ]]; then
  echo "Use either SSH_KEY_PATH or SSH_PASSWORD, not both."
  exit 1
fi

if [[ -n "${SSH_KEY_PATH:-}" ]]; then
  SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
  if [[ "$SSH_KEY_PATH" != /* ]]; then
    SSH_KEY_PATH="$ENV_DIR/$SSH_KEY_PATH"
  fi
  if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "SSH key file not found: $SSH_KEY_PATH"
    exit 1
  fi
fi

require_local_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing local command: $1"
    exit 1
  fi
}

require_local_cmd ssh
require_local_cmd scp
require_local_cmd awk
require_local_cmd sed
require_local_cmd mktemp
require_local_cmd python3
require_local_cmd uuidgen
require_local_cmd openssl

if [[ -n "${SSH_PASSWORD:-}" ]]; then
  require_local_cmd sshpass
fi

if [[ -z "$UUID" ]]; then
  UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
fi

if [[ -z "$REALITY_SHORT_ID" ]]; then
  REALITY_SHORT_ID="$(openssl rand -hex 8)"
fi

ssh_base=(ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new)
scp_base=(scp -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new)

if [[ -n "${SSH_KEY_PATH:-}" ]]; then
  ssh_base+=(-i "$SSH_KEY_PATH")
  scp_base+=(-i "$SSH_KEY_PATH")
else
  ssh_base=(sshpass -p "$SSH_PASSWORD" "${ssh_base[@]}")
  scp_base=(sshpass -p "$SSH_PASSWORD" "${scp_base[@]}")
fi

remote="${SSH_USER}@${SERVER_HOST}"

run_remote() {
  "${ssh_base[@]}" "$remote" "$@"
}

copy_remote() {
  "${scp_base[@]}" "$1" "$remote:$2"
}

echo "==> Checking remote access"
run_remote "uname -a" >/dev/null

echo "==> Installing sing-box on remote host if needed"
remote_install_script="$(cat "$REMOTE_INSTALL_TEMPLATE")"

run_remote "INSTALL_DEPENDENCIES='$INSTALL_DEPENDENCIES' SING_BOX_VERSION='$SING_BOX_VERSION' bash -s" <<<"$remote_install_script"

echo "==> Generating REALITY keypair"
key_output="$(run_remote "sing-box generate reality-keypair")"
REALITY_PRIVATE_KEY="$(printf '%s\n' "$key_output" | awk '/PrivateKey:/ {print $2}')"
REALITY_PUBLIC_KEY="$(printf '%s\n' "$key_output" | awk '/PublicKey:/ {print $2}')"

if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
  echo "Failed to parse reality keypair output."
  echo "$key_output"
  exit 1
fi

export UUID
export REALITY_SHORT_ID
export REALITY_PRIVATE_KEY
export REALITY_PUBLIC_KEY
export CLIENT_NAME
export SERVER_HOST
export SERVER_PORT
export REALITY_SERVER_NAME
export REALITY_SERVER_PORT
export LOCAL_MIXED_PORT

safe_client_name="$(printf '%s' "$CLIENT_NAME" | tr ' /' '__')"
safe_server_host="$(printf '%s' "$SERVER_HOST" | sed 's/[^A-Za-z0-9._-]/_/g')"
client_output_dir="$OUTPUT_DIR/$safe_server_host"
mkdir -p "$client_output_dir"
local_sing_box_desktop_config="$client_output_dir/${safe_client_name}-sing-box-desktop.json"
local_sing_box_mobile_config="$client_output_dir/${safe_client_name}-sing-box-mobile.json"
local_clash_verge_config="$client_output_dir/${safe_client_name}-clash-verge.yaml"

tmp_config="$(mktemp)"
cleanup_local() {
  rm -f "$tmp_config"
}
trap cleanup_local EXIT

python3 - "$TEMPLATE_FILE" "$tmp_config" <<'PY'
import json
import os
import sys
from string import Template

template_path, output_path = sys.argv[1], sys.argv[2]
with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

rendered = Template(content).substitute(os.environ)
data = json.loads(rendered)

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

remote_tmp="/tmp/sing-box-config.json"
echo "==> Uploading config"
copy_remote "$tmp_config" "$remote_tmp"

remote_apply_script="$(cat "$REMOTE_APPLY_TEMPLATE")"

echo "==> Applying remote config and restarting service"
run_remote "REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' REMOTE_SERVICE_NAME='$REMOTE_SERVICE_NAME' SERVER_PORT='$SERVER_PORT' bash -s" <<<"$remote_apply_script"

echo "==> Generating local client configs"
python3 - "$SING_BOX_CLIENT_TEMPLATE" "$local_sing_box_desktop_config" <<'PY'
import json
import os
import sys
from string import Template

template_path, output_path = sys.argv[1], sys.argv[2]
with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

rendered = Template(content).substitute(os.environ)
data = json.loads(rendered)

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

python3 - "$SING_BOX_MOBILE_TEMPLATE" "$local_sing_box_mobile_config" <<'PY'
import json
import os
import sys
from string import Template

template_path, output_path = sys.argv[1], sys.argv[2]
with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

rendered = Template(content).substitute(os.environ)
data = json.loads(rendered)

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

python3 - "$CLASH_VERGE_TEMPLATE" "$local_clash_verge_config" <<'PY'
import os
import sys
from string import Template

template_path, output_path = sys.argv[1], sys.argv[2]
with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

rendered = Template(content).substitute(os.environ)

with open(output_path, "w", encoding="utf-8") as f:
    f.write(rendered)
    if not rendered.endswith("\n"):
        f.write("\n")
PY

cat <<EOF

Deployment complete.

Server:
  Address: ${SERVER_HOST}
  Port: ${SERVER_PORT}
  UUID: ${UUID}
  Flow: xtls-rprx-vision

REALITY:
  Server Name: ${REALITY_SERVER_NAME}
  Server Port: ${REALITY_SERVER_PORT}
  Public Key: ${REALITY_PUBLIC_KEY}
  Short ID: ${REALITY_SHORT_ID}

Local client configs:
  sing-box desktop: ${local_sing_box_desktop_config}
  sing-box mobile: ${local_sing_box_mobile_config}
  Clash Verge: ${local_clash_verge_config}
EOF
