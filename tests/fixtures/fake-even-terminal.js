#!/usr/bin/env node
// Minimal fake even-terminal HTTP server for tests.
// - Logs CLI args, BRIDGE_TOKEN, PORT env vars to stdout
// - Listens on --port or PORT env var (default 3456)
// - Responds to GET / with {"server":"even-terminal-fake","version":"test"}
// - Prints "READY port=<N>" to stdout once listening

'use strict';

const http = require('http');

const argv = process.argv.slice(2);
console.log('ARGS=' + JSON.stringify(argv));
console.log('ENV_BRIDGE_TOKEN=' + (process.env.BRIDGE_TOKEN || ''));
console.log('ENV_PORT=' + (process.env.PORT || ''));

function parsePort(args) {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--port' && i + 1 < args.length) {
      const n = parseInt(args[i + 1], 10);
      if (!Number.isNaN(n)) return n;
    }
    if (args[i].startsWith('--port=')) {
      const n = parseInt(args[i].split('=', 2)[1], 10);
      if (!Number.isNaN(n)) return n;
    }
  }
  if (process.env.PORT) {
    const n = parseInt(process.env.PORT, 10);
    if (!Number.isNaN(n)) return n;
  }
  return 3456;
}

function parseBind(args) {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--bind' && i + 1 < args.length) {
      return args[i + 1];
    }
    if (args[i].startsWith('--bind=')) {
      return args[i].split('=', 2)[1];
    }
  }
  return '127.0.0.1';
}

const port = parsePort(argv);
const bindIp = parseBind(argv);

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && (req.url === '/' || req.url === '')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ server: 'even-terminal-fake', version: 'test' }));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

server.on('error', (err) => {
  console.error('SERVER_ERROR=' + err.message);
  process.exit(2);
});

server.listen(port, bindIp, () => {
  console.log('READY port=' + port + ' bind=' + bindIp);
});

function shutdown() {
  try {
    server.close(() => process.exit(0));
  } catch (_) {
    process.exit(0);
  }
  setTimeout(() => process.exit(0), 1000).unref();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
