#!/bin/bash

# Quick reference for instrumenting applications with OpenTelemetry
# to send data to the local OTel Collector

cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                   INSTRUMENTATION QUICK REFERENCE                         ║
║                   (Sending to local OTel Collector)                        ║
╚════════════════════════════════════════════════════════════════════════════╝

OTel Collector is listening on:
   • gRPC:  localhost:4319
   • HTTP:  localhost:4320
   • Health Check: http://localhost:13133

SigNoz Query Service API
   • Base URL: http://localhost:8900
   • Health Check: http://localhost:8900/api/v1/health

═══════════════════════════════════════════════════════════════════════════════
NODE.JS / TYPESCRIPT (Auto-instrumentation)
═══════════════════════════════════════════════════════════════════════════════

1. Install packages:
   npm install @opentelemetry/api @opentelemetry/auto-instrumentations-node

2. Set environment variables:
   export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4319"
   export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
   export OTEL_SERVICE_NAME="my-node-app"
   export OTEL_NODE_RESOURCE_DETECTORS="env,host,os"

3. Run with auto-instrumentation:
   node --require @opentelemetry/auto-instrumentations-node/register app.js

Or with npm script in package.json:
   {
     "scripts": {
       "start": "node --require @opentelemetry/auto-instrumentations-node/register index.js"
     }
   }

4. In Docker, add to docker-compose.yml:
   environment:
     - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
     - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
     - OTEL_SERVICE_NAME=my-service
     - NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register
   depends_on:
     - otel-collector


═══════════════════════════════════════════════════════════════════════════════
PYTHON (Auto-instrumentation)
═══════════════════════════════════════════════════════════════════════════════

1. Install packages:
   pip install opentelemetry-distro opentelemetry-exporter-otlp

2. Bootstrap instrumentation:
   opentelemetry-bootstrap --action=install

3. Set environment variables:
   export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4319"
   export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
   export OTEL_SERVICE_NAME="my-python-app"

4. Run with instrumentation:
   opentelemetry-instrument python app.py

Or with FastAPI/Flask:
   opentelemetry-instrument uvicorn main:app --host localhost --port 8000
   opentelemetry-instrument flask run

5. In Docker, add to docker-compose.yml or Dockerfile:
   environment:
     - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
     - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
     - OTEL_SERVICE_NAME=my-service
   
   Or in entrypoint:
   ENTRYPOINT ["opentelemetry-instrument", "python", "app.py"]


═══════════════════════════════════════════════════════════════════════════════
DOCKER CONTAINERS (Infrastructure Metrics)
═══════════════════════════════════════════════════════════════════════════════

For Docker containers, the OTel Collector automatically collects:
  ✓ Container metrics (CPU, memory, disk, network)
  ✓ Host metrics
  ✓ Container logs

No additional setup needed for infrastructure monitoring!

To send application traces from your containerized app:
   Just set the environment variable in docker-compose.yml:
   
   services:
     my-app:
       environment:
         - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
         - OTEL_SERVICE_NAME=my-app


═══════════════════════════════════════════════════════════════════════════════
VERIFICATION
═══════════════════════════════════════════════════════════════════════════════

Check if your app is sending data:

1. Health check OTel Collector:
   curl http://localhost:13133

2. Check SigNoz API health:
   curl http://localhost:8900/api/v1/health

3. Check logs:
   ./signoz-stack.sh logs
   ./signoz-stack.sh logs-otel
   ./signoz-stack.sh health

4. Send test telemetry (requires Go):
   ./signoz-stack.sh test-telemetry


═══════════════════════════════════════════════════════════════════════════════
ACCESSING SIGNOZ APIS
═══════════════════════════════════════════════════════════════════════════════

🔌 SigNoz Query Service API
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Base URL: http://localhost:8900

Common Endpoints:

1. Health Check
   GET http://localhost:8900/api/v1/health
   
   Example:
   curl http://localhost:8900/api/v1/health

2. List Services
   GET http://localhost:8900/api/v1/services
   
   Example:
   curl http://localhost:8900/api/v1/services

3. Query Traces
   POST http://localhost:8900/api/v1/traces
   
   Example:
   curl -X POST http://localhost:8900/api/v1/traces \
     -H "Content-Type: application/json" \
     -d '{
       "start": "2024-01-01T00:00:00Z",
       "end": "2024-01-02T00:00:00Z",
       "limit": 10
     }'

4. Get Trace by ID
   GET http://localhost:8900/api/v1/traces/{traceId}
   
   Example:
   curl http://localhost:8900/api/v1/traces/abc123def456

5. Query Metrics
   POST http://localhost:8900/api/v1/query_range
   
   Example:
   curl -X POST http://localhost:8900/api/v1/query_range \
     -H "Content-Type: application/json" \
     -d '{
       "start": 1640995200,
       "end": 1641081600,
       "step": 60,
       "query": "rate(http_requests_total[5m])"
     }'

6. Get Service Metrics
   GET http://localhost:8900/api/v1/service/{serviceName}/metrics
   
   Example:
   curl http://localhost:8900/api/v1/service/my-node-app/metrics


📡 Additional Components
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ClickHouse (Database)
  • Native Protocol: localhost:9000
  • HTTP Interface: http://localhost:8123
  • Use for direct database queries (advanced users)
  
  Example:
  curl "http://localhost:8123?query=SELECT%20count()%20FROM%20signoz_traces.signoz_index_v2"

Zookeeper (Coordination)
  • Metrics Port: localhost:9141
  • Used internally for ClickHouse coordination


🔐 Authentication & Security Notes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• Default deployment has NO authentication (suitable for local development)
• For production environments:
  - Configure authentication in docker-compose.yml
  - Set up API keys for programmatic access
  - Use reverse proxy (nginx/traefik) with SSL/TLS
  - Restrict network access to trusted IPs


📝 API Response Format
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All API responses are in JSON format:

Success Response:
{
  "status": "success",
  "data": { ... }
}

Error Response:
{
  "status": "error",
  "error": "Error message here"
}


💡 API Usage Tips
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• Use the UI to build queries, then inspect network requests to get API format
• For large-scale querying, use the Query Service API directly
• Timestamps can be in Unix epoch or ISO 8601 format
• Rate limiting is not enabled by default in local deployments
• API documentation: Check SigNoz docs at https://signoz.io/docs/


═══════════════════════════════════════════════════════════════════════════════
ENVIRONMENT VARIABLES REFERENCE
═══════════════════════════════════════════════════════════════════════════════

OTEL_EXPORTER_OTLP_ENDPOINT
  └─ Where to send data
     Host: http://localhost:4319
     Docker: http://otel-collector:4317

OTEL_EXPORTER_OTLP_PROTOCOL
  └─ Protocol to use
     grpc (default)
     http/protobuf

OTEL_SERVICE_NAME
  └─ Name of your service
     Used for filtering and identification

OTEL_RESOURCE_ATTRIBUTES
  └─ Additional metadata (optional)
     Example: service.version=1.0.0,environment=dev

OTEL_TRACES_EXPORTER
  └─ Trace exporter (optional)
     otlp (default)

OTEL_METRICS_EXPORTER
  └─ Metrics exporter (optional)
     otlp (default)

OTEL_LOGS_EXPORTER
  └─ Logs exporter (optional)
     otlp (default)


═══════════════════════════════════════════════════════════════════════════════
COMMON ISSUES & SOLUTIONS
═══════════════════════════════════════════════════════════════════════════════

Issue: "Connection refused" when sending to localhost:4319
Solution: 
  • Make sure OTel Collector is running: ./signoz-stack.sh status
  • If in Docker, use http://otel-collector:4317 (not localhost:4319)
  • Check health: ./signoz-stack.sh health

Issue: Data not appearing in SigNoz
Solution:
  • Wait a few seconds for data to be processed
  • Check OTel Collector logs: ./signoz-stack.sh logs-otel
  • Verify service name is set correctly
  • Check that your app is actually generating requests/spans

Issue: OTel Collector consuming too much memory
Solution:
  • Already configured with memory limits in config.yaml
  • If needed, increase limits in signoz-stack/otel-collector/config.yaml
  • Adjust memory_limiter settings

Issue: Python: "ModuleNotFoundError: No module named 'opentelemetry'"
Solution:
  • Make sure you ran: opentelemetry-bootstrap --action=install
  • Install in a virtual environment if needed


═══════════════════════════════════════════════════════════════════════════════
SAMPLING (Advanced)
═══════════════════════════════════════════════════════════════════════════════

By default, all traces are sent. To sample traces (for high-traffic apps):

Environment variable approach:
  export OTEL_TRACES_SAMPLER=parentbased_traceidratio
  export OTEL_TRACES_SAMPLER_ARG=0.1  # Sample 10% of traces

Or configure in OTel Collector config.yaml for centralized control.


═══════════════════════════════════════════════════════════════════════════════
NEXT STEPS
═══════════════════════════════════════════════════════════════════════════════

1. Start the stack:
   ./signoz-stack.sh start

2. Choose your language above and instrument your app

3. Set the environment variables and run your app

4. Check SigNoz API: curl http://localhost:8900/api/v1/health

5. Query your traces and metrics using the API

Happy observability! 🎉

═══════════════════════════════════════════════════════════════════════════════
EOF

