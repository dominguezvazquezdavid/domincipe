# Builds the SPA with Node and serves the static bundle from unprivileged nginx
# (design D11). Build context: the repository root, so the nginx configuration
# next to this Dockerfile is part of the context.

FROM node:22.23.5-alpine AS build

WORKDIR /workspace/apps/web-frontend

# Dependency manifests first: the npm layer is reused while they do not change.
COPY apps/web-frontend/package.json apps/web-frontend/package-lock.json apps/web-frontend/.npmrc ./
RUN npm ci

COPY apps/web-frontend/ ./

# The API endpoint is configuration, not a secret, and vite.config.ts fails the
# build when it is missing or blank (design D13).
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}

RUN npm run build

# The image already runs as UID 101 and listens on 8080, so only the bundle and
# the SPA routing rules are added.
FROM nginxinc/nginx-unprivileged:1.30.6-alpine AS runtime

# The pinned tag is only rebuilt upstream when nginx or Alpine change, so its
# packages lag behind the Alpine 3.24 patch releases while the tag stays the
# current one. The vulnerability gate (design D9) fails the build when a fix is
# already published, so the runtime stage upgrades the base packages here; the
# tag remains pinned and an unreachable repository fails the build instead of
# shipping a silently different image. UID 101 is the runtime user of the image,
# so apk needs root for this step only.
USER root
RUN apk upgrade --no-cache
USER 101

# Short git SHA injected by scripts/build-images.sh and recorded as the OCI
# revision label, so a running image can be traced back to its commit (D11).
ARG GIT_SHA

COPY --from=build /workspace/apps/web-frontend/dist /usr/share/nginx/html
COPY ops/docker/nginx.conf /etc/nginx/conf.d/default.conf

LABEL org.opencontainers.image.revision="${GIT_SHA}"

EXPOSE 8080
