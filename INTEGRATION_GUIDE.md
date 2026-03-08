# SigNoz Integration Guide

## Overview

This guide explains how to send logs and traces from your applications to the SigNoz observability platform.

## Connection Details

### OTLP Endpoints

Your applications should send telemetry data to:

- **gRPC Endpoint**: `http://localhost:4317` (or `http://signoz-host:4317` from remote hosts)
- **HTTP Endpoint**: `http://localhost:4318` (or `http://signoz-host:4318` from remote hosts)
- **SigNoz UI**: `http://localhost:8900` (or `http://signoz-host:8900` from remote hosts)

**Note:** Replace `localhost` with your SigNoz server's hostname or IP address when connecting from remote applications.

### Protocol Support

- **Traces**: OTLP (OpenTelemetry Protocol)
- **Logs**: OTLP
- **Metrics**: OTLP

## Service Identification Strategy

To properly organize telemetry data across multiple platforms and services, use the following resource attributes:

### Required Attributes

| Attribute | Purpose | Example |
|-----------|---------|---------|
| `service.name` | Identifies the specific service/container | `api-gateway`, `user-service`, `payment-processor` |
| `deployment.environment` | Identifies the platform/deployment | `production-cluster-a`, `staging-env`, `dev-platform-1` |
| `service.version` | Version of the service | `1.2.3`, `v2.0.0` |
| `service.namespace` | Logical grouping of services | `ecommerce`, `analytics`, `auth-system` |

### Recommended Additional Attributes

| Attribute | Purpose | Example |
|-----------|---------|---------|
| `host.name` | Container or host identifier | `api-container-1`, `worker-pod-xyz` |
| `container.name` | Docker container name | `myapp_web_1` |
| `k8s.cluster.name` | Kubernetes cluster (if applicable) | `production-k8s` |
| `team` | Owning team | `backend-team`, `frontend-team` |

## Integration Examples

### Docker Compose Services

Add the OpenTelemetry collector endpoint to your service environment variables:

```yaml
version: '3.8'

services:
  my-api:
    image: my-api:latest
    environment:
      # OTLP Configuration
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
      - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
      
      # Service Identification
      - OTEL_SERVICE_NAME=my-api
      - OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production-platform-1,service.namespace=ecommerce,service.version=1.0.0,team=backend-team
```

### Python Application

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource

# Define resource attributes
resource = Resource(attributes={
    "service.name": "payment-service",
    "deployment.environment": "production-platform-1",
    "service.namespace": "payment-system",
    "service.version": "2.1.0",
    "team": "payments-team"
})

# Configure tracer
trace.set_tracer_provider(TracerProvider(resource=resource))
otlp_exporter = OTLPSpanExporter(
    endpoint="http://localhost:4317",
    insecure=True
)
# BatchSpanProcessor exports traces in batches for efficiency
# Default: 30s interval, 512 max batch size
# For test/demo environments, consider: schedule_delay_millis=5000, max_export_batch_size=50
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)
```

### Node.js Application

```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: 'user-service',
  [SemanticResourceAttributes.SERVICE_VERSION]: '1.5.2',
  [SemanticResourceAttributes.SERVICE_NAMESPACE]: 'user-management',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: 'staging-platform-2',
  'team': 'identity-team'
});

const provider = new NodeTracerProvider({ resource });

const exporter = new OTLPTraceExporter({
  url: 'http://localhost:4317',
});

// BatchSpanProcessor exports traces in batches for efficiency
// Default: 30s interval, 512 max batch size
// For test/demo: { scheduledDelayMillis: 5000, maxExportBatchSize: 50 }
provider.addSpanProcessor(
  new BatchSpanProcessor(exporter)
);

provider.register();
```

### Java/Spring Boot Application

```yaml
# application.yml
management:
  otlp:
    tracing:
      endpoint: http://localhost:4317
  tracing:
    sampling:
      probability: 1.0

otel:
  service:
    name: order-service
  resource:
    attributes:
      deployment.environment: production-platform-1
      service.namespace: order-processing
      service.version: 3.2.1
      team: orders-team
```

### Go Application

```go
package main

import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
)

func initTracer() {
    res, _ := resource.New(context.Background(),
        resource.WithAttributes(
            semconv.ServiceNameKey.String("inventory-service"),
            semconv.ServiceVersionKey.String("1.0.0"),
            semconv.ServiceNamespaceKey.String("inventory"),
            semconv.DeploymentEnvironmentKey.String("production-platform-1"),
            attribute.String("team", "inventory-team"),
        ),
    )

    exporter, _ := otlptracegrpc.New(
        context.Background(),
        otlptracegrpc.WithEndpoint("localhost:4317"),
        otlptracegrpc.WithInsecure(),
    )

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
    )
    
    otel.SetTracerProvider(tp)
}
```

## Logging Integration

### Recommended Architecture: Direct OTLP Log Export

**Best Practice (Updated):** Applications send logs directly to SigNoz via OTLP using the OpenTelemetry SDK.

**Why this approach?**
- ✅ Works in non-admin Docker environments (no filesystem access needed)
- ✅ Native OpenTelemetry integration with automatic trace correlation
- ✅ Automatic inclusion of resource attributes (service.name, deployment.environment, etc.)
- ✅ Production-ready and officially supported by OpenTelemetry
- ✅ Simpler architecture - no additional log collector process needed
- ✅ Better performance with batching and retry logic built-in

**Alternative:** For legacy systems or when application changes aren't feasible, use Fluent Bit to collect Docker logs (requires filesystem access).

### Standard Log Format (Required for All Projects)

All applications must emit logs in this JSON format:

```json
{
  "timestamp": "2025-12-30T14:15:22.123Z",
  "level": "info",
  "message": "User authentication successful",
  "service.name": "api-gateway",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "http.method": "POST",
  "http.target": "/api/login",
  "http.status_code": 200,
  "attributes": {
    "user_id": "12345",
    "duration_ms": 145
  }
}
```

**Required Fields:**
- `timestamp` - ISO 8601 format with timezone
- `level` - One of: `debug`, `info`, `warn`, `error`, `fatal`
- `message` - Human-readable log message
- `service.name` - Name of the service emitting the log

**Trace Correlation Fields (required when in request context):**
- `trace_id` - OpenTelemetry trace ID (32 hex characters)
- `span_id` - OpenTelemetry span ID (16 hex characters)

**HTTP Metadata (required for API requests):**
- `http.method` - HTTP method (GET, POST, PUT, DELETE, etc.)
- `http.target` - Request path/URL
- `http.status_code` - HTTP response status code (include in response logs)
- `http.route` - Route pattern (e.g., `/api/users/:id`)
- `http.remote_addr` - Client IP address (optional)

**Optional:**
- `attributes` - Object containing any additional structured data

### Application Code Examples

#### Python (Flask with OTLP Logging)

```python
import structlog
import logging
from flask import Flask, request
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.resources import Resource

# Configure resource attributes
resource = Resource(attributes={
    "service.name": "payment-service",
    "deployment.environment": "production-platform-1",
    "service.namespace": "payment-system",
    "service.version": "2.1.0",
    "team": "payments-team"
})

# Setup tracing
trace.set_tracer_provider(TracerProvider(resource=resource))
otlp_exporter = OTLPSpanExporter(
    endpoint="http://localhost:4317",
    insecure=True
)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)

# Setup logging with OTLP
logger_provider = LoggerProvider(resource=resource)
log_exporter = OTLPLogExporter(
    endpoint="http://localhost:4318/v1/logs",
    headers={}
)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter))

# Attach OTLP handler to root logger
handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)

# Configure structlog for console output
structlog.configure(
    processors=[
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
)

logger = structlog.get_logger()

app = Flask(__name__)

# Middleware to log all requests with HTTP metadata
@app.before_request
def log_request_info():
    span = trace.get_current_span()
    span_context = span.get_span_context()
    
    log_data = {
        "message": "Request received",
        "http.method": request.method,
        "http.target": request.path,
        "http.remote_addr": request.remote_addr
    }
    
    if span_context.is_valid:
        log_data["trace_id"] = format(span_context.trace_id, '032x')
        log_data["span_id"] = format(span_context.span_id, '016x')
    
    # Log to console
    logger.info(**log_data)
    # Send to OTLP
    logging.info("Request received", extra=log_data)

@app.after_request
def log_response_info(response):
    span = trace.get_current_span()
    span_context = span.get_span_context()
    
    log_data = {
        "message": "Request completed",
        "http.method": request.method,
        "http.target": request.path,
        "http.status_code": response.status_code
    }
    
    if span_context.is_valid:
        log_data["trace_id"] = format(span_context.trace_id, '032x')
        log_data["span_id"] = format(span_context.span_id, '016x')
    
    logger.info(**log_data)
    logging.info("Request completed", extra=log_data)
    return response
```

**Key Points:**
- Logs sent to both console (for debugging) and OTLP (for SigNoz)
- Automatic trace correlation via trace_id and span_id
- HTTP metadata captured in middleware for all requests
- Resource attributes automatically attached to all logs

#### Node.js (Express with OTLP Logging)

```javascript
const express = require('express');
const pino = require('pino');
const { trace } = require('@opentelemetry/api');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { LoggerProvider, BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

// Configure resource
const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: 'user-service',
  [SemanticResourceAttributes.SERVICE_VERSION]: '1.5.2',
  [SemanticResourceAttributes.SERVICE_NAMESPACE]: 'user-management',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: 'production-platform-1',
  'team': 'identity-team'
});

// Setup tracing
const provider = new NodeTracerProvider({ resource });
const traceExporter = new OTLPTraceExporter({
  url: 'http://localhost:4317',
});
provider.addSpanProcessor(new BatchSpanProcessor(traceExporter));
provider.register();

// Setup logging with OTLP
const loggerProvider = new LoggerProvider({ resource });
const logExporter = new OTLPLogExporter({
  url: 'http://localhost:4318/v1/logs',
});
loggerProvider.addLogRecordProcessor(new BatchLogRecordProcessor(logExporter));
const otelLogger = loggerProvider.getLogger('user-service', '1.0.0');

// Setup pino for console logging
const logger = pino({
  formatters: { level: (label) => ({ level: label }) },
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
  base: { 'service.name': 'user-service' }
});

// Helper to log with trace context and HTTP metadata
function logWithTrace(level, message, attributes = {}) {
  const span = trace.getActiveSpan();
  const spanContext = span?.spanContext();
  
  const logData = {
    message,
    'service.name': 'user-service',
    attributes
  };
  
  if (spanContext) {
    logData.trace_id = spanContext.traceId;
    logData.span_id = spanContext.spanId;
  }
  
  // Log to console
  logger[level](logData);
  
  // Send to OTLP
  otelLogger.emit({
    severityText: level.toUpperCase(),
    body: message,
    attributes: {
      ...attributes,
      ...(spanContext && {
        'trace_id': spanContext.traceId,
        'span_id': spanContext.spanId
      })
    }
  });
}

const app = express();
app.use(express.json());

// Middleware to log all requests with HTTP metadata
app.use((req, res, next) => {
  logWithTrace('info', 'Request received', {
    'http.method': req.method,
    'http.target': req.path,
    'http.remote_addr': req.ip
  });
  
  // Capture response status code
  const originalSend = res.send;
  res.send = function(data) {
    logWithTrace('info', 'Request completed', {
      'http.method': req.method,
      'http.target': req.path,
      'http.status_code': res.statusCode
    });
    return originalSend.call(this, data);
  };
  
  next();
});

// Your routes...
app.get('/users/:id', (req, res) => {
  logWithTrace('info', 'Fetching user', { user_id: req.params.id });
  // ... handle request
});
```

**Key Points:**
- Logs sent to both console (pino) and OTLP (SigNoz)
- Middleware captures HTTP metadata for all requests
- Automatic trace correlation via trace_id and span_id
- Resource attributes attached to all telemetry

#### Go (using zap)

```go
package main

import (
    "go.uber.org/zap"
    "go.uber.org/zap/zapcore"
    "go.opentelemetry.io/otel/trace"
)

func initLogger() *zap.Logger {
    config := zap.NewProductionConfig()
    config.EncoderConfig.TimeKey = "timestamp"
    config.EncoderConfig.MessageKey = "message"
    config.EncoderConfig.LevelKey = "level"
    
    logger, _ := config.Build()
    return logger
}

func logWithTrace(logger *zap.Logger, span trace.Span, msg string, fields ...zap.Field) {
    spanContext := span.SpanContext()
    
    allFields := append(fields,
        zap.String("trace_id", spanContext.TraceID().String()),
        zap.String("span_id", spanContext.SpanID().String()),
        zap.String("service.name", "inventory-service"),
    )
    
    logger.Info(msg, allFields...)
}
```

#### Java (using Logback with Logstash encoder)

```xml
<!-- logback.xml -->
<configuration>
    <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <customFields>{"service.name":"payment-service"}</customFields>
            <includeContext>false</includeContext>
            <fieldNames>
                <timestamp>timestamp</timestamp>
                <message>message</message>
                <logger>[ignore]</logger>
                <thread>[ignore]</thread>
            </fieldNames>
        </encoder>
    </appender>
    
    <root level="info">
        <appender-ref ref="STDOUT" />
    </root>
</configuration>
```

```java
// With OpenTelemetry trace context
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import io.opentelemetry.api.trace.Span;
import net.logstash.logback.argument.StructuredArguments;

Logger logger = LoggerFactory.getLogger(PaymentService.class);

Span span = Span.current();
logger.info("Payment processed",
    StructuredArguments.keyValue("trace_id", span.getSpanContext().getTraceId()),
    StructuredArguments.keyValue("span_id", span.getSpanContext().getSpanId()),
    StructuredArguments.entries(Map.of(
        "payment_id", "pay_123",
        "amount", 99.99
    ))
);
```

### Fluent Bit Setup (Alternative for Legacy Systems)

**Note:** Use Fluent Bit only if you cannot modify applications to use OTLP log export directly. Requires filesystem access to Docker logs, which may not work in non-admin Docker environments.

Deploy Fluent Bit as a DaemonSet or sidecar to collect Docker logs:

```yaml
# docker-compose.yml - Add to your platform
services:
  fluent-bit:
    image: fluent/fluent-bit:2.2
    container_name: fluent-bit-collector
    volumes:
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - your-network
    environment:
      - SIGNOZ_ENDPOINT=http://localhost:4320
      - DEPLOYMENT_ENVIRONMENT=production-platform-1
```

```ini
# fluent-bit.conf
[SERVICE]
    Flush        5
    Daemon       Off
    Log_Level    info
    Parsers_File parsers.conf

# Read from Docker container logs
[INPUT]
    Name              tail
    Path              /var/lib/docker/containers/*/*.log
    Parser            docker
    Tag               docker.*
    Refresh_Interval  5
    Mem_Buf_Limit     50MB
    Skip_Long_Lines   On

# Parse JSON logs
[FILTER]
    Name    parser
    Match   docker.*
    Key_Name log
    Parser  json
    Reserve_Data On

# Add resource attributes
[FILTER]
    Name    modify
    Match   docker.*
    Add     deployment.environment ${DEPLOYMENT_ENVIRONMENT}

# Extract container metadata
[FILTER]
    Name    docker_metadata
    Match   docker.*

# Send to SigNoz via OTLP HTTP
[OUTPUT]
    Name   opentelemetry
    Match  docker.*
    Host   localhost
    Port   4320
    Logs_uri /v1/logs
    Log_response_payload True
    Tls    Off
```

```ini
# parsers.conf
[PARSER]
    Name   docker
    Format json
    Time_Key time
    Time_Format %Y-%m-%dT%H:%M:%S.%LZ
    Time_Keep On

[PARSER]
    Name   json
    Format json
    Time_Key timestamp
    Time_Format %Y-%m-%dT%H:%M:%S.%LZ
    Time_Keep On
```

### Alternative: Fluent Bit Per-Platform

For better isolation, run one Fluent Bit instance per platform:

```yaml
# In your platform's docker-compose.yml
services:
  log-collector:
    image: fluent/fluent-bit:2.2
    volumes:
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
      # Mount your platform's compose project directory
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    environment:
      - SIGNOZ_ENDPOINT=http://localhost:4318
      - DEPLOYMENT_ENVIRONMENT=my-platform-prod
      - SERVICE_NAMESPACE=my-services
    labels:
      # Only collect logs from this platform
      - fluent-bit.platform=my-platform-prod
```

### Development: Human-Readable Logs

For local development, you can make JSON logs more readable:

**Option 1: Use a JSON pretty-printer**
```bash
# Pipe logs through jq
docker logs -f my-container 2>&1 | jq -r '.timestamp + " " + .level + " " + .message'
```

**Option 2: Conditional formatting in code**
```python
import os
import structlog

# Pretty logs in development, JSON in production
if os.getenv('ENVIRONMENT') == 'development':
    structlog.configure(
        processors=[
            structlog.dev.ConsoleRenderer()  # Human-readable
        ]
    )
else:
    structlog.configure(
        processors=[
            structlog.processors.JSONRenderer()  # Production JSON
        ]
    )
```

### Docker Logs Best Practices

1. **Always log to stdout/stderr** - Never write to files inside containers
2. **Use JSON format** - Consistent parsing across all services
3. **Include trace context** - Enable log-trace correlation
4. **Add service identifier** - Include `service.name` in every log
5. **Structured data in attributes** - Don't concatenate values into message strings

### Log Levels

Use these standard levels consistently:

| Level | Usage | Example |
|-------|-------|---------|
| `debug` | Detailed diagnostic info | Variable values, internal state |
| `info` | General operational events | Request received, operation completed |
| `warn` | Warning conditions | Deprecated API used, retry attempted |
| `error` | Error conditions | Request failed, exception caught |
| `fatal` | Critical failure | Service cannot start, data corruption |

### Testing Your Log Setup

1. **Verify JSON format:**
```bash
docker logs my-container 2>&1 | head -1 | jq .
```

2. **Check Fluent Bit is collecting:**
```bash
docker logs fluent-bit-collector
```

3. **Test trace correlation:**
   - Generate a traced request
   - Find the trace in SigNoz
   - Click "View Logs" to see correlated logs

## Platform Organization Examples

### Example 1: E-commerce Platform

**Platform**: `ecommerce-production`

Services:
- `api-gateway` - Entry point
- `user-service` - User management
- `product-service` - Product catalog
- `order-service` - Order processing
- `payment-service` - Payment processing

All services set: `deployment.environment=ecommerce-production`

### Example 2: Analytics Platform

**Platform**: `analytics-staging`

Services:
- `data-ingestion` - Data intake
- `processing-engine` - Data transformation
- `query-service` - API for queries
- `dashboard-backend` - Dashboard data

All services set: `deployment.environment=analytics-staging`

## Viewing Your Data

1. Open SigNoz UI: `http://localhost:8900`
2. Navigate to **Services** to see all services grouped by name
3. Use filters to narrow by:
   - `deployment.environment` - Filter by platform
   - `service.namespace` - Filter by logical grouping
   - `team` - Filter by team ownership

## SigNoz Query API Access

SigNoz provides a comprehensive REST API for querying traces, logs, and metrics programmatically. This is useful for:

- Building custom dashboards
- Automated monitoring and alerting
- Debugging trace ingestion issues
- Integrating with other tools

### Creating an API Key

1. Navigate to the SigNoz UI: http://localhost:8900
2. Go to **Settings** → **API Keys**
3. Click **Create New Key**
4. Provide a descriptive name (e.g., "Production Monitoring", "CI/CD Integration")
5. Copy the generated key - it will only be shown once

### API Endpoints

**Base URL:** `http://localhost:8900`

**Common endpoints:**
- `GET /api/v1/version` - Get SigNoz version (no auth required)
- `POST /api/v3/query_range` - Query metrics, traces, or logs with filters and aggregations
- `POST /api/v1/traces/{traceId}` - Get specific trace by ID
- `GET /api/v1/services` - List all services

### Authentication

Include your API key in the request header:

```bash
curl -H "SIGNOZ-API-KEY: your-api-key-here" \
  http://localhost:8900/api/v3/query_range
```

### Example: Query Recent Traces

```bash
# Get traces from the last hour for a specific service
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: your-api-key-here" \
  -d '{
    "start": "'$(($(date +%s) - 3600))'000000000",
    "end": "'$(date +%s)'000000000",
    "variables": {},
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "table",
      "builderQueries": {
        "A": {
          "dataSource": "traces",
          "queryName": "A",
          "aggregateOperator": "count",
          "aggregateAttribute": {"key": ""},
          "filters": {
            "items": [{
              "key": {"key": "serviceName", "dataType": "string", "type": "tag"},
              "op": "=",
              "value": "your-service-name"
            }]
          },
          "groupBy": [{"key": "serviceName", "dataType": "string", "type": "tag"}],
          "limit": 100
        }
      }
    }
  }'
```

### Example: Check Service Health

```bash
# Count traces by service in the last 15 minutes
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: your-api-key-here" \
  -d '{
    "start": "'$(($(date +%s) - 900))'000000000",
    "end": "'$(date +%s)'000000000",
    "variables": {},
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "table",
      "builderQueries": {
        "A": {
          "dataSource": "traces",
          "queryName": "A",
          "aggregateOperator": "count",
          "aggregateAttribute": {"key": ""},
          "groupBy": [{"key": "serviceName", "dataType": "string", "type": "tag"}]
        }
      }
    }
  }'
```

For complete API documentation, see: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Troubleshooting

### Connection Issues

Test connectivity from your container:

```bash
# Test gRPC endpoint
docker exec -it <container> curl -v http://localhost:4317

# Test HTTP endpoint
docker exec -it <container> curl -v http://localhost:4318/v1/traces
```

### Verify Data is Being Sent

Check your application logs for OTLP exporter output. Most SDKs will log export attempts.

### Common Issues

See the comprehensive [TROUBLESHOOTING.md](TROUBLESHOOTING.md) guide for:
- Verifying trace ingestion
- API-based diagnostics
- Time range and timestamp issues
- Performance tuning

## Network Configuration

If your services are in different Docker networks or machines:

1. Ensure containers can reach `localhost` on ports 4317/4318
2. Add to the same Docker network, or
3. Use the host IP address instead of hostname
4. For external services, ensure firewall rules allow traffic to ports 4317/4318

## Best Practices

### 1. Consistent Naming
- Use kebab-case for service names: `user-service`, not `UserService`
- Use descriptive environment names: `production-customer-portal` instead of just `prod`

### 2. Always Include HTTP Metadata in API Logs
For all HTTP/REST API applications, include these fields in your logs:
- `http.method` - HTTP method (GET, POST, PUT, DELETE, etc.)
- `http.target` - Request path/URL
- `http.status_code` - Response status code (200, 404, 500, etc.)
- `http.route` - Route pattern (e.g., `/api/users/:id`)

This enables:
- Filtering by status codes (e.g., find all 5xx errors)
- Identifying slow endpoints
- Tracking API usage patterns
- Correlating errors with specific routes

### 3. Implement Request Lifecycle Logging
Log at both the start and end of requests:
```python
# Start of request
log("Request received", http.method=GET, http.target=/api/users/123)

# End of request  
log("Request completed", http.method=GET, http.target=/api/users/123, http.status_code=200)
```

This provides:
- Complete request timeline visibility
- Ability to measure request duration
- Better error context

### 4. Dual Logging Strategy
Send logs to both console (stdout) AND OTLP:
- **Console logs**: For debugging, docker logs, local development
- **OTLP logs**: For centralized observability in SigNoz

```python
# Log to console
logger.info(**log_data)

# Send to OTLP
logging.info(message, extra=log_data)
```

### 5. Automatic Trace Correlation
Always include trace_id and span_id in logs when available:
```python
span = trace.get_current_span()
span_context = span.get_span_context()

if span_context.is_valid:
    log_data["trace_id"] = format(span_context.trace_id, '032x')
    log_data["span_id"] = format(span_context.span_id, '016x')
```

This enables:
- Clicking a log in SigNoz to see the full trace
- Viewing all logs for a specific trace
- Understanding the complete request flow

### 6. Resource Attributes Strategy
Always include these resource attributes:
- `service.name` - Required, uniquely identifies the service
- `deployment.environment` - Required, identifies the platform/environment
- `service.version` - Track deployments and correlate with releases
- `service.namespace` - Logical grouping of related services
- `team` - Ownership and routing of alerts

### 7. Version Tracking
Include `service.version` in resource attributes to:
- Track which version is generating errors
- Correlate deployments with performance changes
- Identify when new issues were introduced

### 8. Docker Network Configuration
When running in Docker:
- Connect application containers to the same network as SigNoz
- Use service name (`otel-collector`) instead of hostname in OTLP endpoints
- For production, use: `http://otel-collector:4317` (gRPC) or `http://otel-collector:4318` (HTTP)

### 9. Performance Considerations and Batching
- **Always use batch processors**: `BatchSpanProcessor` and `BatchLogRecordProcessor` (not Simple processors)
- **Default settings** (production): 30-second export interval, 512 max batch size - optimized for efficiency
- **Test/demo settings**: 5-second interval, 50 batch size - optimized for fast feedback
- **Custom tuning**: Adjust based on your traffic patterns:
  - High traffic: Increase batch size (512-2048) to reduce overhead
  - Low traffic: Reduce export interval (5-10s) for faster visibility
  - Memory constrained: Reduce max batch size
- Monitor your application's memory usage with batching enabled

**Example configurations:**

```python
# Python - Production (defaults)
BatchSpanProcessor(exporter)  # 30s, 512 batch

# Python - Test/demo environment
BatchSpanProcessor(
    exporter,
    schedule_delay_millis=5000,    # Export every 5 seconds
    max_export_batch_size=50       # Smaller batches
)
```

```javascript
// Node.js - Production (defaults)
new BatchSpanProcessor(exporter)  // 30s, 512 batch

// Node.js - Test/demo environment
new BatchSpanProcessor(exporter, {
  scheduledDelayMillis: 5000,  // Export every 5 seconds
  maxExportBatchSize: 50        // Smaller batches
})
```

### 10. Error Handling
When logging errors, include:
- Error type/class name
- Error message
- Stack trace (in attributes, not message)
- Context that led to the error
- Set span status to ERROR for trace correlation

Example:
```python
try:
    process_payment(order_id)
except PaymentError as e:
    span.set_status(Status(StatusCode.ERROR))
    span.record_exception(e)
    logger.error("Payment processing failed",
        error_type=type(e).__name__,
        error_message=str(e),
        order_id=order_id,
        trace_id=...,
        span_id=...
    )
```

## Quick Reference

### Required Dependencies

**Python:**
```bash
pip install opentelemetry-api opentelemetry-sdk
pip install opentelemetry-exporter-otlp-proto-grpc
pip install opentelemetry-exporter-otlp-proto-http  # For logs
```

**Node.js:**
```bash
npm install @opentelemetry/api @opentelemetry/sdk-trace-node
npm install @opentelemetry/exporter-trace-otlp-grpc
npm install @opentelemetry/exporter-logs-otlp-http @opentelemetry/sdk-logs
npm install @opentelemetry/resources @opentelemetry/semantic-conventions
```

### Endpoint Summary

| Telemetry Type | Protocol | Endpoint | Port |
|----------------|----------|----------|------|
| Traces | gRPC | `http://localhost:4317` or `http://signoz-otel-collector:4317` | 4317 |
| Traces | HTTP | `http://localhost:4318/v1/traces` or `http://signoz-otel-collector:4318/v1/traces` | 4318 |
| Logs | HTTP | `http://localhost:4318/v1/logs` or `http://signoz-otel-collector:4318/v1/logs` | 4318 |
| Metrics | gRPC/HTTP | Same as traces | 4317-4318 |
| SigNoz UI | HTTP | `http://localhost:8900` | 8900 |

**Note:** Use `localhost` when connecting from host or external services. Use `signoz-otel-collector` when connecting from Docker containers in the same network.

### Required Log Fields Checklist

- [ ] `timestamp` (ISO 8601 format)
- [ ] `level` (debug/info/warn/error/fatal)
- [ ] `message` (human-readable)
- [ ] `service.name` (your service identifier)
- [ ] `trace_id` (when in request context)
- [ ] `span_id` (when in request context)
- [ ] `http.method` (for API requests)
- [ ] `http.target` (for API requests)
- [ ] `http.status_code` (for API responses)

### Example: Complete Minimal Setup (Python)

See [examples/python-app](examples/python-app) for a complete working example with:
- OTLP trace and log export
- HTTP metadata capture
- Request lifecycle logging
- Trace correlation
- Console + OTLP dual logging

### Example: Complete Minimal Setup (TypeScript)

See [examples/typescript-app](examples/typescript-app) for a complete working example with:
- OTLP trace and log export
- Express middleware for HTTP metadata
- Automatic instrumentation
- Trace correlation
- Console + OTLP dual logging

## Support

For issues or questions, contact the platform team or check the SigNoz documentation at https://signoz.io/docs/
