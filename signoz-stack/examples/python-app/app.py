#!/usr/bin/env python3
"""
Example Python application with OpenTelemetry tracing and structured JSON logging.
Sends traces and logs to SigNoz OTLP collector.
"""

import time
import random
import structlog
from flask import Flask, request, jsonify
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.trace.status import Status, StatusCode
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
import logging

# Configure structured JSON logging
structlog.configure(
    processors=[
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Configure OpenTelemetry
resource = Resource(attributes={
    "service.name": "python-test-app",
    "deployment.environment": "test-platform",
    "service.namespace": "examples",
    "service.version": "1.0.0",
    "team": "platform-team"
})

# Setup tracing
trace.set_tracer_provider(TracerProvider(resource=resource))
otlp_exporter = OTLPSpanExporter(
    endpoint="http://signoz-otel-collector:4317",
    insecure=True
)
# Use optimized batch settings for test/demo environment
# - schedule_delay_millis: Export every 5 seconds (default 30s)
# - max_export_batch_size: Export in batches of 50 spans (default 512)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(
        otlp_exporter,
        schedule_delay_millis=5000,  # Export every 5 seconds
        max_export_batch_size=50     # Smaller batches for faster visibility
    )
)

# Setup logging with OTLP
logger_provider = LoggerProvider(resource=resource)
log_exporter = OTLPLogExporter(
    endpoint="http://signoz-otel-collector:4318/v1/logs",
    headers={}
)
# Optimized batch settings for logs
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(
        log_exporter,
        schedule_delay_millis=5000,  # Export every 5 seconds
        max_export_batch_size=50     # Smaller batches
    )
)

# Attach OTLP handler to root logger
handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)

tracer = trace.get_tracer(__name__)

# Create Flask app
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

def log_with_trace(level, message, **kwargs):
    """Helper function to log with trace context and HTTP attributes."""
    span = trace.get_current_span()
    span_context = span.get_span_context()
    
    log_data = {
        "message": message,
        "service.name": "python-test-app",
        **kwargs
    }
    
    if span_context.is_valid:
        log_data["trace_id"] = format(span_context.trace_id, '032x')
        log_data["span_id"] = format(span_context.span_id, '016x')
        
        # Extract HTTP attributes from span
        if hasattr(span, 'attributes') and span.attributes:
            # Add HTTP method, status code, route, etc. if available
            for key in ['http.method', 'http.status_code', 'http.route', 'http.target', 'http.scheme']:
                if key in span.attributes:
                    log_data[key] = span.attributes[key]
    
    # Also add from Flask request context if available
    if request:
        log_data.setdefault('http.method', request.method)
        log_data.setdefault('http.target', request.path)
    
    # Log to console (stdout) for debugging - using print for visibility
    import json
    print(json.dumps(log_data), flush=True)
    
    # Send to OTLP via standard logging (which has the LoggingHandler attached)
    # Remove 'message' from extra to avoid conflict with logging module
    otlp_data = {k: v for k, v in log_data.items() if k != 'message'}
    log_level_map = {'info': logging.INFO, 'warning': logging.WARNING, 'error': logging.ERROR}
    logging.log(log_level_map.get(level, logging.INFO), message, extra=otlp_data)

# Add middleware to log all HTTP requests
@app.before_request
def log_request_info():
    log_with_trace("info", "Request received", 
        http_method=request.method,
        http_path=request.path,
        http_remote_addr=request.remote_addr
    )

@app.after_request
def log_response_info(response):
    log_with_trace("info", "Request completed",
        http_method=request.method,
        http_path=request.path,
        http_status_code=response.status_code
    )
    return response

@app.route('/')
def index():
    log_with_trace("info", "Index page accessed", endpoint="/")
    return jsonify({
        "service": "python-test-app",
        "status": "healthy",
        "endpoints": ["/", "/hello/<name>", "/slow", "/error", "/process"]
    })

@app.route('/hello/<name>')
def hello(name):
    with tracer.start_as_current_span("process_greeting") as span:
        span.set_attribute("user.name", name)
        
        log_with_trace("info", "Processing greeting", attributes={
            "name": name,
            "endpoint": "/hello"
        })
        
        # Simulate some processing
        time.sleep(random.uniform(0.1, 0.3))
        
        greeting = f"Hello, {name}!"
        span.set_attribute("response.message", greeting)
        
        log_with_trace("info", "Greeting completed", attributes={
            "name": name,
            "greeting": greeting
        })
        
        return jsonify({"message": greeting})

@app.route('/slow')
def slow_endpoint():
    with tracer.start_as_current_span("slow_operation") as span:
        log_with_trace("info", "Starting slow operation", endpoint="/slow")
        
        # Simulate a slow operation with multiple steps
        steps = ["initialization", "processing", "finalization"]
        for step in steps:
            with tracer.start_as_current_span(f"step_{step}") as step_span:
                duration = random.uniform(0.5, 1.5)
                step_span.set_attribute("step.name", step)
                step_span.set_attribute("step.duration", duration)
                
                log_with_trace("debug", f"Executing step: {step}", attributes={
                    "step": step,
                    "duration_ms": int(duration * 1000)
                })
                
                time.sleep(duration)
        
        log_with_trace("info", "Slow operation completed", endpoint="/slow")
        
        return jsonify({"message": "Operation completed", "steps": steps})

@app.route('/error')
def error_endpoint():
    with tracer.start_as_current_span("error_operation") as span:
        log_with_trace("warn", "Entering error-prone endpoint", endpoint="/error")
        
        try:
            # Simulate random errors
            if random.random() < 0.5:
                raise ValueError("Random error occurred!")
            
            log_with_trace("info", "Operation succeeded without error")
            return jsonify({"message": "Success!"})
            
        except Exception as e:
            span.set_status(Status(StatusCode.ERROR, str(e)))
            span.record_exception(e)
            
            log_with_trace("error", "Error occurred during operation", attributes={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "endpoint": "/error"
            })
            
            return jsonify({"error": str(e)}), 500

@app.route('/process')
def process_data():
    with tracer.start_as_current_span("data_processing") as span:
        items = random.randint(5, 20)
        span.set_attribute("data.item_count", items)
        
        log_with_trace("info", "Starting data processing", attributes={
            "item_count": items
        })
        
        processed = 0
        errors = 0
        
        for i in range(items):
            with tracer.start_as_current_span("process_item") as item_span:
                item_span.set_attribute("item.id", i)
                
                # Simulate processing with occasional errors
                if random.random() < 0.1:
                    errors += 1
                    item_span.set_status(Status(StatusCode.ERROR, "Processing failed"))
                    log_with_trace("error", "Item processing failed", attributes={
                        "item_id": i,
                        "reason": "validation_error"
                    })
                else:
                    processed += 1
                    item_span.set_attribute("item.status", "success")
                
                time.sleep(random.uniform(0.01, 0.05))
        
        span.set_attribute("data.processed", processed)
        span.set_attribute("data.errors", errors)
        
        log_with_trace("info", "Data processing completed", attributes={
            "total_items": items,
            "processed": processed,
            "errors": errors,
            "success_rate": f"{(processed/items)*100:.1f}%"
        })
        
        return jsonify({
            "total": items,
            "processed": processed,
            "errors": errors
        })

if __name__ == '__main__':
    log_with_trace("info", "Python test application starting", attributes={
        "port": 5000,
        "environment": "test-platform"
    })
    
    app.run(host='0.0.0.0', port=5000, debug=False)
