const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync, spawnSync } = require('node:child_process');
const mac = process.platform === 'darwin';

function temporary(t, prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test('local certificate retains Keychain access across changed builds and rejects a different signer', { skip: !mac, timeout: 60000 }, t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-signing-test-'));
  const run = (bin, args) => execFileSync(bin, args, { stdio: 'pipe', timeout: 20000 });
  const keychain = path.join(dir, 'isolated.keychain-db');
  const password = crypto.randomBytes(24).toString('hex');
  run('/usr/bin/security', ['create-keychain', '-p', password, keychain]);
  t.after(() => {
    try { run('/usr/bin/security', ['delete-keychain', keychain]); }
    finally { fs.rmSync(dir, { recursive: true, force: true }); }
  });
  run('/usr/bin/security', ['unlock-keychain', '-p', password, keychain]);
  const config = path.join(dir, 'openssl.cnf'), cert = path.join(dir, 'cert.pem'), key = path.join(dir, 'key.pem'), rsa = path.join(dir, 'rsa.pem');
  fs.writeFileSync(config, '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Workspace isolated signing regression\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n');
  run('/usr/bin/openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-x509', '-sha256', '-days', '2', '-config', config, '-keyout', key, '-out', cert]);
  fs.chmodSync(key, 0o600);
  run('/usr/bin/openssl', ['rsa', '-in', key, '-out', rsa]); fs.chmodSync(rsa, 0o600);
  run('/usr/bin/security', ['import', cert, '-k', keychain, '-t', 'cert', '-f', 'pemseq']);
  run('/usr/bin/security', ['import', rsa, '-k', keychain, '-t', 'priv', '-f', 'openssl', '-x', '-T', '/usr/bin/codesign']);
  const identity = new crypto.X509Certificate(fs.readFileSync(cert)).fingerprint.replaceAll(':', '');
  const source = path.join(dir, 'probe.c');
  fs.writeFileSync(source, `#include <Security/Security.h>
#include <string.h>
int main(int argc,char **argv) {
  volatile int build=BUILD; if(build<0)return 9;
  SecKeychainRef kc=NULL; SecKeychainSetUserInteractionAllowed(false);
  if(argc!=3||SecKeychainOpen(argv[1],&kc))return 3;
  OSStatus status;
  if(!strcmp(argv[2],"write"))status=SecKeychainAddGenericPassword(kc,14,"workspace-test",1,"a",7,"fixture",NULL);
  else { UInt32 size=0;void *data=NULL;status=SecKeychainFindGenericPassword(kc,14,"workspace-test",1,"a",&size,&data,NULL);
    if(!status&&(size!=7||memcmp(data,"fixture",7)))return 4;
    if(data)SecKeychainItemFreeContent(NULL,data);
  }
  CFRelease(kc);return status==errSecSuccess?0:2;
}`);
  const versions = ['v1', 'v2', 'unrelated'].map(name => path.join(dir, name));
  versions.forEach((exe, index) => {
    run('/usr/bin/xcrun', ['clang', '-DBUILD=' + index, source, '-framework', 'Security', '-framework', 'CoreFoundation', '-o', exe]);
    run('/usr/bin/codesign', ['--force', '--timestamp=none', '--sign', index === 2 ? '-' : identity, '--keychain', keychain, '--identifier', 'community.localworkspace.signing-test', exe]);
    run('/usr/bin/codesign', ['--verify', '--strict', exe]);
  });
  assert.notDeepEqual(fs.readFileSync(versions[0]), fs.readFileSync(versions[1]));
  run(versions[0], [keychain, 'write']);
  run(versions[1], [keychain, 'read']);
  assert.equal(spawnSync(versions[2], [keychain, 'read'], { timeout: 5000 }).status, 2, 'another signer must not inherit access');
});

test('connection credential cache avoids repeat reads, keeps source isolation and retries explicit failures', { skip: !mac, timeout: 60000 }, t => {
  const dir = temporary(t, 'workspace-credential-test-'), source = path.join(dir, 'main.swift'), exe = path.join(dir, 'check');
  fs.writeFileSync(source, `import Foundation
final class Counter: @unchecked Sendable { var reads=0 }
struct Denied: Error {}
@main struct Check {
  @MainActor static func main() async throws {
    let cache=ConnectionCredentialCache(), count=Counter()
    let reader: @Sendable (Bool) throws -> String? = { source in count.reads += 1; return source ? "production-fixture" : "preview-fixture" }
    let first=try await cache.resolve(useProduction:false,read:reader)
    let second=try await cache.resolve(useProduction:false,read:reader)
    precondition(first==second && count.reads==1)
    _=try await cache.resolve(useProduction:true,read:reader)
    precondition(count.reads==2)
    cache.remember("replacement-fixture",useProduction:false)
    let changed=try await cache.resolve(useProduction:false,read:reader)
    precondition(changed=="replacement-fixture" && count.reads==2)
    precondition(!cache.redacted(changed+"production-fixture").contains("fixture"))
    let empty=ConnectionCredentialCache(), retries=Counter()
    let missing: @Sendable (Bool) throws -> String? = { _ in retries.reads += 1; if retries.reads==1 { throw Denied() }; return retries.reads==2 ? nil : "available" }
    do { _=try await empty.resolve(useProduction:false,read:missing); preconditionFailure() } catch is Denied {}
    let absent=try await empty.resolve(useProduction:false,read:missing)
    precondition(absent.isEmpty)
    let recovered=try await empty.resolve(useProduction:false,read:missing)
    precondition(recovered=="available" && retries.reads==3)
    print("credential cache passed")
  }
}
`);
  execFileSync('swiftc', ['-parse-as-library', path.resolve('macos/Sources/LocalWorkspace/Services/ConnectionCredentialCache.swift'), source, '-o', exe], { timeout: 60000, stdio: 'pipe' });
  assert.match(execFileSync(exe, { encoding: 'utf8' }), /cache passed/);
});
