# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache gcc musl-dev

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o firecracker-vps .

# Final stage
FROM alpine:3.18

# Install required packages for Firecracker
RUN apk add --no-cache \
    ca-certificates \
    iptables \
    bridge-utils \
    iproute2 \
    qemu-img \
    curl \
    bash

# Create required directories
RUN mkdir -p /var/lib/firecracker-vms \
    /var/lib/firecracker/images \
    /var/log/firecracker

# Create firecracker user
RUN addgroup -g 1000 firecracker && \
    adduser -D -s /bin/sh -u 1000 -G firecracker firecracker

# Copy binary from builder stage
COPY --from=builder /app/firecracker-vps /usr/local/bin/

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set permissions
RUN chown -R firecracker:firecracker /var/lib/firecracker-vms /var/lib/firecracker /var/log/firecracker

# Expose API port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Set user
USER firecracker

# Entry point
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/firecracker-vps"]
