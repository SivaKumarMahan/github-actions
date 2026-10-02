const express = require('express');

const app = express();
const port = Number(process.env.PORT) || 3000;
// APP_MESSAGE comes from SSM Parameter Store (injected by the ECS task definition).
const message = process.env.APP_MESSAGE || 'Hello from ECS Fargate!';
const version = process.env.APP_VERSION || 'dev';

app.disable('x-powered-by');

app.get('/', (req, res) => res.send(message));

// ALB target group health check and container health check.
app.get('/health', (req, res) => res.json({ status: 'ok', version }));

if (require.main === module) {
  const server = app.listen(port, () => console.log(`Server running on port ${port}, version ${version}`));

  // ECS sends SIGTERM when it stops a task (rolling deploy or scale-in).
  const shutdown = (signal) => {
    console.log(`${signal} received, shutting down`);
    server.close(() => process.exit(0));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = app;
