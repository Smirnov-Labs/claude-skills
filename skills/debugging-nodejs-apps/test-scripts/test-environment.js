#!/usr/bin/env node
/**
 * Environment Test Script
 *
 * Validates environment variables and configuration.
 * Run this to check if your environment is properly configured.
 */

import { readFile } from 'fs/promises';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

console.log('Environment Configuration Test\n');
console.log('='.repeat(50));

// Step 1: Node.js Environment
console.log('\n1. Node.js Environment');
console.log('-'.repeat(50));
console.log(`   Version: ${process.version}`);
console.log(`   Platform: ${process.platform}`);
console.log(`   Architecture: ${process.arch}`);
console.log(`   Process ID: ${process.pid}`);
console.log(`   Working Directory: ${process.cwd()}`);
console.log(`   User: ${process.env.USER || process.env.USERNAME}`);

// Step 2: Required Environment Variables
console.log('\n2. Environment Variables');
console.log('-'.repeat(50));

// Try to detect required vars from package.json or common patterns
const commonVars = [
  'NODE_ENV',
  'PORT',
  'DATABASE_URL',
  'DB_HOST',
  'DB_PORT',
  'DB_NAME',
  'DB_USER',
  'DB_PASSWORD',
  'API_KEY',
  'SECRET_KEY',
  'JWT_SECRET',
  'REDIS_URL',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY'
];

let foundVars = 0;
let missingVars = [];

commonVars.forEach(varName => {
  const value = process.env[varName];
  if (value !== undefined) {
    foundVars++;
    // Mask sensitive values
    const isSensitive = varName.toLowerCase().includes('secret') ||
                       varName.toLowerCase().includes('password') ||
                       varName.toLowerCase().includes('key');
    const displayValue = isSensitive ? '***' : value;
    console.log(`   ✓ ${varName}=${displayValue}`);
  } else {
    missingVars.push(varName);
  }
});

if (missingVars.length > 0) {
  console.log(`\n   Common missing variables (may not be required):`);
  missingVars.forEach(v => console.log(`   ○ ${v}`));
}

// Step 3: Check for .env file
console.log('\n3. Environment Files');
console.log('-'.repeat(50));

const envFiles = ['.env', '.env.local', '.env.development', '.env.production'];
for (const envFile of envFiles) {
  try {
    await readFile(envFile, 'utf-8');
    console.log(`   ✓ ${envFile} exists`);
  } catch {
    console.log(`   ○ ${envFile} not found`);
  }
}

// Step 4: Check package.json
console.log('\n4. Package Configuration');
console.log('-'.repeat(50));

try {
  const pkgJson = JSON.parse(await readFile('package.json', 'utf-8'));

  console.log(`   Name: ${pkgJson.name || 'not set'}`);
  console.log(`   Version: ${pkgJson.version || 'not set'}`);
  console.log(`   Type: ${pkgJson.type || 'commonjs (default)'}`);
  console.log(`   Main: ${pkgJson.main || 'index.js (default)'}`);

  if (pkgJson.engines) {
    console.log(`   Required Node: ${pkgJson.engines.node || 'any'}`);
  }

  if (pkgJson.scripts) {
    console.log('\n   Available scripts:');
    Object.keys(pkgJson.scripts).forEach(script => {
      console.log(`     - npm run ${script}`);
    });
  }

  // Check for dotenv
  const hasDotenv = pkgJson.dependencies?.dotenv ||
                    pkgJson.devDependencies?.dotenv;
  if (hasDotenv) {
    console.log('\n   ✓ dotenv package installed');
  } else {
    console.log('\n   ○ dotenv not installed (install with: npm install dotenv)');
  }

} catch (err) {
  console.log('   ✗ package.json not found or invalid');
}

// Step 5: Memory and Limits
console.log('\n5. System Resources');
console.log('-'.repeat(50));

const memUsage = process.memoryUsage();
console.log(`   Heap Used: ${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`);
console.log(`   Heap Total: ${Math.round(memUsage.heapTotal / 1024 / 1024)}MB`);
console.log(`   External: ${Math.round(memUsage.external / 1024 / 1024)}MB`);
console.log(`   RSS: ${Math.round(memUsage.rss / 1024 / 1024)}MB`);

// Step 6: Network Checks
console.log('\n6. Network Configuration');
console.log('-'.repeat(50));

const port = process.env.PORT || 3000;
console.log(`   Default Port: ${port}`);

// Try to detect if port is in use
import { createServer } from 'net';

const testPort = (portNum) => {
  return new Promise((resolve) => {
    const server = createServer();
    server.once('error', (err) => {
      if (err.code === 'EADDRINUSE') {
        resolve(false);
      } else {
        resolve(null);
      }
    });
    server.once('listening', () => {
      server.close();
      resolve(true);
    });
    server.listen(portNum);
  });
};

const portAvailable = await testPort(port);
if (portAvailable === true) {
  console.log(`   ✓ Port ${port} is available`);
} else if (portAvailable === false) {
  console.log(`   ✗ Port ${port} is already in use`);
  console.log(`      Check with: lsof -i :${port}`);
} else {
  console.log(`   ? Could not test port ${port}`);
}

// Summary
console.log('\n' + '='.repeat(50));
console.log('Summary');
console.log('='.repeat(50));

if (foundVars > 0) {
  console.log(`✓ Found ${foundVars} environment variables`);
}

if (missingVars.length === commonVars.length) {
  console.log('○ No common environment variables found');
  console.log('  This may be fine if your app doesn\'t need them');
}

console.log('\nNext steps:');
console.log('  1. Ensure all required environment variables are set');
console.log('  2. Create .env file if needed');
console.log('  3. Verify package.json scripts are correct');
console.log('  4. Test with: npm start');
