# SigNoz Troubleshooting Guide

## Prerequisites

### API Key Setup

Most diagnostic commands require a SigNoz API key for authentication:

1. Open SigNoz UI: http://localhost:8900
2. Navigate to **Settings** → **API Keys**  
3. Click **Create New Key**
4. Give it a descriptive name (e.g., "Troubleshooting", "Development")
5. Copy the generated key - it won't be shown again

**Set as environment variable:**
```bash
export SIGNOZ_API_KEY="your-api-key-here"
```

All curl commands below use `$SIGNOZ_API_KEY` for authentication.

## Traces Not Appearing in UI

### ✅ Verified: Backend is Working Correctly

The SigNoz backend **is functioning properly**. Traces are being:
1. ✅ Accepted by the OTLP collector (HTTP 200 responses)
2. ✅ Processed by the collector pipeline
3. ✅ Persisted to ClickHouse database

**Proof**: Running this query shows traces are actively being stored:

```bash
docker exec signoz-clickhouse clickhouse-client --query \
  "SELECT count() FROM signoz_traces.signoz_index_v3 WHERE timestamp >= now() - INTERVAL 1 HOUR"
```

Result: Traces are being persisted successfully.

### Common Issues and Solutions

#### 1. **Time Range Selection**

The most common reason traces "don't appear" is the time range filter in the SigNoz UI.

**Solution:**
- In the SigNoz UI (http://localhost:8900), check the time range selector
- Set it to "Last 15 minutes" or "Last 1 hour"
- Click "Refresh" or wait for auto-refresh

#### 2. **Trace Timestamps**

The collector only accepts traces with **recent timestamps**. Traces with old timestamps (e.g., hardcoded to 2020) will be rejected.

**Solution:**
- Ensure your application sends traces with current timestamps
- Use OpenTelemetry SDK's default timestamp generation (don't override unless necessary)
- Test with this curl command (uses current time):

```bash
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": { "stringValue": "my-test-service" }
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
          "spanId": "051581bf3cb55c13",
          "name": "test-operation",
          "kind": 1,
          "startTimeUnixNano": "'$(date +%s)000000000'",
          "endTimeUnixNano": "'$(($(date +%s) + 1))000000000'",
          "attributes": [{
            "key": "test.key",
            "value": { "stringValue": "test-value" }
          }]
        }]
      }]
    }]
  }'
```

#### 3. **Service Name Filter**

The UI might have a service filter applied that doesn't match your CLI's service name.

**Solution:**
- Check the service name in your OpenTelemetry configuration
- In the SigNoz UI, clear any service filters
- Verify your service appears in the Services list

#### 4. **Batch Processor Delay**

Traces may take up to 10 seconds to appear due to batch processing (configured in the collector).

**Solution:**
- Wait 10-15 seconds after sending traces
- For faster development feedback, consider reducing `timeout` in the batch processor (see Performance Tuning below)

## Verifying Trace Ingestion

### Step 1: Check if Traces are Reaching the Collector

Send a test trace to verify the collector is accepting data:

```bash
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": { "stringValue": "test-service" }
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
          "spanId": "051581bf3cb55c13",
          "name": "test-operation",
          "kind": 1,
          "startTimeUnixNano": "'$(date +%s)000000000'",
          "endTimeUnixNano": "'$(($(date +%s) + 1))000000000'",
          "attributes": [{
            "key": "http.method",
            "value": { "stringValue": "GET" }
          }]
        }]
      }]
    }]
  }'
```

**Expected response:** `{"partialSuccess":{}}`

If you get this response, the collector successfully accepted your trace.

### Step 2: Verify SigNoz Backend Health

Check that the SigNoz query service is running and accessible:

```bash
# Check SigNoz version and status
curl http://localhost:8900/api/v1/version

# Expected response:
# {"version":"v0.105.1","ee":"Y","setupCompleted":true}
```

### Step 3: Query Traces via API

Use the SigNoz Query API to verify traces are being stored and to debug filtering issues.

**List recent traces for all services:**

```bash
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
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
          "groupBy": [
            {"key": "serviceName", "dataType": "string", "type": "tag"}
          ],
          "orderBy": [{"columnName": "timestamp", "order": "desc"}],
          "limit": 10
        }
      }
    }
  }' | jq '.'
```

**Query traces for a specific service:**

```bash
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
  -d '{
    "start": "'$(($(date +%s) - 900))'000000000",
    "end": "'$(date +%s)'000000000",
    "variables": {},
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "list",
      "builderQueries": {
        "A": {
          "dataSource": "traces",
          "queryName": "A",
          "aggregateOperator": "noop",
          "aggregateAttribute": {"key": ""},
          "filters": {
            "items": [{
              "key": {"key": "serviceName", "dataType": "string", "type": "tag"},
              "op": "=",
              "value": "your-service-name"
            }],
            "op": "AND"
          },
          "orderBy": [{"columnName": "timestamp", "order": "desc"}],
          "limit": 10
        }
      }
    }
  }' | jq '.result[0].list | length'
```

**Expected output:** Number of traces found (e.g., `10`). If you get `0`, check:
- Service name matches exactly (case-sensitive)
- Time range includes when traces were sent
- Your application is successfully exporting to the collector

**Get detailed trace information:**

```bash
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
  -d '{
    "start": "'$(($(date +%s) - 900))'000000000",
    "end": "'$(date +%s)'000000000",
    "variables": {},
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "list",
      "builderQueries": {
        "A": {
          "dataSource": "traces",
          "queryName": "A",
          "aggregateOperator": "noop",
          "aggregateAttribute": {"key": ""},
          "selectColumns": [
            {"key": "serviceName", "dataType": "string", "type": "tag", "isColumn": true},
            {"key": "name", "dataType": "string", "type": "tag", "isColumn": true},
            {"key": "durationNano", "dataType": "float64", "type": "tag", "isColumn": true},
            {"key": "timestamp", "dataType": "string", "type": "tag", "isColumn": true}
          ],
          "orderBy": [{"columnName": "timestamp", "order": "desc"}],
          "limit": 5
        }
      }
    }
  }' | jq -r '.result[0].list[]? | [.serviceName, .name, .timestamp] | @tsv'
```

This shows: service name, span name, and timestamp for the 5 most recent traces.

### Step 4: Check the SigNoz UI

After sending a test trace:

1. Wait 10-15 seconds (for batch processing)
2. Open SigNoz UI: http://localhost:8900
3. Navigate to **Services** → Click on your service name
4. Set time range to "Last 15 minutes"
5. You should see your traces listed

### Step 5: Verify Your Application's Traces

Check if your application is successfully sending telemetry:

**From your application's environment:**

```bash
# Test OTLP endpoint connectivity
curl -v http://localhost:4318/v1/traces

# Should return: 405 Method Not Allowed (POST is required)
# This confirms the endpoint is reachable
```

**Check your application logs** for OpenTelemetry export confirmations or errors.

### Advanced: Direct Database Verification (Optional)

If you have Docker access and need to verify traces are persisting to the database:

```bash
# Count traces from the last hour
docker exec signoz-clickhouse clickhouse-client --query \
  "SELECT count() FROM signoz_traces.signoz_index_v3 WHERE timestamp >= now() - INTERVAL 1 HOUR"

# Show recent traces with service names
docker exec signoz-clickhouse clickhouse-client --query \
  "SELECT serviceName, name, timestamp FROM signoz_traces.signoz_index_v3 \
   ORDER BY timestamp DESC LIMIT 10 FORMAT Pretty"

# Check for a specific service
docker exec signoz-clickhouse clickhouse-client --query \
  "SELECT serviceName, name, COUNT(*) as trace_count \
   FROM signoz_traces.signoz_index_v3 \
   WHERE timestamp >= now() - INTERVAL 1 HOUR \
   GROUP BY serviceName, name \
   ORDER BY trace_count DESC \
   FORMAT Pretty"
```

**Note:** Direct database queries require Docker access. Most teams should use the SigNoz UI for troubleshooting.

### Check Collector Health (Optional)

If you have Docker/system access:

```bash
# Test collector health endpoint
curl http://localhost:13133/

# Expected: {"status":"Server available","upSince":"..."}

# Check for errors in collector logs
docker compose logs signoz-otel-collector --tail=50 | grep -i "error\|failed"
```

Most teams won't need direct log access - the SigNoz UI and test traces are sufficient for troubleshooting.

## Configuration Issues

### Incorrect Endpoint

Verify your application is connecting to the correct endpoint:

- **gRPC**: `http://localhost:4317` (or `signoz-otel-collector:4317` from Docker)
- **HTTP**: `http://localhost:4318` (or `signoz-otel-collector:4318` from Docker)

**Test from your application's environment:**

```bash
# Test HTTP endpoint (from host machine)
curl -v http://localhost:4318/v1/traces
# Should return: 405 Method Not Allowed (POST required)

# Test from Docker container
docker run --rm --network signoz-stack_signoz-network curlimages/curl:latest \
  curl -v http://signoz-otel-collector:4318/v1/traces
# Should return: 405 Method Not Allowed
```

### Network Connectivity

**From your application, test the collector endpoint:**

```bash
# If your app is on the host machine
curl -v http://localhost:4318/v1/traces

# If your app is in a Docker container on the signoz network
curl -v http://signoz-otel-collector:4318/v1/traces
```

**Expected response:** HTTP 405 (Method Not Allowed) - this confirms connectivity.
If you get "Connection refused" or timeout, check your network configuration.

## Advanced API Usage

### Query Traces by Time Range and Filters

**Find slow traces (duration > 1 second):**

```bash
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
  -d '{
    "start": "'$(($(date +%s) - 3600))'000000000",
    "end": "'$(date +%s)'000000000",
    "variables": {},
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "list",
      "builderQueries": {
        "A": {
          "dataSource": "traces",
          "queryName": "A",
          "aggregateOperator": "noop",
          "aggregateAttribute": {"key": ""},
          "filters": {
            "items": [{
              "key": {"key": "durationNano", "dataType": "float64", "type": "tag"},
              "op": ">",
              "value": "1000000000"
            }],
            "op": "AND"
          },
          "selectColumns": [
            {"key": "serviceName", "dataType": "string", "type": "tag", "isColumn": true},
            {"key": "name", "dataType": "string", "type": "tag", "isColumn": true},
            {"key": "durationNano", "dataType": "float64", "type": "tag", "isColumn": true}
          ],
          "orderBy": [{"columnName": "durationNano", "order": "desc"}],
          "limit": 10
        }
      }
    }
  }' | jq '.'
```

**Find traces with errors:**

```bash
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
  -d '{
    "start": "'$(($(date +%s) - 3600))'000000000",
    "end": "'$(date +%s)'000000000",
    "variables": {},
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "list",
      "builderQueries": {
        "A": {
          "dataSource": "traces",
          "queryName": "A",
          "aggregateOperator": "noop",
          "aggregateAttribute": {"key": ""},
          "filters": {
            "items": [{
              "key": {"key": "hasError", "dataType": "bool", "type": "tag"},
              "op": "=",
              "value": "true"
            }],
            "op": "AND"
          },
          "selectColumns": [
            {"key": "serviceName", "dataType": "string", "type": "tag", "isColumn": true},
            {"key": "name", "dataType": "string", "type": "tag", "isColumn": true},
            {"key": "statusMessage", "dataType": "string", "type": "tag", "isColumn": true}
          ],
          "orderBy": [{"columnName": "timestamp", "order": "desc"}],
          "limit": 10
        }
      }
    }
  }' | jq '.'
```

**Count traces per service (aggregation):**

```bash
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
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
          "groupBy": [
            {"key": "serviceName", "dataType": "string", "type": "tag"}
          ],
          "orderBy": [{"columnName": "A", "order": "desc"}]
        }
      }
    }
  }' | jq '.result[0].table.rows[] | {service: .data.serviceName, count: .data.A}'
```

**Get a specific trace by trace ID:**

```bash
TRACE_ID="your-trace-id-here"
curl -X POST http://localhost:8900/api/v1/traces/$TRACE_ID \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" | jq '.'
```

### Query Logs

**Get recent logs for a service:**

```bash
curl -X POST http://localhost:8900/api/v3/query_range \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
  -d '{
    "start": "'$(($(date +%s) - 900))'000000000",
    "end": "'$(date +%s)'000000000",
    "variables": {},
    "compositeQuery": {
      "queryType": "builder",
      "panelType": "list",
      "builderQueries": {
        "A": {
          "dataSource": "logs",
          "queryName": "A",
          "aggregateOperator": "noop",
          "aggregateAttribute": {"key": ""},
          "filters": {
            "items": [{
              "key": {"key": "service_name", "dataType": "string", "type": "tag"},
              "op": "=",
              "value": "your-service-name"
            }],
            "op": "AND"
          },
          "orderBy": [{"columnName": "timestamp", "order": "desc"}],
          "limit": 50
        }
      }
    }
  }' | jq '.result[0].list[] | {timestamp, body, severity}'
```

### API Response Formats

**Successful query response:**
```json
{
  "status": "success",
  "data": {
    "result": [...]
  }
}
```

**Error response:**
```json
{
  "status": "error",
  "error": {
    "code": "invalid_argument",
    "message": "description of the error"
  }
}
```

## Performance Tuning

### Faster Trace Visibility (Development)

For faster feedback during development, modify `signoz-stack/signoz-otel-collector-config.yaml`:

```yaml
processors:
  batch:
    send_batch_size: 10000
    send_batch_max_size: 11000
    timeout: 2s  # Changed from 10s to 2s
```

**Note**: This increases database load. Only use in development/testing environments.

### Production Settings

Keep the default 10s timeout for production to balance:
- Database write efficiency
- Resource usage
- Trace visibility latency

## Health Checks

### SigNoz Query Service

```bash
# Check version and health
curl http://localhost:8900/api/v1/version

# Expected response:
# {"version":"v0.105.1","ee":"Y","setupCompleted":true}
```

### OTLP Collector Endpoint

```bash
# Test collector is responding
curl -v http://localhost:4318/v1/traces

# Expected: HTTP 405 (Method Not Allowed)
# This confirms the endpoint is alive and requires POST
```

### All Services Status (Docker access required)

```bash
docker compose ps

# All services should show "healthy" status:
# - signoz (query-service)
# - signoz-clickhouse
# - signoz-otel-collector
# - signoz-zookeeper-1
```

### SigNoz UI

Open your browser to http://localhost:8900

- Should load the SigNoz dashboard
- Navigate to Services to see available services
- Check that you can view traces

## Common Error Messages

### "Connection refused" or "Connection reset by peer"

**Cause**: ClickHouse is restarting or overloaded.

**Solution**:
1. Check ClickHouse memory limits (see Memory Issues below)
2. Wait for ClickHouse to stabilize (it will auto-recover)
3. Check logs: `docker compose logs clickhouse --tail=50`

### "Memory limit exceeded"

**Cause**: ClickHouse memory configuration is too low.

**Solution**: See [TELEMETRY_FIX_SUMMARY.md](TELEMETRY_FIX_SUMMARY.md) for memory optimization details.

### "Exporting failed. Will retry"

**Cause**: Temporary connection issue. The collector will automatically retry.

**Solution**: No action needed if retries succeed. If persistent:
1. Check ClickHouse health: `docker compose ps clickhouse`
2. Restart collector: `docker compose restart signoz-otel-collector`

## Database Schema Version

SigNoz uses schema v3 (with `use_new_schema: true`). Traces are stored in:
- `signoz_traces.signoz_index_v3` (main index)
- `signoz_traces.distributed_signoz_index_v3` (distributed table)

**Don't query v2 tables** - they won't have current data.

## Getting Help

### Collect Diagnostic Information

**Information you can gather without system access:**

1. **Test trace export:**
   ```bash
   # Send a test trace and capture the response
   curl -X POST http://localhost:4318/v1/traces \
     -H "Content-Type: application/json" \
     -d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"diagnostic-test"}}]},"scopeSpans":[{"spans":[{"traceId":"'$(uuidgen | tr -d '-')'","spanId":"'$(openssl rand -hex 8)'","name":"test-span","kind":1,"startTimeUnixNano":"'$(date +%s)000000000'","endTimeUnixNano":"'$(($(date +%s) + 1))000000000'"}]}]}]}'
   
   # Should return: {"partialSuccess":{}}
   ```

2. **Check SigNoz health:**
   ```bash
   curl http://localhost:8900/api/v1/version
   ```

3. **Verify endpoint connectivity:**
   ```bash
   curl -v http://localhost:4318/v1/traces
   # Should return HTTP 405
   ```

4. **Check SigNoz UI:**
   - Can you access http://localhost:8900?
   - Do you see any services listed?
   - What time range is selected?

**If you have Docker/system access:**

```bash
# Service status
docker compose ps > service-status.txt

# Recent collector logs
docker compose logs signoz-otel-collector --tail=100 > collector-logs.txt

# Recent query service logs  
docker compose logs signoz --tail=100 > query-service-logs.txt

# ClickHouse health
docker exec signoz-clickhouse clickhouse-client --query "SELECT version()" > clickhouse-version.txt

# Trace count verification
docker exec signoz-clickhouse clickhouse-client --query \
  "SELECT serviceName, COUNT(*) as count FROM signoz_traces.signoz_index_v3 \
   WHERE timestamp >= now() - INTERVAL 1 HOUR \
   GROUP BY serviceName FORMAT Pretty" > trace-counts.txt
```

### Debug Your Application

Enable debug logging in your OpenTelemetry SDK:

**Node.js:**
```javascript
import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';
diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
```

**Python:**
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

This will show you:
- What traces are being generated
- Export attempts and responses
- Any SDK-level errors

## Summary

**The SigNoz backend is working correctly.** If traces aren't appearing:

### Quick Troubleshooting Checklist

1. ✅ **Test the collector endpoint:**
   ```bash
   curl -X POST http://localhost:4318/v1/traces -H "Content-Type: application/json" -d '{...}'
   ```
   Should return: `{"partialSuccess":{}}`

2. ✅ **Check SigNoz is running:**
   ```bash
   curl http://localhost:8900/api/v1/version
   ```
   Should return version info

3. ✅ **Verify UI access:**
   - Open http://localhost:8900
   - Check time range is set to "Last 15 minutes"
   - Look for your service in the Services list

4. ✅ **Check your application:**
   - Traces have current timestamps (not hardcoded old values)
   - Correct endpoint: `http://localhost:4317` (gRPC) or `http://localhost:4318` (HTTP)
   - Service name is set in your OpenTelemetry configuration

5. ✅ **Wait for batch processing:**
   - Traces take up to 10-15 seconds to appear
   - Refresh the UI after waiting

### Most Common Issues

1. **Time Range Filter** - UI time range doesn't match when traces were sent
2. **Old Timestamps** - Application sends traces with past timestamps
3. **Wrong Service Name** - Service filter in UI doesn't match your app
4. **Batch Delay** - Not waiting 10-15 seconds for batch processing
5. **Network Issues** - Application can't reach the collector endpoint

### When Everything Works

You should see:
- ✅ Collector returns `{"partialSuccess":{}}`
- ✅ SigNoz API responds with version info
- ✅ Traces appear in UI within 15 seconds
- ✅ Service name appears in Services list
