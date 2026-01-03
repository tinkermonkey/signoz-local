#!/bin/bash

# SigNoz Stack Management Script
# Convenient commands to manage the SigNoz + OTel Collector stack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${SCRIPT_DIR}/signoz-stack"

if [ ! -d "$STACK_DIR" ]; then
    echo "❌ Stack directory not found at $STACK_DIR"
    echo "Please run ./setup-signoz.sh first"
    exit 1
fi

command=$1

case $command in
    start)
        echo "🚀 Starting SigNoz + OTel Collector..."
        cd "$STACK_DIR"
        docker-compose up -d
        echo ""
        echo "✅ Stack started. Waiting for services to be ready..."
        sleep 5
        docker-compose ps
        echo ""
        echo "📊 SigNoz UI: http://localhost:3301"
        echo "📡 OTel Collector (gRPC): localhost:4317"
        echo "📡 OTel Collector (HTTP): localhost:4318"
        ;;
    
    stop)
        echo "🛑 Stopping SigNoz + OTel Collector..."
        cd "$STACK_DIR"
        docker-compose down
        echo "✅ Stack stopped"
        ;;
    
    restart)
        echo "🔄 Restarting SigNoz + OTel Collector..."
        cd "$STACK_DIR"
        docker-compose restart
        sleep 3
        docker-compose ps
        ;;
    
    status)
        echo "📋 Stack Status:"
        cd "$STACK_DIR"
        docker-compose ps
        ;;
    
    logs)
        echo "📜 Stack Logs (press Ctrl+C to exit):"
        cd "$STACK_DIR"
        docker-compose logs -f
        ;;
    
    logs-otel)
        echo "�� OTel Collector Logs (press Ctrl+C to exit):"
        cd "$STACK_DIR"
        docker-compose logs -f otel-collector
        ;;
    
    logs-signoz)
        echo "📜 SigNoz Backend Logs (press Ctrl+C to exit):"
        cd "$STACK_DIR"
        docker-compose logs -f signoz-otel-collector query-service frontend
        ;;
    
    health)
        echo "🏥 Checking service health..."
        echo ""
        
        echo "🔹 OTel Collector:"
        if curl -s http://localhost:13133 > /dev/null; then
            echo "   ✅ Healthy"
        else
            echo "   ❌ Unhealthy"
        fi
        
        echo "🔹 ClickHouse:"
        if docker exec clickhouse curl -s http://localhost:8123/ping > /dev/null 2>&1; then
            echo "   ✅ Healthy"
        else
            echo "   ❌ Unhealthy"
        fi
        
        echo "🔹 SigNoz Frontend:"
        if curl -s http://localhost:3301 > /dev/null; then
            echo "   ✅ Healthy"
        else
            echo "   ❌ Unhealthy"
        fi
        
        echo ""
        echo "🔹 Full stack status:"
        cd "$STACK_DIR"
        docker-compose ps
        ;;
    
    test-telemetry)
        echo "📤 Sending test telemetry to OTel Collector..."
        if ! command -v telemetrygen &> /dev/null; then
            echo "Installing telemetrygen..."
            go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@latest
        fi
        
        echo "Sending test trace..."
        telemetrygen traces --traces 1 --otlp-endpoint localhost:4317 --otlp-insecure
        
        echo "Sending test metrics..."
        telemetrygen metrics --otlp-endpoint localhost:4317 --otlp-insecure
        
        echo ""
        echo "✅ Test telemetry sent!"
        echo "Check SigNoz at http://localhost:3301"
        ;;
    
    clean)
        echo "�� Cleaning up (removing all containers and volumes)..."
        cd "$STACK_DIR"
        docker-compose down -v
        echo "✅ Stack cleaned"
        ;;
    
    *)
        echo "SigNoz Stack Management"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  start          Start the stack"
        echo "  stop           Stop the stack"
        echo "  restart        Restart the stack"
        echo "  status         Show stack status"
        echo "  logs           View all logs (follow mode)"
        echo "  logs-otel      View OTel Collector logs"
        echo "  logs-signoz    View SigNoz backend logs"
        echo "  health         Check health of all services"
        echo "  test-telemetry Send test telemetry data"
        echo "  clean          Remove all containers and volumes"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 logs -f"
        echo "  $0 health"
        ;;
esac
