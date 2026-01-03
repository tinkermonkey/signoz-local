#!/bin/bash

# SigNoz + OpenTelemetry Collector Setup Script
# This script sets up SigNoz and an OpenTelemetry Collector that acts as a central
# ingestion point for all your instrumented applications.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNOZ_DIR="${SCRIPT_DIR}/signoz-stack"

echo "=========================================="
echo "SigNoz + OTel Collector Setup"
echo "=========================================="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$SIGNOZ_DIR"
mkdir -p "$SIGNOZ_DIR/otel-collector"
mkdir -p "$SIGNOZ_DIR/logs"

# Create .env file if it doesn't exist
if [ ! -f "$SIGNOZ_DIR/.env" ]; then
    echo "📝 Creating .env file..."
    cat > "$SIGNOZ_DIR/.env" << 'EOF'
# SigNoz Configuration
SIGNOZ_PORT=3301

# OpenTelemetry Collector Configuration
# These are used if you want to export data to a cloud SigNoz instance
# Leave blank if using self-hosted SigNoz only
SIGNOZ_INGESTION_KEY=
SIGNOZ_CLOUD_ENDPOINT=ingest.us.signoz.cloud:443

# OTel Collector Ports
OTEL_COLLECTOR_GRPC_PORT=4317
OTEL_COLLECTOR_HTTP_PORT=4318
OTEL_COLLECTOR_HEALTH_PORT=13133

# Memory limits for OTel Collector (in MiB)
OTEL_MEMORY_LIMIT=512
OTEL_MEMORY_SPIKE_LIMIT=128
EOF
    echo "✅ Created .env file at $SIGNOZ_DIR/.env"
else
    echo "✅ .env file already exists at $SIGNOZ_DIR/.env"
fi

# Create OTel Collector config
echo "⚙️  Creating OpenTelemetry Collector configuration..."
cat > "$SIGNOZ_DIR/otel-collector/config.yaml" << 'EOF'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  
  # Collect host metrics from the container
  hostmetrics:
    collection_interval: 60s
    scrapers:
      cpu: {}
      disk: {}
      filesystem: {}
      load: {}
      memory: {}
      network: {}
      paging: {}
      processes: {}

processors:
  # Batch processor for better throughput
  batch:
    send_batch_size: 1000
    timeout: 10s
  
  # Prevent excessive memory usage
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  
  # Add resource detection (hostname, OS info, etc)
  resourcedetection:
    detectors: [env, system]
    timeout: 2s
    system:
      hostname_sources: [os]

exporters:
  # Export to self-hosted SigNoz (default)
  otlp:
    endpoint: "signoz-otel-collector:4317"
    tls:
      insecure: true
  
  # Uncomment below to export to SigNoz Cloud instead
  # otlp_cloud:
  #   endpoint: "${SIGNOZ_CLOUD_ENDPOINT}"
  #   headers:
  #     "signoz-ingestion-key": "${SIGNOZ_INGESTION_KEY}"
  #   tls:
  #     insecure: false

  # For debugging - logs all telemetry to console
  # debug: {}

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777
  zpages:
    endpoint: 0.0.0.0:55679

service:
  extensions: [health_check, pprof, zpages]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resourcedetection]
      exporters: [otlp]
    
    metrics:
      receivers: [otlp, hostmetrics]
      processors: [memory_limiter, batch, resourcedetection]
      exporters: [otlp]
    
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resourcedetection]
      exporters: [otlp]
EOF

echo "✅ Created OTel Collector config at $SIGNOZ_DIR/otel-collector/config.yaml"

# Create docker-compose.yml
echo "🐳 Creating Docker Compose configuration..."
cat > "$SIGNOZ_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # OpenTelemetry Collector - ingestion point for all apps
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.130.1
    container_name: otel-collector
    restart: unless-stopped
    command: ["--config=/etc/otelcol-contrib/config.yaml"]
    volumes:
      - ./otel-collector/config.yaml:/etc/otelcol-contrib/config.yaml
    ports:
      - "${OTEL_COLLECTOR_GRPC_PORT}:4317"    # OTLP gRPC
      - "${OTEL_COLLECTOR_HTTP_PORT}:4318"    # OTLP HTTP
      - "${OTEL_COLLECTOR_HEALTH_PORT}:13133" # Health check
    environment:
      - SIGNOZ_INGESTION_KEY=${SIGNOZ_INGESTION_KEY}
      - SIGNOZ_CLOUD_ENDPOINT=${SIGNOZ_CLOUD_ENDPOINT}
    networks:
      - signoz-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:13133"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    depends_on:
      - signoz-otel-collector

  # SigNoz Backend - click house setup
  clickhouse:
    image: clickhouse/clickhouse-server:23.10.1.1480
    container_name: clickhouse
    hostname: clickhouse
    ports:
      - "9000:9000"
      - "8123:8123"
      - "9181:9181"
    environment:
      - CLICKHOUSE_DB=signoz
      - CLICKHOUSE_USER=default
      - CLICKHOUSE_PASSWORD=
      - CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1
    volumes:
      - clickhouse-data:/var/lib/clickhouse/
      - ./clickhouse/config.xml:/etc/clickhouse-server/config.xml
      - ./clickhouse/users.xml:/etc/clickhouse-server/users.xml
    networks:
      - signoz-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123/ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  # SigNoz OTel Collector (backend)
  signoz-otel-collector:
    image: signoz/signoz-otel-collector:0.88.7
    container_name: signoz-otel-collector
    command:
      - "--config=/etc/otel-collector-config.yaml"
    volumes:
      - ./signoz-otel-collector-config.yaml:/etc/otel-collector-config.yaml
    environment:
      - GOGC=80
      - GOMEMLIMIT=512MiB
    ports:
      - "4317:4317"     # OTLP gRPC
      - "4318:4318"     # OTLP HTTP
    networks:
      - signoz-network
    depends_on:
      - clickhouse
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:13133"]
      interval: 30s
      timeout: 10s
      retries: 3

  # SigNoz Query Service
  query-service:
    image: signoz/signoz-query-service:0.88.7
    container_name: query-service
    command:
      - "-config=/etc/config/config.yaml"
    volumes:
      - ./query-service-config.yaml:/etc/config/config.yaml
    environment:
      - ClickHouseUrl=tcp://default:@clickhouse:9000
      - STORAGE=clickhouse
      - GODEBUG=madvdontneed=1
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4317
    ports:
      - "8080:8080"
    networks:
      - signoz-network
    depends_on:
      - clickhouse
      - signoz-otel-collector

  # SigNoz Frontend
  frontend:
    image: signoz/signoz-frontend:0.88.7
    container_name: signoz-frontend
    restart: unless-stopped
    ports:
      - "${SIGNOZ_PORT}:3301"
    environment:
      - BACKEND_API_URL=http://localhost:8080
      - DISABLE_ANALYTICS=true
    networks:
      - signoz-network
    depends_on:
      - query-service

networks:
  signoz-network:
    driver: bridge

volumes:
  clickhouse-data:
EOF

echo "✅ Created Docker Compose config at $SIGNOZ_DIR/docker-compose.yml"

# Create basic SigNoz configs
echo "🔧 Creating SigNoz configuration files..."

# Create signoz-otel-collector-config.yaml
cat > "$SIGNOZ_DIR/signoz-otel-collector-config.yaml" << 'EOF'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    send_batch_size: 1000
    timeout: 10s
  memory_limiter:
    check_interval: 1s
    limit_mib: 512

exporters:
  clickhouse:
    dsn: "tcp://default:@clickhouse:9000"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [clickhouse]
    metrics:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [clickhouse]
    logs:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [clickhouse]
EOF

# Create query-service-config.yaml
cat > "$SIGNOZ_DIR/query-service-config.yaml" << 'EOF'
auth:
  enabled: false
logLevel: info
queryTimeout: 600
EOF

# Create minimal clickhouse configs
mkdir -p "$SIGNOZ_DIR/clickhouse"

cat > "$SIGNOZ_DIR/clickhouse/config.xml" << 'EOF'
<?xml version="1.0"?>
<yandex>
    <logger>
        <level>warning</level>
        <console>true</console>
    </logger>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <interserver_http_port>9009</interserver_http_port>
    <listen_host>::</listen_host>
</yandex>
EOF

cat > "$SIGNOZ_DIR/clickhouse/users.xml" << 'EOF'
<?xml version="1.0"?>
<yandex>
    <users>
        <default>
            <password></password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </default>
    </users>
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</yandex>
EOF

echo "✅ Created SigNoz configuration files"

# Create startup instructions
echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Next steps:"
echo ""
echo "1. Review configuration (optional):"
echo "   cd $SIGNOZ_DIR"
echo "   cat .env"
echo ""
echo "2. Start the stack:"
echo "   cd $SIGNOZ_DIR"
echo "   docker-compose up -d"
echo ""
echo "3. Verify everything is running:"
echo "   docker-compose ps"
echo ""
echo "4. Access SigNoz:"
echo "   http://localhost:3301"
echo ""
echo "5. Configure your applications to send data to:"
echo "   - gRPC: localhost:4317"
echo "   - HTTP: localhost:4318"
echo ""
echo "📝 Example environment variables for your apps:"
echo "   export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317"
echo "   export OTEL_EXPORTER_OTLP_PROTOCOL=grpc"
echo "   export OTEL_RESOURCE_ATTRIBUTES=service.name=my-app"
echo ""
echo "🔍 Monitor OTel Collector health:"
echo "   curl http://localhost:13133"
echo ""
echo "📊 View logs:"
echo "   cd $SIGNOZ_DIR"
echo "   docker-compose logs -f"
echo ""
echo "�� Stop the stack:"
echo "   cd $SIGNOZ_DIR"
echo "   docker-compose down"
echo ""
echo "📂 Configuration files are in: $SIGNOZ_DIR"
echo "=========================================="
