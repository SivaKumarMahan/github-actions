const { test } = require('node:test');
const assert = require('node:assert');
const app = require('../src/index');

test('GET / and GET /health respond with 200', async () => {
  const server = app.listen(0);
  const { port } = server.address();
  try {
    const home = await fetch(`http://127.0.0.1:${port}/`);
    assert.strictEqual(home.status, 200);
    assert.match(await home.text(), /Hello from GitHub Actions/);

    const health = await fetch(`http://127.0.0.1:${port}/health`);
    assert.strictEqual(health.status, 200);
    assert.deepStrictEqual(await health.json(), { status: 'ok' });
  } finally {
    server.close();
  }
});
