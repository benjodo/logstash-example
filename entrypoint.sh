#!/usr/bin/env bash
set -euo pipefail

: "${DATADOG_SITE:=datadoghq.com}"
: "${DD_SOURCE:=logstash}"
: "${DD_SERVICE:=log-ingest}"
: "${DD_ENV:=production}"
: "${DD_TAGS:=}"
: "${LOGSTASH_HTTP_HOST:=0.0.0.0}"
: "${LOGSTASH_HTTP_PORT:=8080}"
: "${LOGSTASH_HTTP_THREADS:=4}"
: "${QUEUE_TYPE:=memory}"
: "${LOGSTASH_LOG_LEVEL:=warn}"
: "${LOGSTASH_HTTP_MAX_CONTENT_LENGTH:=5242880}"
: "${LOGSTASH_ENABLE_STDOUT:=false}"

if [[ -z "${DATADOG_API_KEY:-}" ]]; then
  echo "DATADOG_API_KEY is required" >&2
  exit 1
fi

# Ensure Logstash sees defaults via environment for ${VAR} substitution
export DATADOG_SITE DD_SOURCE DD_SERVICE DD_ENV DD_TAGS

PIPELINE_DIR="/usr/share/logstash/pipeline"
CONFIG_DIR="/usr/share/logstash/config"

mkdir -p "$PIPELINE_DIR" "$CONFIG_DIR"

# Generate pipeline configuration
PIPELINE_FILE="$PIPELINE_DIR/logstash.conf"

cat > "$PIPELINE_FILE" <<EOF
input {
  http {
    host => "${LOGSTASH_HTTP_HOST}"
    port => ${LOGSTASH_HTTP_PORT}
    ssl => false
    codec => json
    threads => ${LOGSTASH_HTTP_THREADS}
    max_content_length => ${LOGSTASH_HTTP_MAX_CONTENT_LENGTH}
EOF

if [[ -n "${INPUT_BASIC_AUTH_USER:-}" && -n "${INPUT_BASIC_AUTH_PASS:-}" ]]; then
  cat >> "$PIPELINE_FILE" <<EOF
    user => "${INPUT_BASIC_AUTH_USER}"
    password => "${INPUT_BASIC_AUTH_PASS}"
EOF
fi

cat >> "$PIPELINE_FILE" <<EOF
  }
}
filter {
  mutate {
    add_field => {
      "ddsource" => "\${DD_SOURCE:logstash}"
      "service"  => "\${DD_SERVICE:log-ingest}"
      "env"      => "\${DD_ENV:production}"
    }
  }
EOF

if [[ -n "${DD_TAGS}" ]]; then
  cat >> "$PIPELINE_FILE" <<EOF
  mutate { add_field => { "ddtags" => "\${DD_TAGS}" } }
EOF
fi

cat >> "$PIPELINE_FILE" <<EOF
}
output {
  http {
    url => "https://http-intake.logs.${DATADOG_SITE}/api/v2/logs"
    http_method => "post"
    format => "json"
    content_type => "application/json"
    headers => {
      "DD-API-KEY" => "\${DATADOG_API_KEY}"
      "DD-Source"  => "\${DD_SOURCE:logstash}"
      "DD-Service" => "\${DD_SERVICE:log-ingest}"
      "DD-Env"     => "\${DD_ENV:production}"
    }
    retry_failed => true
    automatic_retries => 5
  }
EOF

if [[ "${LOGSTASH_ENABLE_STDOUT,,}" == "true" ]]; then
  echo '  stdout { codec => rubydebug }' >> "$PIPELINE_FILE"
fi

echo '}' >> "$PIPELINE_FILE"

# Optional logstash.yml tuning
cat > "$CONFIG_DIR/logstash.yml" <<YML
queue.type: ${QUEUE_TYPE}
YML

ARGS=("-f" "$PIPELINE_FILE")
if [[ -n "${PIPELINE_WORKERS:-}" ]]; then ARGS+=("-w" "${PIPELINE_WORKERS}"); fi
if [[ -n "${PIPELINE_BATCH_SIZE:-}" ]]; then ARGS+=("-b" "${PIPELINE_BATCH_SIZE}"); fi
if [[ -n "${LOGSTASH_LOG_LEVEL:-}" ]]; then ARGS+=("--log.level" "${LOGSTASH_LOG_LEVEL}"); fi

exec /usr/local/bin/docker-entrypoint "${ARGS[@]}"


