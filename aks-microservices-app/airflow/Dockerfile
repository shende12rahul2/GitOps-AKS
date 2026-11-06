# syntax=docker/dockerfile:1.7
# Custom Airflow image: official image + pinned providers + plugins.
# DAG *files* are delivered by Git-Sync; anything that needs pip packages or
# shared Python code (plugins/) is versioned here and rolled out through GitOps.
ARG AIRFLOW_IMAGE=apache/airflow:3.2.2-python3.12@sha256:bbe58e3204d550ab98dbf738a42c0e6663c455357ecd0e2d1440ef9cb6a75f00
FROM ${AIRFLOW_IMAGE}
ARG AIRFLOW_VERSION=3.2.2
ARG PYTHON_VERSION=3.12
COPY --chown=airflow:0 airflow/requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt \
      --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
COPY --chown=airflow:0 airflow/plugins/ /opt/airflow/plugins/
USER 50000
