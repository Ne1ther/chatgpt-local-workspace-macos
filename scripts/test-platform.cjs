const { spawnSync } = require('node:child_process');
const tests = process.platform === 'darwin'
  ? ['tests/macos.test.cjs', 'tests/reliability.test.cjs', 'tests/dashboard-ui.test.cjs', 'tests/navigation.test.cjs', 'tests/preview-state.test.cjs', 'tests/local-access.test.cjs', 'tests/cleanup.test.cjs']
  : require('node:fs').readdirSync('tests').filter(name => name.endsWith('.test.cjs') && name !== 'macos.test.cjs').map(name => 'tests/' + name);
const result = spawnSync(process.execPath, ['--test', ...tests], { stdio: 'inherit' });
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
