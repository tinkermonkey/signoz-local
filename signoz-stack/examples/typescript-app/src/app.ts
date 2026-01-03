/**
 * Example TypeScript application with OpenTelemetry tracing and structured JSON logging.
 * Sends traces and logs to SigNoz OTLP collector.
 */

import express, { Request, Response } from 'express';
import pino from 'pino';
import { trace, SpanStatusCode, context } from '@opentelemetry/api';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';
import { Resource } from '@opentelemetry/resources';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { LoggerProvider, BatchLogRecordProcessor } from '@opentelemetry/sdk-logs';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { ExpressInstrumentation } from '@opentelemetry/instrumentation-express';
import { registerInstrumentations } from '@opentelemetry/instrumentation';

// Configure structured JSON logging with pino
const logger = pino({
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
  base: {
    'service.name': 'typescript-test-app'
  }
});

// Configure OpenTelemetry
const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: 'typescript-test-app',
  [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  [SemanticResourceAttributes.SERVICE_NAMESPACE]: 'examples',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: 'test-platform',
  'team': 'platform-team'
});

// Setup tracing
const provider = new NodeTracerProvider({ resource });
const traceExporter = new OTLPTraceExporter({
  url: 'http://signoz-otel-collector:4317',
});
// Use optimized batch settings for test/demo environment
// - scheduledDelayMillis: Export every 5 seconds (default 30s)
// - maxExportBatchSize: Export in batches of 50 spans (default 512)
provider.addSpanProcessor(new BatchSpanProcessor(traceExporter, {
  scheduledDelayMillis: 5000,  // Export every 5 seconds
  maxExportBatchSize: 50        // Smaller batches for faster visibility
}));
provider.register();

// Setup logging with OTLP
const loggerProvider = new LoggerProvider({ resource });
const logExporter = new OTLPLogExporter({
  url: 'http://signoz-otel-collector:4318/v1/logs',
});
// Optimized batch settings for logs
loggerProvider.addLogRecordProcessor(new BatchLogRecordProcessor(logExporter, {
  scheduledDelayMillis: 5000,  // Export every 5 seconds
  maxExportBatchSize: 50        // Smaller batches
}));

const otelLogger = loggerProvider.getLogger('typescript-test-app', '1.0.0');

// Helper to add trace context to logs and send via OTLP
function logWithTrace(level: string, message: string, attributes: Record<string, any> = {}) {
  const span = trace.getActiveSpan();
  const spanContext = span?.spanContext();
  
  const logData: any = {
    message,
    'service.name': 'typescript-test-app',
    attributes
  };
  
  if (spanContext) {
    logData.trace_id = spanContext.traceId;
    logData.span_id = spanContext.spanId;
    
    // Extract HTTP attributes from span if available
    if (span && (span as any)['attributes']) {
      const spanAttrs = (span as any)['attributes'];
      ['http.method', 'http.status_code', 'http.route', 'http.target', 'http.scheme'].forEach(key => {
        if (spanAttrs[key]) {
          logData[key] = spanAttrs[key];
        }
      });
    }
  }
  
  // Log to console for debugging
  (logger as any)[level](logData);
  
  // Send to OTLP
  otelLogger.emit({
    severityText: level.toUpperCase(),
    body: message,
    attributes: {
      ...attributes,
      'service.name': 'typescript-test-app',
      ...(spanContext && {
        'trace_id': spanContext.traceId,
        'span_id': spanContext.spanId
      })
    }
  });
}

// Register instrumentations
registerInstrumentations({
  instrumentations: [
    new HttpInstrumentation(),
    new ExpressInstrumentation(),
  ],
});

const tracer = trace.getTracer('typescript-test-app');

// Create Express app
const app = express();
app.use(express.json());

// Middleware to log all requests with HTTP metadata
app.use((req: Request, res: Response, next) => {
  logWithTrace('info', 'Request received', {
    'http.method': req.method,
    'http.target': req.path,
    'http.remote_addr': req.ip
  });
  
  // Capture response status code after request completes
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

app.get('/', (req: Request, res: Response) => {
  logWithTrace('info', 'Index page accessed', { endpoint: '/' });
  
  res.json({
    service: 'typescript-test-app',
    status: 'healthy',
    endpoints: ['/', '/hello/:name', '/calculate', '/chain', '/database']
  });
});

app.get('/hello/:name', (req: Request, res: Response) => {
  const span = tracer.startSpan('process_greeting');
  
  context.with(trace.setSpan(context.active(), span), () => {
    const { name } = req.params;
    span.setAttribute('user.name', name);
    
    logWithTrace('info', 'Processing greeting', { name, endpoint: '/hello' });
    
    // Simulate processing
    const delay = Math.random() * 200 + 100;
    setTimeout(() => {
      const greeting = `Hello, ${name}! Welcome to TypeScript service.`;
      span.setAttribute('response.message', greeting);
      
      logWithTrace('info', 'Greeting completed', { name, greeting });
      
      span.end();
      res.json({ message: greeting });
    }, delay);
  });
});

app.post('/calculate', async (req: Request, res: Response) => {
  const span = tracer.startSpan('calculate_operation');
  
  await context.with(trace.setSpan(context.active(), span), async () => {
    const { operation, values } = req.body;
    
    span.setAttribute('operation.type', operation);
    span.setAttribute('values.count', values?.length || 0);
    
    logWithTrace('info', 'Starting calculation', { operation, valueCount: values?.length });
    
    try {
      if (!values || !Array.isArray(values)) {
        throw new Error('Invalid values array');
      }
      
      let result: number;
      
      const calcSpan = tracer.startSpan('perform_calculation');
      
      switch (operation) {
        case 'sum':
          result = values.reduce((a, b) => a + b, 0);
          break;
        case 'average':
          result = values.reduce((a, b) => a + b, 0) / values.length;
          break;
        case 'max':
          result = Math.max(...values);
          break;
        case 'min':
          result = Math.min(...values);
          break;
        default:
          throw new Error(`Unknown operation: ${operation}`);
      }
      
      calcSpan.setAttribute('result', result);
      calcSpan.end();
      
      span.setAttribute('calculation.result', result);
      
      logWithTrace('info', 'Calculation completed', { 
        operation, 
        valueCount: values.length, 
        result 
      });
      
      res.json({ operation, values, result });
      
    } catch (error: any) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
      span.recordException(error);
      
      logWithTrace('error', 'Calculation failed', {
        error_type: error.constructor.name,
        error_message: error.message,
        operation
      });
      
      res.status(400).json({ error: error.message });
    } finally {
      span.end();
    }
  });
});

app.get('/chain', async (req: Request, res: Response) => {
  const span = tracer.startSpan('chain_operation');
  
  await context.with(trace.setSpan(context.active(), span), async () => {
    logWithTrace('info', 'Starting chained operations');
    
    const operations = ['fetch_data', 'transform_data', 'validate_data', 'store_data'];
    const results: string[] = [];
    
    for (const op of operations) {
      const opSpan = tracer.startSpan(op);
      
      await context.with(trace.setSpan(context.active(), opSpan), async () => {
        logWithTrace('debug', `Executing operation: ${op}`, { operation: op });
        
        // Simulate async operation
        await new Promise(resolve => setTimeout(resolve, Math.random() * 300 + 100));
        
        // Randomly fail validate_data 30% of the time
        if (op === 'validate_data' && Math.random() < 0.3) {
          opSpan.setStatus({ code: SpanStatusCode.ERROR, message: 'Validation failed' });
          logWithTrace('error', 'Validation failed', { operation: op });
          results.push(`${op}: failed`);
        } else {
          opSpan.setStatus({ code: SpanStatusCode.OK });
          logWithTrace('debug', `Operation completed: ${op}`, { operation: op });
          results.push(`${op}: success`);
        }
        
        opSpan.end();
      });
    }
    
    logWithTrace('info', 'Chained operations completed', { operations: results });
    
    span.end();
    res.json({ operations: results });
  });
});

app.get('/database', async (req: Request, res: Response) => {
  const span = tracer.startSpan('database_operations');
  
  await context.with(trace.setSpan(context.active(), span), async () => {
    logWithTrace('info', 'Simulating database operations');
    
    const queries = ['SELECT', 'INSERT', 'UPDATE'];
    const queryResults: any[] = [];
    
    for (const query of queries) {
      const querySpan = tracer.startSpan(`db_${query.toLowerCase()}`);
      querySpan.setAttribute('db.system', 'postgresql');
      querySpan.setAttribute('db.operation', query);
      
      await context.with(trace.setSpan(context.active(), querySpan), async () => {
        const duration = Math.random() * 150 + 50;
        
        logWithTrace('debug', `Executing database query`, {
          query_type: query,
          duration_ms: Math.round(duration)
        });
        
        await new Promise(resolve => setTimeout(resolve, duration));
        
        const rowsAffected = Math.floor(Math.random() * 100) + 1;
        querySpan.setAttribute('db.rows_affected', rowsAffected);
        
        queryResults.push({
          query,
          rows_affected: rowsAffected,
          duration_ms: Math.round(duration)
        });
        
        querySpan.end();
      });
    }
    
    logWithTrace('info', 'Database operations completed', {
      total_queries: queries.length,
      total_rows: queryResults.reduce((sum, r) => sum + r.rows_affected, 0)
    });
    
    span.end();
    res.json({ queries: queryResults });
  });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  logWithTrace('info', 'TypeScript test application starting', {
    port: PORT,
    environment: 'test-platform'
  });
});
