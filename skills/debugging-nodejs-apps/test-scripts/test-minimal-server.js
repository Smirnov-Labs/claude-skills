#!/usr/bin/env node
/**
 * Minimal Node.js HTTP Server Test
 *
 * Use this to verify basic Node.js functionality works.
 * If this fails, the issue is with Node.js installation or environment.
 * If this works but your app doesn't, the issue is with your app code/config.
 */

import http from 'http';

const PORT = process.env.PORT || 3000;

console.log('Starting minimal HTTP server test...');
console.log('Node.js version:', process.version);
console.log('Platform:', process.platform);
console.log('Arch:', process.arch);

const server = http.createServer((req, res) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'ok',
    timestamp: new Date().toISOString(),
    message: 'Minimal server works!'
  }));
});

server.listen(PORT, () => {
  console.log(`✓ Server listening on http://localhost:${PORT}`);
  console.log(`Test with: curl http://localhost:${PORT}`);
});

server.on('error', (err) => {
  console.error('✗ Server error:', err.message);
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use.`);
    console.error(`Try: lsof -i :${PORT}`);
  }
  process.exit(1);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
