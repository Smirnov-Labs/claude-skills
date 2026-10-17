---
name: debugging-nodejs-apps
description: Use this skill when debugging Node.js applications, fixing service startup issues, resolving npm/dependency errors, troubleshooting runtime failures, investigating connection problems, or when stuck on seemingly simple Node.js issues. This includes analyzing error messages, testing services systematically, checking configuration, and breaking out of debugging local minimums with fresh systematic approaches.
---

# Node.js Application Debugging Expert

Systematically debug Node.js applications using methodical investigation, avoiding local minimums through structured problem-solving approaches.

## Core Philosophy: Escape Local Minimums

When debugging Node.js apps, it's easy to get stuck trying the same approaches repeatedly. This skill provides systematic workflows to break out of those loops.

**Red Flags You're in a Local Minimum:**
- Trying the same fix repeatedly with slight variations
- Not validating basic assumptions (e.g., "is the service actually running?")
- Skipping verification steps
- Making multiple changes without testing each one
- Not checking logs systematically

**How to Escape:**
1. Stop and reset
2. Start from first principles
3. Validate every assumption
4. Test one thing at a time
5. Document what you've tried

## Systematic Debugging Workflow

### Phase 1: Initial Triage

Before making any changes, gather complete context:

1. **Capture the Full Error**
   ```bash
   # Run the service and capture ALL output
   npm start 2>&1 | tee service-error.log
   # OR
   node src/index.js 2>&1 | tee error.log
   ```

2. **Check Basic Assumptions**
   ```bash
   # Node version
   node --version

   # Verify package.json exists
   cat package.json

   # Check if dependencies are installed
   ls -la node_modules/ | head -20

   # Verify the entry point exists
   ls -la src/index.js  # or whatever the main file is
   ```

3. **Understand the Stack**
   - What framework? (Express, Fastify, Koa, vanilla Node)
   - What dependencies are critical?
   - Any environment variables required?
   - Database connections needed?

### Phase 2: Systematic Investigation

Work through these steps **in order**, validating each before moving to the next:

#### Step 1: Validate Dependencies

```bash
# Check for missing dependencies
npm ls 2>&1 | grep -i "missing\|error"

# Fresh install if suspicious
rm -rf node_modules package-lock.json
npm install

# Check for peer dependency issues
npm ls --all 2>&1 | grep -i "unmet"
```

**Common Issues:**
- Peer dependencies not installed
- Version conflicts
- Missing optional dependencies that are actually required
- Platform-specific builds (bcrypt, sharp, etc.)

#### Step 2: Validate Configuration

```bash
# Check for required env vars
cat .env 2>/dev/null || echo "No .env file"

# Check env var usage in code
grep -r "process.env" src/ | head -20

# Verify config files
ls -la *.config.js *.config.json 2>/dev/null
```

**Common Issues:**
- Missing .env file
- ENV vars not loaded (need dotenv?)
- Wrong database connection strings
- Port conflicts

#### Step 3: Validate Entry Point

```bash
# Check package.json scripts
cat package.json | grep -A 5 '"scripts"'

# Verify main/start file exists
node -e "const pkg = require('./package.json'); console.log('Main:', pkg.main || 'index.js')"

# Test file can be loaded (syntax check)
node --check src/index.js
```

**Common Issues:**
- Wrong file path in package.json
- Syntax errors preventing load
- Missing file extensions in ESM
- Import/require mismatches

#### Step 4: Test Minimal Service

Create a minimal test to isolate the issue:

```javascript
// test-minimal.js
console.log('Node version:', process.version);
console.log('Starting minimal test...');

// Test basic import/require
try {
  // For ESM
  // import { something } from './src/index.js';

  // For CommonJS
  const main = require('./src/index.js');
  console.log('✓ Main file loads successfully');
} catch (error) {
  console.error('✗ Failed to load:', error.message);
  console.error('Stack:', error.stack);
}

console.log('Test complete');
```

Run it:
```bash
node test-minimal.js
```

#### Step 5: Progressive Service Start

Start the service with increasing complexity:

```bash
# 1. Can we load the file?
node --check src/index.js

# 2. Can we run it?
node src/index.js

# 3. With environment
NODE_ENV=development node src/index.js

# 4. With debugging
NODE_OPTIONS='--inspect' node src/index.js

# 5. With full logging
DEBUG=* node src/index.js
```

### Phase 3: Common Node.js Failure Modes

#### ESM vs CommonJS Issues

**Symptoms:**
- `require is not defined in ES module scope`
- `Cannot use import statement outside a module`
- `Unknown file extension ".ts"`

**Investigation:**
```bash
# Check package.json type
cat package.json | grep '"type"'

# Check file extensions
ls -la src/*.js src/*.mjs src/*.cjs 2>/dev/null

# Check imports in main file
head -20 src/index.js | grep -E "import |require\("
```

**Fixes:**
- ESM requires `"type": "module"` in package.json OR `.mjs` extension
- CommonJS requires `"type": "commonjs"` OR `.cjs` extension OR no type field
- Can't mix `require()` and `import` in same file without workarounds

#### Port Already in Use

**Symptoms:**
- `EADDRINUSE`
- `address already in use`

**Investigation:**
```bash
# Find what's using the port (e.g., 3000)
lsof -i :3000
# OR
ss -tulpn | grep :3000
# OR
netstat -tulpn | grep :3000

# Kill the process
kill -9 <PID>

# Or change the port
PORT=3001 node src/index.js
```

#### Database Connection Failures

**Symptoms:**
- `ECONNREFUSED`
- `Connection timeout`
- `Authentication failed`

**Investigation:**
```bash
# Test database is reachable
# For PostgreSQL:
pg_isready -h localhost -p 5432

# For generic TCP:
nc -zv localhost 5432

# Check connection string
grep -r "DATABASE\|DB_" .env src/

# Test direct connection
psql -h localhost -p 5432 -U username -d database
```

**Fixes:**
- Verify database is actually running
- Check credentials match
- Ensure host/port are correct
- Check firewall/network connectivity

#### Missing Environment Variables

**Symptoms:**
- `undefined is not a function`
- Cryptic errors with no stack trace
- Service starts but fails on first request

**Investigation:**
```bash
# List all env var references
grep -rh "process.env\." src/ | sort -u

# Check which are set
node -e "console.log(process.env)" | grep -E "DB|API|PORT|SECRET"

# Create env template
grep -rh "process.env\." src/ | sed 's/.*process\.env\.//; s/[^A-Z_].*//' | sort -u
```

**Fix Template:**
```bash
# Create .env file with required vars
cat > .env << 'EOF'
NODE_ENV=development
PORT=3000
DATABASE_URL=postgresql://user:pass@localhost:5432/db
API_KEY=your_key_here
EOF
```

#### Async/Import Timing Issues

**Symptoms:**
- Works sometimes, fails other times
- Race conditions
- "Cannot access before initialization"

**Investigation:**
- Check for top-level await usage
- Look for initialization order dependencies
- Check for circular imports

```bash
# Find top-level awaits
grep -r "^await\|^const.*await" src/

# Find circular dependencies (Node.js has built-in detection)
node --trace-warnings src/index.js
```

### Phase 4: Verification & Testing

After fixing, verify systematically:

```bash
# 1. Clean start
pkill -f "node.*index.js"
rm -rf node_modules package-lock.json
npm install

# 2. Start service
npm start &
SERVICE_PID=$!

# 3. Wait for startup
sleep 3

# 4. Test basic endpoint
curl http://localhost:3000/health || curl http://localhost:3000/

# 5. Check logs
tail -n 50 service-error.log

# 6. Stop service
kill $SERVICE_PID
```

## Debugging Tools & Commands

### Essential CLI Tools

```bash
# Process management
ps aux | grep node          # Find running Node processes
pkill -f "node"            # Kill all Node processes
lsof -i :PORT              # Find what's using a port

# Dependency investigation
npm ls package-name        # Check if package is installed
npm outdated              # Check for outdated packages
npm audit                 # Security vulnerabilities

# File system checks
find . -name "*.js" -type f | wc -l    # Count JS files
du -sh node_modules                    # Size of dependencies

# Network debugging
curl -v http://localhost:3000          # Test HTTP endpoint
nc -zv localhost PORT                   # Test TCP connection
nmap localhost -p 3000-3010            # Scan port range
```

### Node.js Debugging Flags

```bash
# Inspect mode (Chrome DevTools)
node --inspect src/index.js
node --inspect-brk src/index.js  # Break on start

# Stack trace settings
node --trace-warnings src/index.js
node --trace-uncaught src/index.js
node --trace-deprecation src/index.js

# Memory debugging
node --max-old-space-size=4096 src/index.js
node --expose-gc src/index.js

# Module resolution
node --trace-modules src/index.js
```

### Creating Debug Scripts

Add to package.json:

```json
{
  "scripts": {
    "start": "node src/index.js",
    "dev": "node --watch src/index.js",
    "debug": "node --inspect-brk src/index.js",
    "debug:trace": "node --trace-warnings --trace-uncaught src/index.js",
    "test:load": "node --check src/index.js",
    "clean": "rm -rf node_modules package-lock.json && npm install"
  }
}
```

## Escaping Common Local Minimums

### Local Minimum #1: "Just Try One More Time"

**Symptom:** Running the same command repeatedly hoping for different results

**Escape Strategy:**
1. Stop running the command
2. Add verbose logging to understand what's happening
3. Break the problem into smaller pieces
4. Test each piece independently

```bash
# Instead of:
npm start
npm start
npm start

# Do:
node --check src/index.js  # Syntax check first
node src/index.js 2>&1 | tee full-output.log  # Capture everything
cat full-output.log  # Read the FULL error, not just the last line
```

### Local Minimum #2: "The Config Must Be Wrong"

**Symptom:** Tweaking configuration values without understanding the error

**Escape Strategy:**
1. Test with absolute minimal config
2. Add config pieces one at a time
3. Verify each addition works

```javascript
// Minimal test - can we even start?
// test-minimal-server.js
import Fastify from 'fastify';

const app = Fastify({ logger: true });

app.get('/', async () => ({ status: 'ok' }));

try {
  await app.listen({ port: 3000 });
  console.log('✓ Minimal server started successfully');
  console.log('Visit: http://localhost:3000');
} catch (err) {
  console.error('✗ Minimal server failed:', err);
  process.exit(1);
}
```

### Local Minimum #3: "It's Probably the Database"

**Symptom:** Focusing on database when service won't even start

**Escape Strategy:**
1. Comment out ALL database code
2. Get service to start without database
3. Add database back incrementally

```javascript
// Temporarily disable database
// const db = await connectDatabase();
const db = null; // TEMPORARY: Testing without DB

// Later, test DB connection separately
import postgres from 'postgres';

const testConnection = async () => {
  try {
    const sql = postgres(process.env.DATABASE_URL);
    const result = await sql`SELECT NOW()`;
    console.log('✓ Database connected:', result);
    await sql.end();
  } catch (error) {
    console.error('✗ Database failed:', error.message);
  }
};

testConnection();
```

### Local Minimum #4: "Let Me Try Reinstalling Everything"

**Symptom:** Running `rm -rf node_modules && npm install` without understanding the issue

**Escape Strategy:**
1. Check if it's actually a dependency issue first
2. Look at the error message carefully
3. Only reinstall if you see dependency errors

```bash
# Before reinstalling, check:
npm ls 2>&1 | grep -i error  # Are there actual dependency errors?

# Check if the error is even dependency-related
node src/index.js 2>&1 | grep -i "cannot find module"

# If no module errors, reinstalling won't help!
```

## Troubleshooting Decision Tree

```
Service won't start
├─ Syntax error?
│  ├─ Run: node --check src/index.js
│  └─ Fix: Resolve syntax issues
├─ Module not found?
│  ├─ Check: npm ls <module>
│  ├─ Install: npm install <module>
│  └─ Verify: import/require path correct?
├─ Port in use?
│  ├─ Check: lsof -i :PORT
│  ├─ Kill: kill -9 <PID>
│  └─ Or change: PORT=3001 npm start
├─ Database connection failed?
│  ├─ Test: nc -zv localhost 5432
│  ├─ Verify: .env has correct connection string
│  └─ Check: Database actually running?
├─ Environment variables missing?
│  ├─ Check: grep "process.env" src/
│  └─ Create: .env file with required vars
└─ Still stuck?
   ├─ Create minimal reproduction
   ├─ Test each component separately
   └─ Add extensive logging
```

## Documentation & Reference

See supporting files for detailed information:
- `./common-nodejs-errors.md` - Detailed error catalog
- `./debugging-checklist.md` - Step-by-step checklist
- `./test-scripts/` - Reusable debugging scripts

## Success Checklist

Before declaring a fix complete:

- [ ] Service starts without errors
- [ ] Can make successful HTTP request (if web service)
- [ ] Database connects (if database-backed)
- [ ] Environment variables loaded correctly
- [ ] No error messages in logs
- [ ] Service survives restart
- [ ] Documented what the issue was and how you fixed it
