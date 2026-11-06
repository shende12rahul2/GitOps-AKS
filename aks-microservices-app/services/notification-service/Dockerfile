# syntax=docker/dockerfile:1.7
# Build context: repository root (shared libs/svc-common is copied in).
#   docker build -f services/notification-service/Dockerfile -t notification-service:dev .
ARG PYTHON_IMAGE=python:3.13-slim-trixie@sha256:09a17cad02668ae61ece136b4fd36ac3849e14f670ebedb637ea3e15580525bc

FROM ${PYTHON_IMAGE} AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
COPY libs/svc-common /src/svc-common
COPY services/notification-service/requirements.txt /src/requirements.txt
RUN /opt/venv/bin/pip install /src/svc-common -r /src/requirements.txt

FROM ${PYTHON_IMAGE}
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="notification-service" \
      org.opencontainers.image.source="https://github.com/REPLACE_ORG/aks-microservices-app" \
      org.opencontainers.image.version="${APP_VERSION}"
# Non-root runtime user with a fixed UID/GID: Azure Files is mounted with
# uid=10001,gid=10001 so every service can read and write the shared volume.
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app
COPY --from=build /opt/venv /opt/venv
COPY services/notification-service/app /app/app

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}
WORKDIR /app
USER 10001:10001
EXPOSE 8000
# The root filesystem is read-only in Kubernetes; nothing is written outside /tmp and /mnt/shared.
ENTRYPOINT ["uvicorn", "app.main:build", "--factory", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*", "--no-server-header", "--no-access-log"]
