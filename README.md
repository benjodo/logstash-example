## Logstash → Datadog (HTTP JSON on port 8080)

Accept HTTP JSON logs on 0.0.0.0:8080 and forward them to Datadog. TLS termination is expected to happen outside the container (e.g., load balancer or platform proxy).

### Quick start

Build the image:

```bash
docker build -t logstash-datadog .
```

Run the container (no auth on input):

```bash
docker run --rm -p 8080:8080 \
  -e DATADOG_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -e DATADOG_SITE=datadoghq.com \
  -e DD_SERVICE=myapp \
  -e DD_ENV=staging \
  -e DD_TAGS="team:platform,region:us-east-1" \
  logstash-datadog
```

Send a test log:

```bash
curl -sS -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"hello","level":"info","app":"example"}'
```

Optional (non-Aptible drains) Basic Auth on the ingestion endpoint:

```bash
docker run --rm -p 8080:8080 \
  -e DATADOG_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -e INPUT_BASIC_AUTH_USER=ingest \
  -e INPUT_BASIC_AUTH_PASS=secret \
  logstash-datadog

# Then:
curl -u ingest:secret -sS -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"secured log"}'
```

### Environment variables

- **DATADOG_API_KEY**: Required. Datadog API key used in the `DD-API-KEY` header.
- **DATADOG_SITE**: Datadog site. Default `datadoghq.com`. Examples: `datadoghq.eu`, `us3.datadoghq.com`, `us5.datadoghq.com`, `gcp.datadoghq.com`.
- **DD_SOURCE**: Sets `ddsource` field. Default `logstash`.
- **DD_SERVICE**: Sets `service` field. Default `log-ingest`.
- **DD_ENV**: Sets `env` field. Default `production`.
- **DD_TAGS**: Comma-separated `key:value` tags (e.g., `team:platform,region:us-east-1`). Optional.
- **LOGSTASH_HTTP_HOST**: HTTP input bind host. Default `0.0.0.0`.
- **LOGSTASH_HTTP_PORT**: HTTP input port. Default `8080`.
- **LOGSTASH_HTTP_THREADS**: HTTP input worker threads. Default `4`.
- **INPUT_BASIC_AUTH_USER** / **INPUT_BASIC_AUTH_PASS**: If both provided, Basic Auth is enabled on the HTTP input.
- **LOGSTASH_LOG_LEVEL**: Logstash internal log level (`fatal|error|warn|info|debug|trace`). Default `warn`.
- **LOGSTASH_HTTP_MAX_CONTENT_LENGTH**: Max request body size in bytes. Default `5242880` (5 MiB).
- **LOGSTASH_ENABLE_STDOUT**: When `true`, also log events to stdout (`rubydebug`). Default `false`.
- **PIPELINE_WORKERS**: Optional Logstash pipeline workers (`-w`).
- **PIPELINE_BATCH_SIZE**: Optional Logstash pipeline batch size (`-b`).
- **QUEUE_TYPE**: Logstash queue type (`memory` or `persisted`). Default `memory`.
- **LS_JAVA_OPTS**: JVM flags for Logstash (e.g., `-Xms256m -Xmx256m`). Passed through by the base image.

### How it works

- HTTP input listens on `0.0.0.0:8080` with `ssl => false` and `codec => json`.
- Each event is enriched with `ddsource`, `service`, `env` and optional `ddtags`.
- Output uses Logstash `http` output to POST JSON to `https://http-intake.logs.${DATADOG_SITE}/api/v2/logs` with Datadog headers.
- Also logs to container stdout for debugging/observability when `LOGSTASH_ENABLE_STDOUT=true`.

### Aptible notes

- Prefer an internal-only endpoint for the Logstash service (not internet-exposed). Aptible log drains do not support Basic Auth.
- Expose container port `8080`. Aptible will terminate TLS upstream and forward plaintext HTTP to the container.
- Configure environment variables on the app (at minimum, `DATADOG_API_KEY`).
- Tune verbosity with `LOGSTASH_LOG_LEVEL` (defaults to `warn`).

### File overview

- `Dockerfile`: Logstash base + required plugins + entrypoint. Exposes 8080.
- `entrypoint.sh`: Renders `pipeline/logstash.conf` and `config/logstash.yml` from environment and execs Logstash.

### Security and hygiene

- Secrets avoidance: sensitive values (e.g., `DATADOG_API_KEY`, Basic Auth creds) are referenced via environment variable substitution in the Logstash config, so they are not written in cleartext to disk.
- Exposure: prefer internal-only ingress on Aptible; restrict sources at the platform layer. TLS termination should be upstream.
- Input hardening: request body capped by `LOGSTASH_HTTP_MAX_CONTENT_LENGTH` (default 5 MiB). Adjust based on expected log size.
- Privileges: container runs as `root` to bind port 80. For stricter hardening, grant `cap_net_bind_service` to the Java binary and run as the non-root `logstash` user instead, or bind to a high port and map externally.
- Verbosity: set `LOGSTASH_LOG_LEVEL` to `warn`/`error` in production; keep `LOGSTASH_ENABLE_STDOUT=false` to avoid duplicating logs.


