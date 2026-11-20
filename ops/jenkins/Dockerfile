# Jenkins controller of the local CI stack (design D5 and D6).
#
# It carries the same toolchain the maintainer uses on the host, pinned to the
# versions registered in PROJECT.md §4, so a green build in CI cannot depend on
# "it works on my machine". Every version lives in a build arg and is asserted as
# soon as it is installed: a base-image bump that drifts a version fails the
# build instead of producing an image nobody inspects.
#
# Build context: ops/jenkins/, because the only file the image copies is
# plugins.txt. The daemon that builds the project images is the separate
# buildkitd container (design D2): the Docker CLI installed below is the client
# of the dind test daemon, never a builder and never a host socket.

FROM jenkins/jenkins:2.580.2-lts-jdk21

ARG TEMURIN_VERSION=21.0.13+9
ARG MAVEN_VERSION=3.9.16
ARG NODE_VERSION=22.23.5
ARG BUILDKIT_VERSION=0.35.0
ARG SYFT_VERSION=1.57.2
ARG TRIVY_VERSION=0.76.2
ARG DOCKER_CLI_VERSION=29.10.0
ARG DOCKER_COMPOSE_VERSION=5.7.1

# The -jdk21 tag already ships Temurin as JAVA_HOME (/opt/java/openjdk), and its
# version is exactly the one the project pins, so the JDK is verified instead of
# reinstalled: two JDKs in one image would only add weight and a second source of
# truth about which one the build uses (design D5).
RUN java -version 2>&1 | grep -F "Temurin-${TEMURIN_VERSION}"

USER root

# Tarballs below are x86_64 builds: the CI stack runs on the single x86_64 host
# described in design D8. Each release spells the architecture differently
# (linux-x64, linux-amd64, linux_amd64, Linux-64bit), so the names are written
# literally instead of hidden behind a variable.

# Maven: the release the wrapper pins, so `./mvnw` and `mvn` cannot disagree.
RUN curl -fsSL "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      | tar -xz -C /opt \
    && ln -s "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven \
    && /opt/maven/bin/mvn -v | grep -F "Apache Maven ${MAVEN_VERSION}"

# Node.js: 22.23.5, above the 22.22.0 the frontend requires (PROJECT.md §4).
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" \
      | tar -xz -C /opt \
    && ln -s "/opt/node-v${NODE_VERSION}-linux-x64" /opt/node \
    && [ "$(/opt/node/bin/node -v)" = "v${NODE_VERSION}" ]

# buildctl only: the daemon is the buildkitd container, so the controller keeps
# its hands off the host Docker socket (design D1/R3).
RUN mkdir -p /tmp/buildkit \
    && curl -fsSL "https://github.com/moby/buildkit/releases/download/v${BUILDKIT_VERSION}/buildkit-v${BUILDKIT_VERSION}.linux-amd64.tar.gz" \
      | tar -xz -C /tmp/buildkit bin/buildctl \
    && mv /tmp/buildkit/bin/buildctl /usr/local/bin/buildctl \
    && rm -rf /tmp/buildkit \
    && buildctl --version | grep -F "v${BUILDKIT_VERSION}"

# SBOM: reads the OCI archive exported by buildctl, no daemon involved (D4).
RUN curl -fsSL "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin syft \
    && syft version | grep -E "^Version:[[:space:]]+${SYFT_VERSION}$"

# Vulnerability gate: scans the extracted OCI layout, no daemon involved (D4).
RUN curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
      | tar -xz -C /usr/local/bin trivy \
    && trivy --version | grep -F "Version: ${TRIVY_VERSION}"

# Docker client and Compose plugin (change ci-integration, design D2): the integration, e2e and
# environment stages drive the dind container through DOCKER_HOST, so the controller needs the
# client but never a daemon of its own. The image ships both versions asserted here, exactly like
# the rest of the toolchain: a silent drift fails the build instead of surfacing as a pipeline
# that speaks a different Compose syntax.
RUN mkdir -p /tmp/docker \
    && curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz" \
      | tar -xz -C /tmp/docker \
    && mv /tmp/docker/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker \
    && docker --version | grep -F "${DOCKER_CLI_VERSION}"
# The plugin goes where the CLI looks for it without extra configuration
# (~/.docker/cli-plugins or the system-wide path below), so `docker compose` resolves it for the
# jenkins user with no DOCKER_CONFIG to maintain.
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose \
    && docker compose version | grep -F "${DOCKER_COMPOSE_VERSION}"

# Mount points of the named volumes declared in docker-compose.yml (design D2,
# D3, D11): /cache, /out, /var/jenkins_home/.m2/repository and
# /var/jenkins_home/.npm. Docker initialises a fresh volume by copying the
# ownership of the directory at that path in the image, so the paths have to
# exist here and belong to the jenkins user; a path Docker creates on the fly is
# root-owned and the pipeline (buildctl, Maven, npm) cannot write to it.
RUN mkdir -p /cache /out /var/jenkins_home/.m2/repository /var/jenkins_home/.npm \
    && chown -R jenkins:jenkins /cache /out /var/jenkins_home/.m2 /var/jenkins_home/.npm

# Put the toolchain on the PATH of the jenkins user without depending on its
# shell profile (the stages run non-interactive shells).
ENV MAVEN_HOME=/opt/maven
ENV PATH="/opt/maven/bin:/opt/node/bin:${PATH}"

# Plugins are the controller's behaviour, so they are pinned one by one in
# plugins.txt and installed through the CLI, never through the web UI (design
# D6). /usr/share/jenkins/ref is what the entrypoint copies into a fresh
# JENKINS_HOME, which is what makes `down -v` + `up` reproducible.
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt

USER jenkins

# The count check ties the image to the file: a plugin that the CLI silently
# dropped (or added as an extra transitive dependency) fails the build here.
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt \
        --plugin-download-directory /usr/share/jenkins/ref/plugins \
        --clean-download-directory \
    && [ "$(find /usr/share/jenkins/ref/plugins -name '*.jpi' | wc -l)" \
         -eq "$(grep -vc '^#' /usr/share/jenkins/ref/plugins.txt)" ]

# The base image already ends as USER jenkins; the line is explicit because
# nothing in this image may run as root at runtime.
USER jenkins
