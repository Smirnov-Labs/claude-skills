# Node.js Debugging Checklist

Step-by-step checklist to systematically debug Node.js applications. Check off items as you complete them.

## Pre-Flight Checks

Before starting to debug, gather information:

- [ ] **Capture full error output**
  ```bash
  npm start 2>&1 | tee error.log
  ```

- [ ] **Note Node.js version**
  ```bash
  node --version
  ```

- [ ] **Check package.json exists and is valid**
  ```bash
  cat package.json
  ```

- [ ] **Identify the entry point**
  - Check `package.json` "main" field
  - Check `package.json` "start" script
  - Note: `src/index.js` or `dist/index.js` or other

## Phase 1: Environment Validation

- [ ] **Node.js version compatible**
  - Check package.json "engines" field
  - Verify minimum version met
  - Consider using nvm if version mismatch

- [ ] **Dependencies installed**
  ```bash
  ls node_modules/ | wc -l
  # Should be > 0 if dependencies exist
  ```

- [ ] **No dependency errors**
  ```bash
  npm ls 2>&1 | grep -i "error\|missing"
  # Should show no errors
  ```

- [ ] **Lock file present**
  ```bash
  ls package-lock.json  # npm
  ls yarn.lock          # yarn
  ls pnpm-lock.yaml     # pnpm
  ```

- [ ] **package.json and lock file in sync**
  ```bash
  npm ci  # Reinstall from lock file
  ```

## Phase 2: File System Validation

- [ ] **Entry file exists**
  ```bash
  ls -la src/index.js  # or your entry point
  ```

- [ ] **All imported files exist**
  ```bash
  # Check for broken imports
  node --check src/index.js
  ```

- [ ] **File permissions correct**
  ```bash
  ls -la src/
  # Should be readable (r--)
  ```

- [ ] **No conflicting file extensions**
  ```bash
  # Check for .js, .mjs, .cjs, .ts mix
  find src/ -type f -name "*.?js" -o -name "*.ts"
  ```

## Phase 3: Module System Validation

- [ ] **Check package.json "type" field**
  ```bash
  cat package.json | grep '"type"'
  # "type": "module" → ESM
  # "type": "commonjs" or missing → CommonJS
  ```

- [ ] **Import/require matches module type**
  - ESM: Uses `import`/`export`
  - CommonJS: Uses `require()`/`module.exports`

- [ ] **ESM imports include file extensions**
  ```javascript
  // ESM - MUST have .js extension
  import { x } from './file.js';  // ✓
  import { x } from './file';     // ✗ May fail
  ```

- [ ] **No mixing require() and import in same file**
  - Exception: Dynamic `await import()` is OK

- [ ] **Check for circular dependencies**
  ```bash
  node --trace-warnings src/index.js 2>&1 | grep -i circular
  ```

## Phase 4: Configuration Validation

- [ ] **Environment variables defined**
  ```bash
  # Check what's needed
  grep -rh "process.env\." src/ | sed 's/.*process\.env\.//; s/[^A-Z_].*//' | sort -u
  ```

- [ ] **Create/verify .env file**
  ```bash
  cat .env
  # Should contain all required variables
  ```

- [ ] **dotenv loaded if needed**
  ```javascript
  // At top of entry file
  import 'dotenv/config';  // ESM
  // or
  require('dotenv').config();  // CommonJS
  ```

- [ ] **Config files exist and are readable**
  ```bash
  ls -la *.config.js *.config.json .env
  ```

- [ ] **No conflicting environment variables**
  ```bash
  env | grep -E "NODE_ENV|PORT|DATABASE"
  ```

## Phase 5: Network & Services Validation

- [ ] **Port not already in use**
  ```bash
  lsof -i :3000  # or your port
  # Should show "command not found" or empty
  ```

- [ ] **Database/external services reachable**
  ```bash
  # PostgreSQL example
  nc -zv localhost 5432

  # Generic TCP test
  nc -zv <host> <port>
  ```

- [ ] **Database credentials correct**
  ```bash
  # Test PostgreSQL connection
  psql -h localhost -U user -d database -c "SELECT 1"
  ```

- [ ] **Connection strings valid**
  - Format: `protocol://user:pass@host:port/database`
  - No typos in hostname
  - Port number correct

- [ ] **Firewall not blocking connections**
  ```bash
  # Check if port is accessible
  telnet localhost 3000
  ```

## Phase 6: Syntax & Load Validation

- [ ] **No syntax errors**
  ```bash
  node --check src/index.js
  # Should exit silently with code 0
  ```

- [ ] **File actually loads**
  ```bash
  node -e "require('./src/index.js')"  # CommonJS
  node --input-type=module -e "import('./src/index.js')"  # ESM
  ```

- [ ] **No immediate crashes**
  ```bash
  timeout 5 node src/index.js
  # Should run for 5 seconds without crashing
  ```

## Phase 7: Minimal Service Test

- [ ] **Create minimal test script**
  ```javascript
  // test-minimal.js
  console.log('✓ Node.js works');
  console.log('✓ Version:', process.version);

  import('./src/index.js')
    .then(() => console.log('✓ Module loads'))
    .catch(err => console.error('✗ Load failed:', err));
  ```

- [ ] **Test minimal server (if web service)**
  ```javascript
  // test-server.js
  import http from 'http';

  const server = http.createServer((req, res) => {
    res.writeHead(200);
    res.end('OK');
  });

  server.listen(3000, () => {
    console.log('✓ Minimal server running on :3000');
  });
  ```

- [ ] **Verify response**
  ```bash
  curl http://localhost:3000
  # Should return "OK"
  ```

## Phase 8: Progressive Debugging

- [ ] **Start with maximum logging**
  ```bash
  DEBUG=* node src/index.js
  # or
  NODE_ENV=development node src/index.js
  ```

- [ ] **Enable all warnings**
  ```bash
  node --trace-warnings --trace-deprecation src/index.js
  ```

- [ ] **Use inspect mode if needed**
  ```bash
  node --inspect-brk src/index.js
  # Then open chrome://inspect in Chrome
  ```

- [ ] **Add console.log statements progressively**
  ```javascript
  console.log('1. Starting...');
  console.log('2. Loading config...');
  console.log('3. Connecting to database...');
  console.log('4. Starting server...');
  ```

## Phase 9: Component Isolation

If service still won't start, isolate components:

- [ ] **Comment out database connection**
  - Can service start without DB?

- [ ] **Comment out external API calls**
  - Can service start without external dependencies?

- [ ] **Test database separately**
  ```javascript
  // test-db.js
  import postgres from 'postgres';

  const sql = postgres(process.env.DATABASE_URL);
  const result = await sql`SELECT NOW()`;
  console.log('✓ Database works:', result);
  await sql.end();
  ```

- [ ] **Test each module independently**
  ```bash
  # Test individual files
  node --check src/routes/users.js
  node --check src/services/auth.js
  ```

## Phase 10: Dependency Issues

If you suspect dependency issues:

- [ ] **Clean install**
  ```bash
  rm -rf node_modules package-lock.json
  npm install
  ```

- [ ] **Check for peer dependency issues**
  ```bash
  npm ls 2>&1 | grep "UNMET"
  ```

- [ ] **Check for conflicting versions**
  ```bash
  npm ls <package-name>
  # Should show single version tree
  ```

- [ ] **Try with different package manager**
  ```bash
  # If using npm, try yarn
  rm -rf node_modules
  yarn install
  ```

- [ ] **Check for platform-specific builds**
  ```bash
  npm rebuild
  # Rebuilds native modules
  ```

## Phase 11: Fresh Start Test

Verify fix works from clean slate:

- [ ] **Kill all Node processes**
  ```bash
  pkill -f node
  ```

- [ ] **Clear port**
  ```bash
  lsof -ti:3000 | xargs kill -9
  ```

- [ ] **Fresh dependency install**
  ```bash
  rm -rf node_modules package-lock.json
  npm install
  ```

- [ ] **Start service**
  ```bash
  npm start
  ```

- [ ] **Verify service responds**
  ```bash
  curl http://localhost:3000/health
  # or
  curl http://localhost:3000/
  ```

- [ ] **Check logs for errors**
  ```bash
  tail -f logs/*.log
  # or check console output
  ```

- [ ] **Test service restart**
  ```bash
  # Stop and start again
  pkill -f "node.*index.js"
  npm start
  ```

## Phase 12: Documentation

Once fixed, document the solution:

- [ ] **Write down what the problem was**
  - Error message
  - Root cause
  - What was actually wrong

- [ ] **Document the solution**
  - What changes fixed it
  - Why the fix works
  - How to prevent in the future

- [ ] **Update project documentation**
  - Add to README if setup-related
  - Update .env.example if env vars needed
  - Add troubleshooting section

- [ ] **Create reproduction test**
  - Can you trigger the error again?
  - Write a test to prevent regression

## Common Gotchas Checklist

Quick checks for frequent issues:

- [ ] Port 3000 not in use (`lsof -i :3000`)
- [ ] `.env` file exists and loaded
- [ ] `node_modules/` exists and populated
- [ ] Entry file path correct in package.json
- [ ] Database actually running
- [ ] Correct Node.js version (`node --version`)
- [ ] No syntax errors (`node --check src/index.js`)
- [ ] Import paths include `.js` extension (for ESM)
- [ ] No mixed `require()` and `import`
- [ ] `package.json` "type" field set correctly

## Emergency Reset Procedure

If completely stuck, nuclear option:

```bash
# 1. Stop everything
pkill -f node

# 2. Clean project
rm -rf node_modules package-lock.json
git clean -fdx  # WARNING: Removes all untracked files

# 3. Fresh install
npm install

# 4. Verify package.json scripts
cat package.json | grep -A 10 '"scripts"'

# 5. Try minimal start
node src/index.js

# 6. If that works, try npm start
npm start
```

## When to Ask for Help

You've exhausted systematic debugging if:

- [ ] Completed all checklist items above
- [ ] Created minimal reproduction
- [ ] Isolated each component
- [ ] Tested with fresh install
- [ ] Documented all attempts
- [ ] Error message is unclear even after investigation

At this point, gather:
- Full error output (`error.log`)
- Node.js version
- Package.json
- Minimal reproduction
- What you've tried
