// Stable, read-only Keychain client. Secrets leave only through the authenticated
// GUI parent's private stdout pipe. Never accept a caller-supplied item name.
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libproc.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef WORKSPACE_CERT_SHA1
#error A pinned signing certificate is required
#endif

static int authorized_parent(int *preview) {
    pid_t pid=getppid();
    char parent[PROC_PIDPATHINFO_MAXSIZE],own[PATH_MAX],resolved[PATH_MAX];
    uint32_t size=sizeof(own);
    if(pid<=1 || proc_pidpath(pid,parent,sizeof(parent))<=0 || _NSGetExecutablePath(own,&size) || !realpath(own,resolved))return 0;
    char *helpers=strstr(resolved,"/Contents/Helpers/workspace-credentials");
    if(!helpers || helpers[strlen("/Contents/Helpers/workspace-credentials")])return 0;
    strcpy(helpers,"/Contents/MacOS/LocalWorkspace");
    if(strcmp(parent,resolved))return 0;
    CFNumberRef number=CFNumberCreate(NULL,kCFNumberIntType,&pid);
    const void *keys[]={kSecGuestAttributePid},*values[]={number};
    CFDictionaryRef attributes=CFDictionaryCreate(NULL,keys,values,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    SecCodeRef code=NULL;OSStatus status=SecCodeCopyGuestWithAttributes(NULL,attributes,kSecCSDefaultFlags,&code);
    CFRelease(attributes);CFRelease(number);if(status)return 0;
    SecRequirementRef requirement=NULL;
    status=SecRequirementCreateWithString(CFSTR("(identifier \"community.localworkspace.mac\" or identifier \"community.localworkspace.mac.preview\") and certificate leaf = H\"" WORKSPACE_CERT_SHA1 "\""),kSecCSDefaultFlags,&requirement);
    if(!status)status=SecCodeCheckValidity(code,kSecCSStrictValidate,requirement);
    CFDictionaryRef info=NULL;
    if(!status)status=SecCodeCopySigningInformation(code,kSecCSSigningInformation,&info);
    int allowed=0;
    if(!status && info) {
        int flags=0;CFNumberRef number=CFDictionaryGetValue(info,kSecCodeInfoFlags);
        if(number)CFNumberGetValue(number,kCFNumberIntType,&flags);
        CFDictionaryRef entitlements=CFDictionaryGetValue(info,kSecCodeInfoEntitlementsDict);
        int weakened=entitlements && (
            CFDictionaryGetValue(entitlements,CFSTR("com.apple.security.cs.disable-library-validation"))==kCFBooleanTrue ||
            CFDictionaryGetValue(entitlements,CFSTR("com.apple.security.cs.allow-dyld-environment-variables"))==kCFBooleanTrue);
        allowed=(flags & kSecCodeSignatureRuntime) && !weakened;
        *preview=CFEqual(CFDictionaryGetValue(info,kSecCodeInfoIdentifier),CFSTR("community.localworkspace.mac.preview"));
    }
    if(info)CFRelease(info);if(requirement)CFRelease(requirement);CFRelease(code);return allowed;
}

int main(int argc,char **argv) {
    int preview=0;pid_t parent=getppid();
    if(argc!=3 || (strcmp(argv[1],"read") && strcmp(argv[1],"read-production")) ||
       (strcmp(argv[2],"interactive") && strcmp(argv[2],"noninteractive")) || !authorized_parent(&preview)) {
        printf("%d\n",(int)errSecAuthFailed);return 0;
    }
    if(!strcmp(argv[2],"noninteractive"))SecKeychainSetUserInteractionAllowed(false);
    CFMutableDictionaryRef query=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(query,kSecClass,kSecClassGenericPassword);
#ifdef WORKSPACE_TEST_KEYCHAIN
    // Compile-time-only isolation for regression tests; production has no override.
    SecKeychainRef keychain=NULL;
    if(SecKeychainOpen(WORKSPACE_TEST_KEYCHAIN,&keychain)){CFRelease(query);printf("%d\n",(int)errSecItemNotFound);return 0;}
    const void *items[]={keychain};CFArrayRef search=CFArrayCreate(NULL,items,1,&kCFTypeArrayCallBacks);
    CFDictionarySetValue(query,kSecMatchSearchList,search);CFRelease(search);CFRelease(keychain);
    CFDictionarySetValue(query,kSecAttrService,CFSTR("workspace-helper-test"));
#else
    CFDictionarySetValue(query,kSecAttrService,preview && !strcmp(argv[1],"read") ? CFSTR("community.localworkspace.mac.preview") : CFSTR("community.localworkspace.mac"));
#endif
    CFDictionarySetValue(query,kSecAttrAccount,CFSTR("tunnel-api-key"));
    CFDictionarySetValue(query,kSecReturnData,kCFBooleanTrue);
    CFDictionarySetValue(query,kSecMatchLimit,kSecMatchLimitOne);
    CFTypeRef result=NULL;OSStatus status=SecItemCopyMatching(query,&result);
    if(getppid()!=parent)status=errSecAuthFailed;
    if(!status && (!result || CFGetTypeID(result)!=CFDataGetTypeID() || CFDataGetLength(result)>65536))status=errSecDecode;
    printf("%d\n",(int)status);fflush(stdout);
    if(!status)fwrite(CFDataGetBytePtr(result),1,CFDataGetLength(result),stdout);
    if(result)CFRelease(result);CFRelease(query);return 0;
}
