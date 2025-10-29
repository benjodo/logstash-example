## Logstash → Datadog (HTTP JSON on port 80)

Accept HTTP JSON logs on 0.0.0.0:80 and forward them to Datadog. TLS termination is expected to happen outside the container (e.g., load balancer or platform proxy).

### Quick start

Build the image:

```bash
docker build -t logstash-datadog .
```

Run the container (no auth on input):

```bash
docker run --rm -p 80:80 \
  -e DATADOG_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -e DATADOG_SITE=datadoghq.com \
  -e DD_SERVICE=myapp \
  -e DD_ENV=staging \
  -e DD_TAGS="team:platform,region:us-east-1" \
  logstash-datadog
```

Send a test log:

```bash
curl -sS -X POST http://localhost:80 \
  -H 'Content-Type: application/json' \
  -d '{"message":"hello","level":"info","app":"example"}'
```

Enable Basic Auth on the ingestion endpoint:

```bash
docker run --rm -p 80:80 \
  -e DATADOG_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -e INPUT_BASIC_AUTH_USER=ingest \
  -e INPUT_BASIC_AUTH_PASS=secret \
  logstash-datadog

# Then:
curl -u ingest:secret -sS -X POST http://localhost:80 \
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
- **LOGSTASH_HTTP_PORT**: HTTP input port. Default `80`.
- **LOGSTASH_HTTP_THREADS**: HTTP input worker threads. Default `4`.
- **INPUT_BASIC_AUTH_USER** / **INPUT_BASIC_AUTH_PASS**: If both provided, Basic Auth is enabled on the HTTP input.
- **PIPELINE_WORKERS**: Optional Logstash pipeline workers (`-w`).
- **PIPELINE_BATCH_SIZE**: Optional Logstash pipeline batch size (`-b`).
- **QUEUE_TYPE**: Logstash queue type (`memory` or `persisted`). Default `memory`.
- **LS_JAVA_OPTS**: JVM flags for Logstash (e.g., `-Xms256m -Xmx256m`). Passed through by the base image.

### How it works

- HTTP input listens on `0.0.0.0:80` with `ssl => false` and `codec => json`.
- Each event is enriched with `ddsource`, `service`, `env` and optional `ddtags`.
- Output uses Logstash `http` output to POST JSON to `https://http-intake.logs.${DATADOG_SITE}/api/v2/logs` with Datadog headers.
- Also logs to container stdout for debugging/observability.

### Aptible notes

- Expose container port `80`. Aptible will terminate TLS upstream and forward plaintext HTTP to the container.
- Configure environment variables on the app (at minimum, `DATADOG_API_KEY`).
- If you need auth on the ingest endpoint, set `INPUT_BASIC_AUTH_USER` and `INPUT_BASIC_AUTH_PASS`.

### Security

- The image runs as root by default to bind to privileged port 80. If you prefer non-root, you can grant `cap_net_bind_service` to the Java binary at build time or switch to a higher, non-privileged port.

### File overview

- `Dockerfile`: Logstash base + required plugins + entrypoint. Exposes 80.
- `entrypoint.sh`: Renders `pipeline/logstash.conf` and `config/logstash.yml` from environment and execs Logstash.


