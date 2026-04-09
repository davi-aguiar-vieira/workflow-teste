# =============================================================
# Apache Ranger Admin – custom Docker image
# Installs Ranger 2.4.0 with PostgreSQL backend (no Solr).
# =============================================================
FROM ubuntu:22.04

ARG RANGER_VERSION=2.4.0

ENV RANGER_VERSION=${RANGER_VERSION}
ENV RANGER_HOME=/opt/ranger-admin
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=${JAVA_HOME}/bin:${PATH}
# Suppress interactive prompts during apt install
ENV DEBIAN_FRONTEND=noninteractive

# ---- system dependencies ----------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        wget \
        openjdk-11-jdk \
        python3 \
        python3-pip \
        postgresql-client \
        procps \
        net-tools \
    && rm -rf /var/lib/apt/lists/*

# ---- PostgreSQL JDBC driver -------------------------------------
RUN wget -q -O /opt/postgresql-jdbc.jar \
    "https://jdbc.postgresql.org/download/postgresql-42.7.1.jar"

# ---- Download Apache Ranger admin --------------------------------
WORKDIR /opt
RUN wget -q \
    "https://archive.apache.org/dist/ranger/${RANGER_VERSION}/ranger-${RANGER_VERSION}-admin.tar.gz" \
    -O /tmp/ranger-admin.tar.gz \
    && tar -xzf /tmp/ranger-admin.tar.gz \
    && mv "ranger-${RANGER_VERSION}-admin" ranger-admin \
    && rm /tmp/ranger-admin.tar.gz

# ---- Configuration and startup scripts --------------------------
COPY install.properties ${RANGER_HOME}/install.properties
COPY entrypoint.sh      /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6080

ENTRYPOINT ["/entrypoint.sh"]
