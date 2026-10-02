# Node 20 reached end of life in April 2026; use the current LTS line.
FROM node:24.21.0-alpine3.24

ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app

# Install only production dependencies, from the lock file.
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src

# The official Node image ships a non-root "node" user.
USER node

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" || exit 1

# Run node directly (not "npm start") so SIGTERM reaches the app.
CMD ["node", "src/index.js"]
