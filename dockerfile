# Build stage: Use Golang 1.25 Alpine for a fast, modern build environment
FROM golang:1.25-alpine AS builder

# Install make and build tools (Alpine uses apk)
RUN apk add --no-cache make gcc musl-dev bash

# Minimal Slurm configuration to allow `sinfo` to run
RUN mkdir -p /etc/slurm-llnl && \
    echo -e "SlurmdPort=7003\nSlurmctldPort=7002\nAuthType=auth/none\nControlMachine=localhost\nMpiDefault=none\nProctrackType=proctrack/pgid\nReturnToService=2\nSlurmdLogFile=/var/log/slurmd.log\nSlurmdSpoolDir=/var/spool/slurmd\nStateSaveLocation=/var/spool/slurmctld\nSwitchType=switch/none\nTaskPlugin=task/none" \
    > /etc/slurm-llnl/slurm.conf
    
# Create mock sinfo, squeue, and sdiag scripts (only in the build stage)
RUN printf '#!/bin/sh\n\necho "100/200/50/350"\n' > /usr/local/bin/sinfo && \
    chmod +x /usr/local/bin/sinfo && \
    printf '#!/bin/sh\n\necho "running:10 pending:5"\n' > /usr/local/bin/squeue && \
    chmod +x /usr/local/bin/squeue && \
    printf '#!/bin/sh\n\necho "mocked scheduler diagnostic data"\n' > /usr/local/bin/sdiag && \
    chmod +x /usr/local/bin/sdiag

# Set up environment variables for Go
ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 
    # GOPROXY=direct \
    # GOSUMDB=off

# Set the working directory inside the container
WORKDIR /app

# Copy the source code into the container
COPY . .

# Debug: Print environment variables
RUN env

# Build the application binary using the Makefile
RUN make build SHELL=/bin/bash
RUN ldd /app/bin/slurm_exporter || echo "Static binary or ldd not found"

# Final stage: Use the public Red Hat UBI Micro image
# Alternatively, use 'alpine:latest' or 'scratch' for an even smaller image
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

# Set up environment variables
ENV SLURM_EXPORTER_PORT=8080

# Copy the binary from the builder stage
COPY --from=builder /app/bin/slurm_exporter /slurm_exporter

# Set environment variables for library and binary paths (best set during runtime)
# ENV LD_LIBRARY_PATH=/opt/software/slurm/20.02.3/lib:/lib64:/opt/software/slurm/20.02.3/lib
# ENV PATH=/opt/software/slurm/20.02.3/bin:/opt/software/slurm/20.02.3/sbin:/usr/local/sbin:/sbin:/bin:/usr/sbin:/usr/bin

# Expose the default port
EXPOSE 8080

# Command to run the exporter
ENTRYPOINT ["/slurm_exporter"]
CMD ["--listen-address=0.0.0.0:8080"]
