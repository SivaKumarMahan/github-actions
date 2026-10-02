const express = require('express');

const app = express();
const port = Number(process.env.PORT) || 3000;

app.disable('x-powered-by');

app.get('/', (req, res) => res.send('Hello from GitHub Actions CI/CD!'));

// Used by the Docker HEALTHCHECK and by load balancers.
app.get('/health', (req, res) => res.json({ status: 'ok' }));

if (require.main === module) {
  const server = app.listen(port, () => console.log(`Server running on port ${port}`));

  // docker stop sends SIGTERM. Close open connections and exit cleanly.
  const shutdown = (signal) => {
    console.log(`${signal} received, shutting down`);
    server.close(() => process.exit(0));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = app;
