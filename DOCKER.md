# Docker Setup Guide

This guide covers building and running the Multi-threaded Database Server in Docker.

## Quick Start

### Using Docker Compose (Recommended)

```bash
docker-compose up -d
```

Access the server on `localhost:1234`.

Stop the server:
```bash
docker-compose down
```

### Using Docker CLI

**Build the image:**
```bash
docker build -t kv-database-server:latest .
```

**Run the container:**
```bash
docker run -d \
  --name kv-server \
  -p 1234:1234 \
  kv-database-server:latest
```

**View logs:**
```bash
docker logs -f kv-server
```

**Stop the container:**
```bash
docker stop kv-server
docker rm kv-server
```

## Image Variants

### Standard (Ubuntu 22.04)

**Dockerfile:** `Dockerfile`
- **Base:** ubuntu:22.04
- **Size:** ~500MB
- **Pros:** Well-supported, familiar environment
- **Cons:** Larger image size

```bash
docker build -f Dockerfile -t kv-database-server:ubuntu .
```

### Lightweight (Alpine Linux)

**Dockerfile:** `Dockerfile.alpine`
- **Base:** alpine:3.18
- **Size:** ~50MB
- **Pros:** Minimal footprint, fast startup
- **Cons:** Limited package ecosystem

```bash
docker build -f Dockerfile.alpine -t kv-database-server:alpine .
```

## Docker Compose Configuration

The `docker-compose.yml` includes:

- **Port Mapping:** 1234:1234
- **Container Name:** kv-database-server
- **Restart Policy:** unless-stopped (auto-restart on crash)
- **Health Check:** TCP connectivity probe every 10s
- **Logging:** JSON file driver with 10MB max size, 3 file rotation

### Health Check

The container includes a health check that verifies the server is listening:

```bash
docker ps
# Status will show "healthy" or "unhealthy"
```

## Building from Makefile

### Build image:
```bash
make docker-build
```

### Run container:
```bash
make docker-run
```

### Stop container:
```bash
make docker-stop
```

### Docker Compose:
```bash
make docker-compose-up
make docker-compose-down
```

## Testing the Server

### Using netcat inside container:

```bash
# Get container ID
CONTAINER_ID=$(docker ps --filter "name=kv-server" -q)

# Test connectivity
docker exec $CONTAINER_ID nc -z localhost 1234 && echo "Server is running"
```

### From host machine (requires netcat/nc):

```bash
nc localhost 1234
# Should connect successfully (Ctrl+C to exit)
```

### Using Python client:

```bash
# Create a simple test script
cat > test_server.py << 'EOF'
import socket
import struct

def send_command(cmd_parts):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(('localhost', 1234))

    # Build protocol message
    msg = struct.pack('<I', len(cmd_parts))
    for part in cmd_parts:
        msg += struct.pack('<I', len(part)) + part.encode()

    sock.send(msg)
    response = sock.recv(4096)
    sock.close()
    return response

# Test SET command
print("Testing SET...")
send_command(['set', 'mykey', 'myvalue'])

# Test GET command
print("Testing GET...")
response = send_command(['get', 'mykey'])
print(f"Response: {response.hex()}")

print("Server is working!")
EOF

python3 test_server.py
```

## Environment Variables

Currently, the docker-compose sets:
- `MALLOC_TRIM_THRESHOLD_`: Memory allocation tuning (131072 bytes)

Add more variables in `docker-compose.yml` under `environment:` as needed.

## Networking

### Single Container
```bash
docker run -p 1234:1234 kv-database-server:latest
```
- Server accessible at `localhost:1234`

### Multiple Containers with Docker Compose
```bash
docker-compose up -d
```
- Services communicate via service name
- Accessible externally on `localhost:1234`

### Custom Network
```bash
docker network create kv-network
docker run --network kv-network --name server1 kv-database-server:latest
docker run --network kv-network --name client alpine nc server1 1234
```

## Performance Tuning

### Increase ulimits:

```yaml
# In docker-compose.yml
services:
  database-server:
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
      nproc:
        soft: 32768
        hard: 32768
```

### CPU/Memory limits:

```yaml
services:
  database-server:
    cpus: '2'
    memory: '512m'
    memswap_limit: '512m'
```

### Resource reservations:

```yaml
services:
  database-server:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: '2G'
        reservations:
          cpus: '2'
          memory: '1G'
```

## Troubleshooting

### Container exits immediately:

```bash
docker logs kv-server
# Check for compilation or runtime errors
```

### Port already in use:

```bash
# Kill the process using port 1234
lsof -i :1234
kill -9 <PID>

# Or use a different port in docker-compose.yml
ports:
  - "5000:1234"
```

### Connection refused:

```bash
# Verify container is running
docker ps | grep kv-server

# Check health
docker ps --format "table {{.Names}}\t{{.Status}}"

# Inspect logs
docker logs -f kv-server
```

### Out of memory:

```bash
# Increase memory allocation in docker-compose.yml
docker-compose down
# Edit docker-compose.yml, increase memory
docker-compose up -d
```

## Production Deployment

### 1. Build optimized image:
```bash
docker build -f Dockerfile.alpine -t kv-database-server:1.0 .
docker tag kv-database-server:1.0 myregistry.azurecr.io/kv-database-server:1.0
docker push myregistry.azurecr.io/kv-database-server:1.0
```

### 2. Deploy with docker-compose:
```bash
docker-compose -f docker-compose.yml up -d
```

### 3. Enable monitoring:
Add volume for logs:
```yaml
services:
  database-server:
    volumes:
      - ./logs:/var/log/kv-server
```

### 4. Set up backup (if persistence added):
```yaml
services:
  database-server:
    volumes:
      - kv-data:/data
volumes:
  kv-data:
    driver: local
```

## Cleanup

### Remove stopped containers:
```bash
docker container prune
```

### Remove dangling images:
```bash
docker image prune
```

### Remove unused volumes:
```bash
docker volume prune
```

### Full cleanup (WARNING: removes all unused Docker resources):
```bash
docker system prune -a --volumes
```

## Next Steps

1. **Add persistence:** Implement RDB/AOF to persist data to volumes
2. **Add monitoring:** Integrate Prometheus metrics endpoint
3. **Multi-stage build:** Reduce final image size
4. **CI/CD integration:** Automate building and pushing to registry
5. **Kubernetes:** Deploy with Helm charts
