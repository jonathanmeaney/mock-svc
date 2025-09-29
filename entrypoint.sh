#!/usr/bin/env sh
set -euo pipefail

: "${CONFIG_PATH:=/config/imposters.json}"

echo "Starting mock-svc (direct mode only)"
if [ ! -f "$CONFIG_PATH" ]; then
  echo "ERROR: CONFIG_PATH '$CONFIG_PATH' not found. Mount your imposters file into the container."
  exit 1
fi
case "$CONFIG_PATH" in
  *.js)
    # Convert a CommonJS module.exports = { imposters: [...] } file to JSON mountebank can parse
    if command -v node >/dev/null 2>&1; then
      TMP_JSON="/tmp/imposters-converted.json"
      echo "Converting JS config to JSON at $TMP_JSON"
      node -e 'const cfg=require(process.argv[1]); process.stdout.write(JSON.stringify(cfg,null,2));' "$CONFIG_PATH" > "$TMP_JSON"
      CONFIG_PATH="$TMP_JSON"
    else
      echo "Node runtime not available to convert JS config; supply a JSON or YAML config instead." >&2
      exit 2
    fi
    ;;
esac

echo "Launching mountebank with --configfile $CONFIG_PATH"
exec mb --allowInjection --cors --loglevel info --configfile "$CONFIG_PATH"
