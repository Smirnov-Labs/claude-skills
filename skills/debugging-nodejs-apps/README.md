# Node.js Application Debugging Skill

Systematic debugging skill for Node.js applications, designed to help Claude Code escape local minimums when debugging.

## When This Skill Activates

This skill automatically activates when you mention:
- Debugging Node.js apps
- Node.js service won't start
- npm/dependency errors
- Runtime failures
- Connection problems
- "Stuck" on Node.js issues

## What This Skill Provides

### 1. Systematic Debugging Workflow

A step-by-step approach that:
- Validates assumptions before making changes
- Tests one thing at a time
- Documents what's been tried
- Provides escape strategies from debugging loops

### 2. Common Error Catalog

Comprehensive reference of Node.js errors with:
- Error explanations
- Investigation commands
- Concrete solutions
- Example code fixes

See: `./common-nodejs-errors.md`

### 3. Debugging Checklist

Phase-by-phase checklist covering:
- Environment validation
- File system checks
- Module system validation
- Configuration verification
- Network & services testing

See: `./debugging-checklist.md`

### 4. Test Scripts

Ready-to-use diagnostic scripts:

```bash
# Test basic Node.js functionality
./test-scripts/test-minimal-server.js

# Test database connectivity
DATABASE_URL="postgresql://..." ./test-scripts/test-database-connection.js

# Validate environment configuration
./test-scripts/test-environment.js
```

## Quick Start

### Option 1: Let Claude Use the Skill

Just describe your issue:

```
My Node.js service won't start. Getting "Cannot find module" error.
```

Claude will automatically invoke this skill and follow systematic debugging.

### Option 2: Explicitly Use the Skill

```
debugging-nodejs-apps

I'm getting EADDRINUSE error when starting my Fastify app.
```

### Option 3: Use Test Scripts Directly

```bash
cd your-project/

# Test environment
~/.claude/skills/debugging-nodejs-apps/test-scripts/test-environment.js

# Test minimal server
~/.claude/skills/debugging-nodejs-apps/test-scripts/test-minimal-server.js

# Test database (requires postgres package)
DATABASE_URL="postgresql://user:pass@host/db" \
  ~/.claude/skills/debugging-nodejs-apps/test-scripts/test-database-connection.js
```

## Key Features

### Escape Local Minimums

Red flags you're stuck in a loop:
- Trying the same fix repeatedly
- Not validating basic assumptions
- Skipping verification steps
- Making multiple changes at once

Escape strategies:
1. Stop and reset
2. Start from first principles
3. Validate every assumption
4. Test one thing at a time

### Systematic Investigation

Progressive debugging phases:
1. Initial triage - Gather context
2. Systematic investigation - Step-by-step validation
3. Common failure modes - Recognize patterns
4. Verification & testing - Confirm fixes

### Decision Trees

Quick diagnosis paths for:
- Module system issues (ESM vs CommonJS)
- Port conflicts (EADDRINUSE)
- Database connection failures
- Missing environment variables
- Async/timing issues

## File Structure

```
debugging-nodejs-apps/
├── SKILL.md                           # Main skill instructions
├── README.md                          # This file
├── common-nodejs-errors.md            # Error catalog with solutions
├── debugging-checklist.md             # Phase-by-phase checklist
└── test-scripts/
    ├── test-minimal-server.js         # Test basic Node.js
    ├── test-database-connection.js    # Test DB connectivity
    └── test-environment.js            # Validate configuration
```

## Common Scenarios

### "My service won't start"

1. Claude captures full error output
2. Validates basic assumptions (Node version, dependencies installed)
3. Checks entry point exists
4. Tests minimal service
5. Progressively adds complexity

### "Getting module not found error"

1. Verifies module is installed (`npm ls`)
2. Checks import path syntax
3. Validates ESM vs CommonJS setup
4. Tests file extensions
5. Checks for circular dependencies

### "Port already in use"

1. Identifies process using port (`lsof -i :PORT`)
2. Provides kill command
3. Suggests alternative ports
4. Checks for multiple instances

### "Database connection failed"

1. Tests TCP connectivity (`nc -zv host port`)
2. Validates connection string format
3. Checks credentials
4. Tests database separately
5. Verifies service is running

## Best Practices

### Before Debugging

- Capture full error output with `2>&1 | tee error.log`
- Note Node.js version
- Check if dependencies are installed
- Identify the entry point

### During Debugging

- Validate each assumption
- Test one change at a time
- Document what you've tried
- Use diagnostic scripts to isolate issues

### After Fixing

- Verify from clean slate
- Test service restart
- Document the solution
- Update project documentation

## Integration with Your Projects

### Add to Project Scripts

In your `package.json`:

```json
{
  "scripts": {
    "debug:env": "node ~/.claude/skills/debugging-nodejs-apps/test-scripts/test-environment.js",
    "debug:server": "node ~/.claude/skills/debugging-nodejs-apps/test-scripts/test-minimal-server.js",
    "debug:db": "node ~/.claude/skills/debugging-nodejs-apps/test-scripts/test-database-connection.js"
  }
}
```

### Create Project Checklist

Copy the debugging checklist to your project:

```bash
cp ~/.claude/skills/debugging-nodejs-apps/debugging-checklist.md \
   your-project/.claude/debugging-checklist.md
```

## Troubleshooting the Skill Itself

### Skill not activating?

The skill activates on these keywords:
- "debugging node"
- "node.js won't start"
- "npm error"
- "stuck on"
- "service failing"

Try being more explicit: "Help me debug this Node.js application"

### Test scripts not working?

Make sure they're executable:

```bash
chmod +x ~/.claude/skills/debugging-nodejs-apps/test-scripts/*.js
```

Verify Node.js is in your PATH:

```bash
which node
node --version
```

### Want more examples?

Check `./common-nodejs-errors.md` for comprehensive error catalog with:
- 20+ common errors
- Investigation commands
- Multiple solution approaches
- Code examples

## Updates and Maintenance

This skill is designed to be:
- **Self-contained** - No external dependencies
- **Version-agnostic** - Works with Node.js 14+
- **Extensible** - Add your own error patterns

To add custom patterns:
1. Edit `./common-nodejs-errors.md`
2. Add to decision trees in `SKILL.md`
3. Create test scripts as needed

## Resources

External documentation references:
- [Node.js Debugging Guide](https://nodejs.org/en/docs/guides/debugging-getting-started/)
- [npm CLI Documentation](https://docs.npmjs.com/cli/)
- [ESM vs CommonJS](https://nodejs.org/api/esm.html)

## License

This skill is part of your personal Claude Code setup. Modify as needed for your workflows.
