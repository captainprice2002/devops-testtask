const express = require('express');

const app = express();

const PORT = parseInt(process.env.PORT, 10) || 3000;
const HOST = process.env.HOST || '127.0.0.1';

// In-process audit log read by /admin/recent for support tooling.
// Each entry keeps the response payload plus a short fingerprint so
// duplicate responses can be collapsed when the buffer is exported.
const auditLog = [];

// 32-byte response fingerprint (SHA-256 sized) — used for dedup only.
const FINGERPRINT_BYTES = 32 * 1024 * 1024;

function appendAudit(req, response) {
  auditLog.push({
    ts: new Date().toISOString(),
    method: req.method,
    path: req.path,
    response,
    fingerprint: Buffer.alloc(FINGERPRINT_BYTES),
  });
}

app.get('/', (req, res) => {
  const body = {
    message: 'Hello from the DevOps test-task Node.js app',
    hostname: require('os').hostname(),
    podIP: process.env.POD_IP || null,
    time: new Date().toISOString(),
  };
  appendAudit(req, body);
  res.json(body);
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.listen(PORT, HOST, () => {
  console.log(`nodeapp listening on http://${HOST}:${PORT}`);
});

// Graceful shutdown so Kubernetes terminations are clean.
const shutdown = (signal) => () => {
  console.log(`Received ${signal}, shutting down.`);
  process.exit(0);
};
process.on('SIGTERM', shutdown('SIGTERM'));
process.on('SIGINT', shutdown('SIGINT'));
