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
  CFMutableDictionaryRef query=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(query,kSecClass,kSecClassGenericPassword);
  CFDictionarySetValue(query,kSecAttrService,CFSTR("workspace-test"));
  CFDictionarySetValue(query,kSecAttrAccount,CFSTR("a"));
  OSStatus status;
  if(!strcmp(argv[2],"write")) {
    CFDictionarySetValue(query,kSecUseKeychain,kc);
    CFDataRef value=CFDataCreate(NULL,(const UInt8 *)"fixture",7);
    CFDictionarySetValue(query,kSecValueData,value);status=SecItemAdd(query,NULL);CFRelease(value);
  } else {
    const void *items[]={kc};CFArrayRef search=CFArrayCreate(NULL,items,1,&kCFTypeArrayCallBacks);
    CFDictionarySetValue(query,kSecMatchSearchList,search);CFDictionarySetValue(query,kSecReturnData,kCFBooleanTrue);
    CFTypeRef data=NULL;status=SecItemCopyMatching(query,&data);
    if(!status&&(CFDataGetLength(data)!=7||memcmp(CFDataGetBytePtr(data),"fixture",7)))return 4;
    if(data)CFRelease(data);CFRelease(search);
  }
  CFRelease(query);
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

  // Use one fixed read-only helper while replacing the GUI caller with new builds.
  const app = path.join(dir, 'Review.app'), helper = path.join(app, 'Contents/Helpers/workspace-credentials'), parent = path.join(app, 'Contents/MacOS/LocalWorkspace');
  fs.mkdirSync(path.dirname(helper), { recursive: true }); fs.mkdirSync(path.dirname(parent), { recursive: true });
  const helperArgs = ['-O2', '-mmacosx-version-min=14.0', `-DWORKSPACE_CERT_SHA1="${identity}"`, `-DWORKSPACE_TEST_KEYCHAIN="${keychain}"`, path.resolve('macos/credential_helper.c'), '-framework', 'Security', '-framework', 'CoreFoundation'];
  const sign = (exe, id, hardened = true, signer = identity) => run('/usr/bin/codesign', ['--force', '--timestamp=none', '--sign', signer, '--keychain', keychain, ...(hardened ? ['--options', 'runtime'] : []), '--identifier', id, exe]);
  run('/usr/bin/xcrun', ['clang', ...helperArgs, '-o', helper]); sign(helper, 'community.localworkspace.mac.credentials');
  const writer = path.join(dir, 'writer.c'), writerExe = path.join(dir, 'writer');
  fs.writeFileSync(writer, `#include <Security/Security.h>
int main(int argc,char **argv) {
 SecKeychainRef kc=NULL;SecTrustedApplicationRef app=NULL;SecAccessRef access=NULL;
 if(argc!=3||SecKeychainOpen(argv[1],&kc)||SecTrustedApplicationCreateFromPath(argv[2],&app))return 1;
 const void *items[]={app};CFArrayRef apps=CFArrayCreate(NULL,items,1,&kCFTypeArrayCallBacks);
 if(SecAccessCreate(CFSTR("Workspace helper fixture"),apps,&access))return 2;
 CFMutableDictionaryRef q=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 CFDictionarySetValue(q,kSecClass,kSecClassGenericPassword);CFDictionarySetValue(q,kSecUseKeychain,kc);
 CFDictionarySetValue(q,kSecAttrService,CFSTR("workspace-helper-test"));CFDictionarySetValue(q,kSecAttrAccount,CFSTR("tunnel-api-key"));
 CFDataRef data=CFDataCreate(NULL,(const UInt8 *)"fixture",7);CFDictionarySetValue(q,kSecValueData,data);CFDictionarySetValue(q,kSecAttrAccess,access);
 return SecItemAdd(q,NULL)==0?0:3;
}`);
  run('/usr/bin/xcrun', ['clang', writer, '-framework', 'Security', '-framework', 'CoreFoundation', '-o', writerExe]);
  run(writerExe, [keychain, helper]);
  const caller = path.join(dir, 'caller.c');
  fs.writeFileSync(caller, `#include <unistd.h>
#include <sys/wait.h>
int main(int argc,char **argv){volatile int build=BUILD;if(build<0||argc!=2)return 9;pid_t pid=fork();if(pid==0){execl(argv[1],argv[1],"read","noninteractive",NULL);_exit(8);}int status=0;if(pid<0||waitpid(pid,&status,0)<0)return 7;return WIFEXITED(status)?WEXITSTATUS(status):6;}`);
  const compileCaller = (build, hardened = true, signer = identity) => {
    run('/usr/bin/xcrun', ['clang', '-DBUILD=' + build, caller, '-o', parent]);
    sign(parent, 'community.localworkspace.mac', hardened, signer);
  };
  compileCaller(1);
  assert.equal(run(parent, [helper]).toString(), '0\nfixture');
  const oldCaller = fs.readFileSync(parent);
  compileCaller(2);
  assert.notDeepEqual(fs.readFileSync(parent), oldCaller);
  assert.equal(run(parent, [helper]).toString(), '0\nfixture', 'a changed authenticated GUI uses the same helper without authorization');
  assert.equal(run(helper, ['read', 'noninteractive']).toString(), '-25293\n', 'direct callers cannot retrieve a secret');
  compileCaller(3, false);
  assert.equal(run(parent, [helper]).toString(), '-25293\n', 'an injectable caller is rejected');
  compileCaller(4, true, '-');
  assert.equal(run(parent, [helper]).toString(), '-25293\n', 'a caller signed by a different identity is rejected');
  const rebuiltHelper = path.join(dir, 'another-stage/workspace-credentials');
  fs.mkdirSync(path.dirname(rebuiltHelper)); run('/usr/bin/xcrun', ['clang', ...helperArgs, '-o', rebuiltHelper]); sign(rebuiltHelper, 'community.localworkspace.mac.credentials');
  const cdhash = exe => {
    const result = spawnSync('/usr/bin/codesign', ['-d', '--verbose=4', exe], { encoding: 'utf8' });
    return result.stderr.match(/^CDHash=(\w+)$/m)?.[1];
  };
  assert(cdhash(helper)); assert.equal(cdhash(helper), cdhash(rebuiltHelper), 'helper identity stays identical in another build directory');
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
