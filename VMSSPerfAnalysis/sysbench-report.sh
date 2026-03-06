#!/usr/bin/env bash
# Helper script to run sysbench and post results to Log Analytics (for local testing)
set -euo pipefail
if [ -z "${1-}" ] || [ -z "${2-}" ]; then
  echo "Usage: sysbench-report.sh <workspaceId> <workspaceKey> [duration_seconds]"
  exit 2
fi
workspaceId="$1"
workspaceKey="$2"
duration="${3:-30}"
HOSTNAME=$(hostname)
OUTPUT_FILE=/tmp/sysbench-${HOSTNAME}.log
sudo apt-get update -y
sudo apt-get install -y sysbench python3 python3-pip curl jq
sysbench cpu --threads=$(nproc) --time=${duration} run > ${OUTPUT_FILE} 2>&1 || true
payload=$(jq -Rs --arg host "${HOSTNAME}" '{Host: $host, Output: .}' < ${OUTPUT_FILE})
dateString=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")
contentLength=$(printf "%s" "$payload" | wc -c)
resourcePath="/api/logs"
stringToSign="POST\n${contentLength}\napplication/json\nx-ms-date:${dateString}\n${resourcePath}"
signature=$(python3 - <<PY
import sys, hmac, hashlib, base64
key = base64.b64decode(sys.argv[1])
sig = hmac.new(key, sys.argv[2].encode('utf-8'), hashlib.sha256).digest()
print(base64.b64encode(sig).decode())
PY
"${workspaceKey}" "$stringToSign")
authHeader="SharedKey ${workspaceId}:${signature}"
url="https://${workspaceId}.ods.opinsights.azure.com${resourcePath}?api-version=2016-04-01"
curl -s -S -H "Content-Type: application/json" -H "Authorization: ${authHeader}" -H "Log-Type: SysbenchPerf" -H "x-ms-date: ${dateString}" -d "$payload" "$url" || true
