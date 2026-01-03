# SigNoz Test Applications

This directory contains example applications to validate log and trace sending to SigNoz.

## What's Included

- **Python Flask App** - Demonstrates OpenTelemetry tracing and structured logging sent via OTLP
- **TypeScript Express App** - Shows async operations with trace context and logs sent via OTLP
- **Load Generator** - Automatically generates test traffic

Both applications send traces and logs directly to the SigNoz OTLP collector using the OpenTelemetry SDK. This approach works well for non-admin Docker setups and is the recommended method for production deployments.

## Quick Start

### 1. Start the test applications

```bash
cd signoz-stack/examples
docker-compose up -d
```

This will start:
- Python app on http://localhost:5000
- TypeScript app on http://localhost:3002
- Automatic load generator

### 2. View in SigNoz

Open SigNoz UI: http://localhost:8900

Navigate to:
- **Services** → See `python-test-app` and `typescript-test-app`
- **Traces** → View distributed traces with multiple spans
- **Logs** → See structured logs with trace correlation (trace_id and span_id linking)

### 3. Manual Testing

#### Python App Endpoints

```bash
# Health check
curl http://localhost:5000/

# Simple traced request
curl http://localhost:5000/hello/YourName

# Slow operation with multiple spans
curl http://localhost:5000/slow

# Error simulation (50% chance of error)
curl http://localhost:5000/error

# Data processing with multiple items
curl http://localhost:5000/process
```

#### TypeScript App Endpoints

```bash
# Health check
curl http://localhost:3002/

# Simple greeting
curl http://localhost:3002/hello/Alice

# Calculate sum
curl -X POST http://localhost:3002/calculate \
  -H 'Content-Type: application/json' \
  -d '{"operation":"sum","values":[1,2,3,4,5]}'

# Calculate average
curl -X POST http://localhost:3002/calculate \
  -H 'Content-Type: application/json' \
  -d '{"operation":"average","values":[10,20,30,40,50]}'

# Chained operations
curl http://localhost:3002/chain

# Database operations
curl http://localhost:3002/database
```

## What to Look For in SigNoz

### Traces
1. Go to **Services** → Click on `python-test-app` or `typescript-test-app`
2. Click on any trace to see the flame graph
3. Notice:
   - Parent-child span relationships
   - Span attributes (like `user.name`, `operation.type`)
   - Error spans marked in red
   - Timing information for each operation

### Logs
1. Go to **Logs** tab
2. Filter by `service.name` = `python-test-app` or `typescript-test-app`
3. Notice:
   - JSON structured logs with timestamp, level, message
   - `trace_id` and `span_id` fields for correlation
   - Custom attributes in structured format
4. Click "View Trace" on any log entry to jump to the related trace

### Log-Trace Correlation
1. Find a trace in the **Traces** view
2. Click on it to open the trace details
3. Look for a "Logs" tab or "View Related Logs" button
4. See all logs that occurred during that trace execution

### Service Map
1. Go to **Service Map**
2. See how services are connected
3. Click on services to see metrics and traces

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Python App     │         │ TypeScript App  │
│  (Flask)        │         │  (Express)      │
└────────┬────────┘         └────────┬────────┘
         │                           │
         │ stdout/stderr (JSON)      │ stdout/stderr (JSON)
         │                           │
         └────────┬──────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │   Fluent Bit   │
         │ (Log Collector)│
         └────────┬────────┘
                  │
                  │ OTLP HTTP (logs)
                  │
                  ▼
         ┌────────────────────┐
         │ SigNoz OTLP       │◄─── OTLP gRPC (traces)
         │ Collector          │     from both apps
         │ (localhost:4320)│
         └────────────────────┘
```

## Troubleshooting

### Check if services are running
```bash
docker-compose ps
```

### View application logs
```bash
# Python app logs (should see JSON formatted logs)
docker logs test-python-app

# TypeScript app logs
docker logs test-typescript-app

# Fluent Bit logs (should show it's collecting and sending)
docker logs test-fluent-bit
```

### Test connectivity to SigNoz
```bash
# From Python container
docker exec test-python-app curl -v http://localhost:4319

# From TypeScript container
docker exec test-typescript-app curl -v http://localhost:4319
```

### Verify log format
```bash
# Should see JSON with timestamp, level, message, trace_id, etc.
docker logs test-python-app 2>&1 | head -5 | jq .
docker logs test-typescript-app 2>&1 | head -5 | jq .
```

### Check Fluent Bit is collecting logs
```bash
# Should see messages about connecting to SigNoz and sending logs
docker logs test-fluent-bit | tail -20
```

## Cleanup

Stop and remove all test containers:
```bash
docker-compose down -v
```

Remove built images:
```bash
docker-compose down -v --rmi all
```

## Key Features Demonstrated

### Python App
- ✅ OpenTelemetry tracing with manual span creation
- ✅ Structured JSON logging with structlog
- ✅ Automatic trace-log correlation
- ✅ Error handling and error spans
- ✅ Span attributes and custom metadata
- ✅ Multiple span levels (parent-child relationships)

### TypeScript App
- ✅ OpenTelemetry tracing with context propagation
- ✅ Pino logger for structured JSON logs
- ✅ Async operation tracing
- ✅ Database operation simulation
- ✅ Error tracking and status codes
- ✅ Automatic Express route instrumentation

### Fluent Bit
- ✅ Docker log collection from all containers
- ✅ JSON log parsing
- ✅ Metadata enrichment (container name, deployment environment)
- ✅ OTLP HTTP export to SigNoz
- ✅ Configurable filtering and transformation

## Customization

### Change Platform Identifier
Edit `docker-compose.yml` and change the `DEPLOYMENT_ENVIRONMENT` variable:
```yaml
environment:
  - SIGNOZ_HOST=localhost
  - SIGNOZ_PORT=4320
  - DEPLOYMENT_ENVIRONMENT=my-custom-platform  # Change this
```

### Add More Services
Copy one of the app directories and modify:
1. Change service name in the code
2. Add to `docker-compose.yml`
3. Update load generator to test new endpoints

### Adjust Log Levels
Set environment variables:
```yaml
environment:
  - LOG_LEVEL=debug  # or info, warn, error
```
