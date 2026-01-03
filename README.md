# SigNoz + OpenTelemetry Collector Setup

Quick setup for running SigNoz with a centralized OpenTelemetry Collector that all your applications can send data to.

## What This Does

This setup provides:

- **SigNoz**: Open-source observability platform (traces, metrics, logs)
- **OpenTelemetry Collector**: Central ingestion point for all your apps
- **Architecture**: All your apps → OTel Collector (localhost:4317) → SigNoz

This is better than having each app send directly to SigNoz because:
- Single place to manage sampling, batching, and retry policies
- Easier to debug and monitor data flow
- No ingestion key needed in your application repos
- Scales from development to production

## Prerequisites

- Docker
- Docker Compose
- ~2GB of disk space for ClickHouse data
- Ports 3301, 4317, 4318, 8080, 9000 available

## Quick Start

### 1. Initial Setup (run once)

```bash
chmod +x setup-signoz.sh
./setup-signoz.sh
```

This creates:
- `signoz-stack/` directory with all configuration
- `.env` file with default settings
- OTel Collector configuration
- Docker Compose setup

### 2. Start the Stack

```bash
chmod +x signoz-stack.sh
./signoz-stack.sh start
```

Wait for services to be ready (20-30 seconds).

### 3. Access SigNoz

Open http://localhost:3301 in your browser

### 4. Configure Your Applications

See `INSTRUMENTATION_GUIDE.sh` for language-specific instructions:

```bash
./INSTRUMENTATION_GUIDE.sh
```

**Quick example (Node.js):**

```bash
# Install
npm install @opentelemetry/api @opentelemetry/auto-instrumentations-node

# Run with auto-instrumentation
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_SERVICE_NAME=my-app \
node --require @opentelemetry/auto-instrumentations-node/register app.js
```

## Scripts

### `setup-signoz.sh`
**Run once** to initialize the stack. Creates configuration files and directory structure.

```bash
./setup-signoz.sh
```

### `signoz-stack.sh`
Daily management commands for the stack.

```bash
# Start the stack
./signoz-stack.sh start

# Stop the stack
./signoz-stack.sh stop

# Restart
./signoz-stack.sh restart

# View status
./signoz-stack.sh status

# View logs (all services)
./signoz-stack.sh logs

# View only OTel Collector logs
./signoz-stack.sh logs-otel

# View SigNoz backend logs
./signoz-stack.sh logs-signoz

# Check health of all services
./signoz-stack.sh health

# Send test telemetry (requires Go installed)
./signoz-stack.sh test-telemetry

# Remove everything (including volumes)
./signoz-stack.sh clean
```

### `INSTRUMENTATION_GUIDE.sh`
Reference guide for instrumenting applications.

```bash
./INSTRUMENTATION_GUIDE.sh
```

## Directory Structure

```
.
├── setup-signoz.sh                    # Initial setup script
├── signoz-stack.sh                    # Management script
├── INSTRUMENTATION_GUIDE.sh           # Quick reference
└── signoz-stack/                      # Created by setup-signoz.sh
    ├── docker-compose.yml             # Docker Compose configuration
    ├── .env                           # Environment variables
    ├── otel-collector/
    │   └── config.yaml                # OTel Collector configuration
    ├── signoz-otel-collector-config.yaml
    ├── query-service-config.yaml
    ├── clickhouse/
    │   ├── config.xml
    │   └── users.xml
    ├── logs/                          # Docker logs directory
    └── clickhouse-data/               # ClickHouse data (created by Docker)
```

## Services

### OpenTelemetry Collector (otel-collector)
- **Purpose**: Central ingestion point for all your applications
- **Ports**:
  - 4317: gRPC OTLP receiver (preferred)
  - 4318: HTTP OTLP receiver
  - 13133: Health check endpoint
- **Health check**: `curl http://localhost:13133`

### SigNoz Stack
- **Frontend**: http://localhost:3301
- **Backend (ClickHouse)**: Stores all telemetry data
- **Query Service**: HTTP API for SigNoz UI
- **OTel Collector**: Backend component that processes data from OTel Collector

## Configuration

### Environment Variables

Edit `signoz-stack/.env` to customize:

```bash
# Port for SigNoz UI
SIGNOZ_PORT=3301

# OTel Collector ports
OTEL_COLLECTOR_GRPC_PORT=4317
OTEL_COLLECTOR_HTTP_PORT=4318
OTEL_COLLECTOR_HEALTH_PORT=13133

# Memory limits for OTel Collector
OTEL_MEMORY_LIMIT=512
OTEL_MEMORY_SPIKE_LIMIT=128
```

### OTel Collector Configuration

Edit `signoz-stack/otel-collector/config.yaml` to:
- Change batch size/timeout for data export
- Add sampling policies
- Configure additional receivers
- Modify memory limits

## Common Tasks

### View application traces

1. Go to http://localhost:3301
2. Click "Traces" tab
3. Filter by service name or trace ID

### Monitor OTel Collector health

```bash
./signoz-stack.sh health
```

Or manually:
```bash
curl http://localhost:13133
```

### Check if data is flowing

```bash
./signoz-stack.sh logs-otel
```

Look for messages like "successfully exported spans" or "sent 100 spans"

### Stop the stack temporarily

```bash
./signoz-stack.sh stop
```

Services will exit but data persists (in Docker volumes).

### Clean everything up

```bash
./signoz-stack.sh clean
```

This removes all containers and volumes. **Data will be lost!**

### Increase memory limits

If OTel Collector crashes due to memory:

1. Edit `signoz-stack/otel-collector/config.yaml`
2. Change `limit_mib` under `memory_limiter`
3. Run `./signoz-stack.sh restart`

## Troubleshooting

### "Connection refused" when app tries to send data

**Host machine**: Use `localhost:4317`
**Docker container**: Use `http://otel-collector:4317`

### Data not appearing in SigNoz

1. Wait 5-10 seconds for data to be processed
2. Check OTel Collector logs: `./signoz-stack.sh logs-otel`
3. Verify your app is actually generating requests
4. Check service name is set with `OTEL_SERVICE_NAME`

### OTel Collector crashes

Check logs:
```bash
./signoz-stack.sh logs-otel
```

Common causes:
- Memory limit exceeded (increase `OTEL_MEMORY_LIMIT`)
- ClickHouse not responding (check `./signoz-stack.sh health`)
- Invalid config.yaml syntax

### ClickHouse not responding

```bash
docker-compose -f signoz-stack/docker-compose.yml logs clickhouse
```

Usually starts up within 30 seconds. If it keeps failing, the container might be out of disk space.

### SigNoz UI won't load

1. Check if frontend is running: `./signoz-stack.sh status`
2. Check browser console for errors
3. Clear browser cache and reload
4. Restart: `./signoz-stack.sh restart`

## Production Considerations

For production use:

1. **Persistent storage**: The setup uses Docker volumes which are persistent
2. **Memory management**: Adjust `OTEL_MEMORY_LIMIT` based on your traffic
3. **Sampling**: Consider enabling trace sampling to reduce data volume
4. **Retention**: Configure ClickHouse retention policies (advanced)
5. **TLS/Security**: Add authentication to SigNoz UI and OTel Collector
6. **Backup**: Regular backups of ClickHouse volumes
7. **Monitoring**: Monitor OTel Collector and ClickHouse metrics

## Instrumenting Your Applications

### Node.js/TypeScript

Auto-instrumentation (no code changes):
```bash
npm install @opentelemetry/api @opentelemetry/auto-instrumentations-node
node --require @opentelemetry/auto-instrumentations-node/register app.js
```

### Python

Auto-instrumentation (no code changes):
```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap --action=install
opentelemetry-instrument python app.py
```

### Docker

In docker-compose.yml:
```yaml
services:
  my-app:
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
      - OTEL_SERVICE_NAME=my-app
    depends_on:
      - otel-collector
```

See `INSTRUMENTATION_GUIDE.sh` for complete examples.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Applications                         │
│  (Node.js, Python, Docker containers, etc.)                │
│  All configured to send to localhost:4317                   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓ (gRPC or HTTP OTLP)
                    
┌──────────────────────────────────────────────────────────────┐
│         OpenTelemetry Collector (localhost:4317)            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Receives: Traces, Metrics, Logs                         ││
│  │ Processes: Batching, memory management, sampling        ││
│  │ Exports: To SigNoz backend                              ││
│  └─────────────────────────────────────────────────────────┘│
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
                    
┌──────────────────────────────────────────────────────────────┐
│                     SigNoz Stack                            │
│  ┌──────────────────────────────────────────────────────────┐│
│  │ Query Service (port 8080)                                ││
│  │     ↓                                                     ││
│  │ ClickHouse (port 9000) - Data storage & analytics       ││
│  │     ↓                                                     ││
│  │ Frontend (port 3301) - Web UI                           ││
│  └──────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
                           │
                           ↓
                    
                 http://localhost:3301
                   (View your traces, 
                  metrics, and logs!)
```

## Support

For issues with:
- **SigNoz**: https://github.com/SigNoz/signoz
- **OpenTelemetry**: https://opentelemetry.io
- **Docker Compose**: Docker documentation

## License

These scripts are provided as-is for setting up SigNoz locally.
SigNoz is licensed under SSPL (see https://github.com/SigNoz/signoz for details).
