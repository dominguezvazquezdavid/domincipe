# One Dockerfile for the six Java applications: MODULE selects the Maven module
# to package and the runtime stage is identical for all of them (design D11).
#
# Build context: the repository root, because the reactor, the shared libraries,
# the Checkstyle configuration and scripts/verify-modules.sh all live there.

# The Maven release matches the version fixed by the wrapper (3.9.16) and the JDK
# is 21, so images and local builds share the same toolchain (design D2).
FROM maven:3.9.16-eclipse-temurin-21-alpine AS build

# Module to package, relative to the repository root
# (for example apps/services/auth-service).
ARG MODULE
RUN test -n "${MODULE}" || (echo "MODULE build arg is required" >&2; exit 1)

WORKDIR /workspace
COPY . .

# scripts/verify-modules.sh runs in the validate phase and needs bash, which
# Alpine does not ship by default.
RUN apk add --no-cache bash

# The suite and the coverage gate belong to `mvn verify` and Jenkins: the image
# only needs the repackaged executable jar, and Testcontainers has no Docker
# daemon inside this stage. -am also builds the shared libraries the module uses.
RUN mvn -B -ntp -pl "${MODULE}" -am package -DskipTests

# Runtime: JRE only, so neither the compiler nor Maven reach the shipped image.
FROM eclipse-temurin:21.0.13_9-jre-alpine AS runtime

ARG MODULE

# Short git SHA injected by scripts/build-images.sh. It is metadata only: it
# lands in the OCI revision label so a running image can be traced back to the
# commit it was built from (design D11).
ARG GIT_SHA

# Fixed non-root identity shared by every environment, so volume permissions and
# Kubernetes securityContexts can rely on it.
RUN addgroup -S -g 10001 domincipe \
    && adduser -S -H -u 10001 -G domincipe -s /sbin/nologin domincipe

WORKDIR /app
COPY --from=build /workspace/${MODULE}/target/*.jar /app/app.jar

LABEL org.opencontainers.image.revision="${GIT_SHA}"

# Configuration stays in the environment (12-factor). JAVA_TOOL_OPTIONS is read
# by the JVM itself, so Compose and Kubernetes can tune it without a shell
# wrapper; CMD (not ENTRYPOINT) keeps `docker run <image> <command>` usable for
# one-off checks such as `id -u`, and java stays PID 1 for graceful shutdown.
ENV JAVA_TOOL_OPTIONS=""
USER 10001:10001
EXPOSE 8080
CMD ["java", "-jar", "/app/app.jar"]
