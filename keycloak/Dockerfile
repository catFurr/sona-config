# keycloak/Dockerfile
# Stage 1: Build the custom scripts JAR
FROM eclipse-temurin:17-jdk-focal AS script_jar_builder

WORKDIR /tmp/keycloak-custom-scripts

# Copy custom provider scripts (all .js files) and META-INF directory
COPY ./META-INF ./META-INF/
COPY ./*.js .

# Copy and run the build script
COPY ./build-all.sh .
RUN chmod +x ./build-all.sh && bash ./build-all.sh

# -----
# Stage 2: Install curl using a UBI image
FROM registry.access.redhat.com/ubi9 AS curl_installer
RUN mkdir -p /mnt/rootfs
RUN dnf install --installroot /mnt/rootfs curl --releasever 9 --setopt install_weak_deps=false --nodocs -y && \
    dnf --installroot /mnt/rootfs clean all && \
    rm -rf /mnt/rootfs/var/cache/dnf /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/yum.*

# -----
# Stage 3: Configure Keycloak and incorporate the custom scripts JAR
FROM quay.io/keycloak/keycloak:26.2.0 AS keycloak_config_builder

# Configure build settings
ENV KC_DB=postgres
ENV KC_FEATURES=preview
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_VAULT=file
# KC_VAULT
ENV KC_EVENT_METRICS_USER_ENABLED=true
ENV KC_HTTP_RELATIVE_PATH=/auth

WORKDIR /opt/keycloak
RUN mkdir -p /opt/keycloak/providers

# Copy the custom-scripts.jar from the script_jar_builder stage and set ownership/permissions
COPY --from=script_jar_builder --chown=keycloak:keycloak --chmod=644 /tmp/keycloak-custom-scripts/custom-scripts.jar /opt/keycloak/providers/custom-scripts.jar

# Copy the keycloak-events.jar from the build context and set ownership/permissions
# https://repo1.maven.org/maven2/io/phasetwo/keycloak/keycloak-events/0.46/keycloak-events-0.46.jar
COPY --chown=keycloak:keycloak --chmod=644 ./keycloak-events.jar /opt/keycloak/providers/keycloak-events.jar

# Keycloak's build step - this will pick up providers from /opt/keycloak/providers
RUN echo "--- Contents of /opt/keycloak/providers before kc.sh build:" && ls -la /opt/keycloak/providers
RUN /opt/keycloak/bin/kc.sh build

# -----
# Final image
FROM quay.io/keycloak/keycloak:26.2.0

# Copy the optimized Keycloak server from the keycloak_config_builder stage.
COPY --from=keycloak_config_builder /opt/keycloak/ /opt/keycloak/

# Copy curl and its dependencies from the curl_installer stage
COPY --from=curl_installer /mnt/rootfs /

# Assuming 8GB of RAM
# ENV JAVA_OPTS_KC_HEAP="-XX:MaxHeapFreeRatio=25 -XX:MaxRAMPercentage=25"

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]