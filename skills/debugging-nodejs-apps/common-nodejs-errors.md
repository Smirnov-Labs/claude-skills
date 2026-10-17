# Common Node.js Errors Catalog

Comprehensive reference for Node.js error messages and their solutions.

## Module System Errors

### `Error [ERR_REQUIRE_ESM]: require() of ES Module not supported`

**Cause:** Trying to use `require()` to load an ESM module

**Solution:**
```javascript
// Option 1: Convert to ESM import
import pkg from 'package-name';

// Option 2: Use dynamic import
const pkg = await import('package-name');

// Option 3: Add "type": "commonjs" and use .mjs for ESM files
```

### `SyntaxError: Cannot use import statement outside a module`

**Cause:** Using ESM `import` in CommonJS context

**Solution:**
```json
// Add to package.json:
{
  "type": "module"
}
```

OR rename file from `.js` to `.mjs`

### `Error [ERR_MODULE_NOT_FOUND]: Cannot find module`

**Cause:** Module not installed or wrong path

**Investigation:**
```bash
# Check if installed
npm ls package-name

# Check typo in name
npm search package-name

# Verify path for local imports
ls -la ./src/your-module.js
```

**Solution:**
```bash
npm install package-name

# For local imports, check relative path:
# import { x } from './file.js';  // Need .js extension in ESM!
```

### `Error [ERR_UNKNOWN_FILE_EXTENSION]: Unknown file extension ".ts"`

**Cause:** Trying to run TypeScript directly

**Solution:**
```bash
# Option 1: Compile first
npm run build
node dist/index.js

# Option 2: Use tsx/ts-node
npx tsx src/index.ts

# Option 3: Add loader (Node 20.6+)
node --loader ts-node/esm src/index.ts
```

## Network & Port Errors

### `Error: listen EADDRINUSE: address already in use :::3000`

**Cause:** Port already occupied

**Investigation:**
```bash
lsof -i :3000
# OR
ss -tulpn | grep :3000
```

**Solutions:**
```bash
# Kill the process
kill -9 <PID>

# Or use different port
PORT=3001 node src/index.js

# Or find and kill all node processes
pkill -f node
```

### `Error: connect ECONNREFUSED 127.0.0.1:5432`

**Cause:** Can't connect to service (database, API, etc.)

**Investigation:**
```bash
# Check if service is running
nc -zv localhost 5432

# Check if it's a different host
ping your-database-host

# Check firewall
sudo iptables -L | grep 5432
```

**Solutions:**
- Start the service (e.g., `sudo systemctl start postgresql`)
- Check host/port in connection string
- Verify credentials
- Check network connectivity

### `Error: getaddrinfo ENOTFOUND`

**Cause:** DNS resolution failed

**Investigation:**
```bash
# Test DNS resolution
nslookup your-hostname
dig your-hostname

# Check /etc/hosts
cat /etc/hosts | grep your-hostname
```

**Solutions:**
- Verify hostname is correct
- Check internet connectivity
- Add to /etc/hosts if needed
- Use IP address directly

## Database Errors

### PostgreSQL: `error: password authentication failed`

**Investigation:**
```bash
# Check connection string format
# postgresql://user:password@host:port/database

# Test with psql
psql -h localhost -U username -d database
```

**Solutions:**
- Verify username and password
- Check pg_hba.conf for auth method
- Ensure user has access to database

### PostgreSQL: `error: database "xyz" does not exist`

**Solutions:**
```bash
# Create database
psql -U postgres -c "CREATE DATABASE xyz;"

# Or check if different database name
psql -U postgres -l
```

### `MongoNetworkError: failed to connect to server`

**Investigation:**
```bash
# Check MongoDB is running
sudo systemctl status mongod

# Test connection
mongosh --host localhost --port 27017
```

**Solutions:**
- Start MongoDB: `sudo systemctl start mongod`
- Check connection string
- Verify network access

## Environment & Configuration Errors

### `TypeError: Cannot read property 'X' of undefined`

**Cause:** Environment variable not set

**Investigation:**
```bash
# Check env vars
node -e "console.log(process.env.YOUR_VAR)"

# List all env references in code
grep -r "process.env" src/ | cut -d: -f2 | sort -u
```

**Solutions:**
```bash
# Create .env file
cat > .env << 'EOF'
YOUR_VAR=value
OTHER_VAR=value2
EOF

# Load with dotenv
npm install dotenv
```

```javascript
// At top of entry file
import 'dotenv/config';
// or
require('dotenv').config();
```

### `ReferenceError: __dirname is not defined`

**Cause:** `__dirname` doesn't exist in ESM

**Solution:**
```javascript
// ESM equivalent
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
```

## Memory & Performance Errors

### `FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory`

**Cause:** Application exceeded default memory limit (usually 2GB)

**Solutions:**
```bash
# Increase heap size
node --max-old-space-size=4096 src/index.js

# Or in package.json
{
  "scripts": {
    "start": "node --max-old-space-size=4096 src/index.js"
  }
}
```

**Investigation:**
- Check for memory leaks
- Use heap snapshots
- Profile memory usage

### `MaxListenersExceededWarning: Possible EventEmitter memory leak detected`

**Cause:** Too many listeners on EventEmitter

**Investigation:**
```javascript
// Check listener count
emitter.listenerCount('eventName');
```

**Solutions:**
```javascript
// Increase limit if intentional
emitter.setMaxListeners(20);

// Or remove listeners when done
emitter.removeListener('event', handler);

// Use .once() instead of .on() if appropriate
emitter.once('event', handler);
```

## Async & Promise Errors

### `UnhandledPromiseRejectionWarning: Unhandled promise rejection`

**Cause:** Promise rejected without catch handler

**Solutions:**
```javascript
// Always catch promises
someAsyncFunction()
  .catch(err => console.error('Error:', err));

// Or use try/catch with async/await
try {
  await someAsyncFunction();
} catch (err) {
  console.error('Error:', err);
}

// Global handler (not recommended as main solution)
process.on('unhandledRejection', (err) => {
  console.error('Unhandled rejection:', err);
});
```

### `Error: Cannot find module './config.json'` (intermittent)

**Cause:** Race condition with file system or build process

**Investigation:**
- Check if file exists: `ls -la config.json`
- Check file permissions
- Verify build completes before start

**Solutions:**
```javascript
// Add delays if needed
import { setTimeout } from 'timers/promises';
await setTimeout(1000);

// Or wait for file
import { access } from 'fs/promises';
while (true) {
  try {
    await access('./config.json');
    break;
  } catch {
    await setTimeout(100);
  }
}
```

## Dependency & Build Errors

### `npm ERR! peer dep missing`

**Cause:** Peer dependency not installed

**Solution:**
```bash
# Install the missing peer dependency
npm install peer-package-name

# Or use --legacy-peer-deps
npm install --legacy-peer-deps
```

### `Error: Cannot find module 'node:crypto'`

**Cause:** Node.js version too old (node: prefix requires Node 14.18+)

**Solutions:**
```bash
# Update Node.js
nvm install --lts
nvm use --lts

# Or remove 'node:' prefix
// import crypto from 'node:crypto';
import crypto from 'crypto';
```

### `gyp ERR! build error` (native modules)

**Cause:** Can't compile native dependencies

**Investigation:**
```bash
# Check build tools
npm config get python
which python3

# Check compiler
gcc --version
g++ --version
```

**Solutions:**
```bash
# Install build tools (Ubuntu/Debian)
sudo apt-get install build-essential python3

# macOS
xcode-select --install

# Windows
npm install --global windows-build-tools

# Or use pre-built binaries
npm rebuild
npm install --build-from-source
```

## Framework-Specific Errors

### Express: `Error: Cannot set headers after they are sent`

**Cause:** Trying to send response twice

**Solution:**
```javascript
// Bad - sends multiple responses
app.get('/', (req, res) => {
  res.json({ data: 'first' });
  res.json({ data: 'second' }); // ERROR
});

// Good - only one response
app.get('/', (req, res) => {
  res.json({ data: 'first' });
  return; // Exit early
});

// Good - use early returns
app.get('/', (req, res) => {
  if (error) {
    return res.status(400).json({ error: 'Bad request' });
  }
  res.json({ data: 'success' });
});
```

### Fastify: `Error: Promise may not be fulfilled with 'undefined'`

**Cause:** Route handler returns undefined with async

**Solution:**
```javascript
// Bad
app.get('/', async (request, reply) => {
  reply.send({ data: 'ok' });
  // Returns undefined
});

// Good - return reply
app.get('/', async (request, reply) => {
  return reply.send({ data: 'ok' });
});

// Good - return data directly
app.get('/', async (request, reply) => {
  return { data: 'ok' };
});
```

## Debugging Commands Reference

```bash
# Check syntax without running
node --check file.js

# Run with warnings
node --trace-warnings file.js

# Run with deprecation traces
node --trace-deprecation file.js

# Inspect mode
node --inspect file.js

# Break at start
node --inspect-brk file.js

# Check import resolution
node --trace-modules file.js

# Expose garbage collector
node --expose-gc file.js

# Increase stack trace limit
node --stack-trace-limit=100 file.js
```

## Quick Diagnosis Decision Tree

```
1. Does the file load?
   → node --check file.js
   NO → Fix syntax errors

2. Are dependencies installed?
   → npm ls
   NO → npm install

3. Is it a module system issue?
   → Check import vs require
   → Check package.json "type" field
   → Check file extensions

4. Is it a network issue?
   → nc -zv host port
   → Check connection strings
   → Verify services running

5. Is it a configuration issue?
   → Check env vars exist
   → Verify config file paths
   → Test with minimal config

6. Still stuck?
   → Create minimal reproduction
   → Add extensive logging
   → Test components in isolation
```
