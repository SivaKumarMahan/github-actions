const express = require('express');

const app = express();
const port = Number(process.env.PORT) || 3000;
// APP_MESSAGE comes from the Helm values (one value per environment).
const message = process.env.APP_MESSAGE || 'Hello from AKS!';
const version = process.env.APP_VERSION || 'dev';

app.disable('x-powered-by');

app.get('/', (req, res) => res.send(message));

// Kubernetes readiness/liveness probes and the Helm smoke test call this.
app.get('/health', (req, res) => res.json({ status: 'ok', version }));

if (require.main === module) {
  const server = app.listen(port, () => console.log(`Server running on port ${port}, version ${version}`));

  // Kubernetes sends SIGTERM when it stops a pod (rolling update, scale-in, node drain).
  const shutdown = (signal) => {
    console.log(`${signal} received, shutting down`);
    server.close(() => process.exit(0));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = app;
