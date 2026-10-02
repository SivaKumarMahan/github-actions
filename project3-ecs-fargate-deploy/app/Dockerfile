# Node 20 reached end of life in April 2026; use the current LTS line.
ARG NODE_IMAGE=node:24.21.0-alpine3.24

# Stage 1: install production dependencies from the lock file.
FROM ${NODE_IMAGE} AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 2: runtime image.
FROM ${NODE_IMAGE}
ARG APP_VERSION=dev
ENV NODE_ENV=production \
    PORT=3000 \
    APP_VERSION=${APP_VERSION}

# The app does not need npm, npx, corepack or yarn at runtime. Removing them
# shrinks the image and removes their bundled packages from the CVE scan.
RUN rm -rf /usr/local/lib/node_modules /opt/yarn-* \
      /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
      /usr/local/bin/yarn /usr/local/bin/yarnpkg

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# The official Node image ships a non-root "node" user.
USER node

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" || exit 1

# Run node directly (not "npm start") so SIGTERM reaches the app.
CMD ["node", "src/index.js"]
