#!/usr/bin/env node
/**
 * Database Connection Test
 *
 * Tests database connectivity independently of application code.
 * Supports PostgreSQL. Adapt for other databases as needed.
 */

import { promisify } from 'util';
import { exec as execCallback } from 'child_process';

const exec = promisify(execCallback);

console.log('Testing database connection...\n');

// Get database URL from environment
const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('✗ DATABASE_URL environment variable not set');
  console.error('Set it with: export DATABASE_URL="postgresql://user:pass@host:port/db"');
  process.exit(1);
}

console.log('DATABASE_URL found (masked)');

// Parse connection string
let dbConfig;
try {
  const url = new URL(DATABASE_URL);
  dbConfig = {
    protocol: url.protocol.replace(':', ''),
    username: url.username,
    password: url.password ? '***' : 'none',
    host: url.hostname,
    port: url.port || '5432',
    database: url.pathname.slice(1)
  };

  console.log('Parsed configuration:');
  console.log(`  Protocol: ${dbConfig.protocol}`);
  console.log(`  Host: ${dbConfig.host}`);
  console.log(`  Port: ${dbConfig.port}`);
  console.log(`  Database: ${dbConfig.database}`);
  console.log(`  Username: ${dbConfig.username}`);
  console.log(`  Password: ${dbConfig.password}`);
  console.log();
} catch (err) {
  console.error('✗ Invalid DATABASE_URL format');
  console.error('Expected: postgresql://user:pass@host:port/database');
  process.exit(1);
}

// Test TCP connectivity first
console.log('Step 1: Testing TCP connectivity...');
try {
  const { stdout, stderr } = await exec(`nc -zv ${dbConfig.host} ${dbConfig.port} 2>&1`);
  console.log('✓ TCP connection successful');
  console.log(`  ${stdout.trim()}`);
} catch (err) {
  console.error('✗ TCP connection failed');
  console.error(`  Cannot reach ${dbConfig.host}:${dbConfig.port}`);
  console.error('  Possible causes:');
  console.error('    - Database service not running');
  console.error('    - Wrong host/port');
  console.error('    - Firewall blocking connection');
  process.exit(1);
}

// Test PostgreSQL-specific connection
console.log('\nStep 2: Testing PostgreSQL connection...');

try {
  // Dynamic import to avoid crash if pg not installed
  const { default: postgres } = await import('postgres');

  const sql = postgres(DATABASE_URL, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 5
  });

  console.log('Attempting database query...');
  const result = await sql`SELECT
    current_database() as database,
    current_user as user,
    version() as version,
    NOW() as current_time
  `;

  await sql.end();

  console.log('✓ Database connection successful!\n');
  console.log('Database info:');
  console.log(`  Database: ${result[0].database}`);
  console.log(`  User: ${result[0].user}`);
  console.log(`  Time: ${result[0].current_time}`);
  console.log(`  Version: ${result[0].version.split('\n')[0]}`);

} catch (err) {
  console.error('✗ Database connection failed');
  console.error(`  Error: ${err.message}`);
  console.error('\nPossible causes:');
  console.error('  - Wrong username/password');
  console.error('  - Database does not exist');
  console.error('  - User lacks permissions');
  console.error('  - SSL/TLS configuration issue');
  console.error('\nTroubleshooting:');
  console.error(`  Test with psql: psql "${DATABASE_URL}"`);
  console.error(`  List databases: psql -h ${dbConfig.host} -U ${dbConfig.username} -l`);
  process.exit(1);
}

console.log('\n✓ All database tests passed');
