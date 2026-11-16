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

COPY --from=build /workspace/apps/web-frontend/dist /usr/share/nginx/html
COPY ops/docker/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080
