using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

// Only workspace-state encryption lives here. Tunnel credentials are a separate
// Keychain service owned by the Swift app; this code never reads those items.
static class StateKeychain
{
    const string Security = "/System/Library/Frameworks/Security.framework/Security";
    const string CoreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    const string ProductionService = "community.localworkspace.mac.state-encryption";
    const string TestServicePrefix = ProductionService + ".test.";
    static readonly string Service = ResolveService();
    const string Account = "state-v1";
    const int NotFound = -25300, Duplicate = -25299;
    const int KeyLength = 32, NonceLength = 12, TagLength = 16;
    static readonly byte[] Magic = Encoding.ASCII.GetBytes("LWSMAC01");
    static readonly IntPtr SecurityHandle = NativeLibrary.Load(Security);
    static readonly IntPtr FoundationHandle = NativeLibrary.Load(CoreFoundation);

    // Integration tests must not request access to a user's existing state key.
    // The explicit override is restricted to disposable test items and requires
    // an explicitly selected state directory; normal app runs retain the service.
    static string ResolveService()
    {
        string configured = Environment.GetEnvironmentVariable("WORKSPACE_TEST_STATE_KEYCHAIN_SERVICE");
        if (string.IsNullOrEmpty(configured)) return ProductionService;
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("WORKSPACE_STATE_DIR")) ||
            !configured.StartsWith(TestServicePrefix, StringComparison.Ordinal))
            throw new ArgumentException("Test Keychain service requires WORKSPACE_STATE_DIR and the dedicated test prefix.");
        string suffix = configured.Substring(TestServicePrefix.Length);
        if (suffix.Length == 0 || suffix.Length > 128)
            throw new ArgumentException("Test Keychain service suffix must contain 1..128 safe characters.");
        foreach (char c in suffix)
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '-' || c == '_'))
                throw new ArgumentException("Test Keychain service suffix contains unsafe characters.");
        return configured;
    }

    [DllImport(CoreFoundation)] static extern IntPtr CFDictionaryCreateMutable(IntPtr allocator, nint capacity, IntPtr keyCallbacks, IntPtr valueCallbacks);
    [DllImport(CoreFoundation)] static extern void CFDictionarySetValue(IntPtr dictionary, IntPtr key, IntPtr value);
    [DllImport(CoreFoundation)] static extern IntPtr CFStringCreateWithCString(IntPtr allocator, [MarshalAs(UnmanagedType.LPUTF8Str)] string value, uint encoding);
    [DllImport(CoreFoundation)] static extern IntPtr CFDataCreate(IntPtr allocator, byte[] bytes, nint length);
    [DllImport(CoreFoundation)] static extern nint CFDataGetLength(IntPtr data);
    [DllImport(CoreFoundation)] static extern IntPtr CFDataGetBytePtr(IntPtr data);
    [DllImport(CoreFoundation)] static extern void CFRelease(IntPtr value);
    [DllImport(Security)] static extern int SecItemCopyMatching(IntPtr query, out IntPtr result);
    [DllImport(Security)] static extern int SecItemAdd(IntPtr attributes, IntPtr result);

    static IntPtr SecurityValue(string name) { return Marshal.ReadIntPtr(NativeLibrary.GetExport(SecurityHandle, name)); }
    static IntPtr FoundationValue(string name) { return Marshal.ReadIntPtr(NativeLibrary.GetExport(FoundationHandle, name)); }
    static void Set(IntPtr query, string key, IntPtr value) { CFDictionarySetValue(query, SecurityValue(key), value); }
    static IntPtr Query(string service)
    {
        var query = CFDictionaryCreateMutable(IntPtr.Zero, 0,
            NativeLibrary.GetExport(FoundationHandle, "kCFTypeDictionaryKeyCallBacks"),
            NativeLibrary.GetExport(FoundationHandle, "kCFTypeDictionaryValueCallBacks"));
        if (query == IntPtr.Zero) throw new IOException("Cannot allocate workspace Keychain query.");
        try {
            Set(query, "kSecClass", SecurityValue("kSecClassGenericPassword"));
            SetText(query, "kSecAttrService", service);
            SetText(query, "kSecAttrAccount", Account);
            return query;
        } catch { CFRelease(query); throw; }
    }
    static void SetText(IntPtr query, string key, string text)
    {
        var value = CFStringCreateWithCString(IntPtr.Zero, text, 0x08000100);
        if (value == IntPtr.Zero) throw new IOException("Cannot allocate workspace Keychain attribute.");
        try { Set(query, key, value); } finally { CFRelease(value); }
    }
    static byte[] ReadKey(string service)
    {
        var query = Query(service); IntPtr result = IntPtr.Zero;
        try {
            Set(query, "kSecReturnData", FoundationValue("kCFBooleanTrue"));
            Set(query, "kSecMatchLimit", SecurityValue("kSecMatchLimitOne"));
            int status = SecItemCopyMatching(query, out result);
            if (status == NotFound) return null;
            if (status != 0) throw new IOException("Cannot access workspace-state Keychain key (OSStatus " + status + "). Unlock the login Keychain and allow access; no state was overwritten.");
            if (result == IntPtr.Zero || CFDataGetLength(result) != KeyLength)
                throw new CryptographicException("Workspace-state Keychain key is invalid; original state was preserved.");
            var key = new byte[KeyLength]; Marshal.Copy(CFDataGetBytePtr(result), key, 0, key.Length); return key;
        } finally { if (result != IntPtr.Zero) CFRelease(result); CFRelease(query); }
    }
    // A service argument also permits round-trip tests with an isolated disposable
    // Keychain item. Production always uses the dedicated service above.
    internal static byte[] GetOrCreateKey(string service, bool mayCreate)
    {
        byte[] existing = ReadKey(service);
        if (existing != null) return existing;
        if (!mayCreate) throw new CryptographicException("Workspace-state Keychain key is missing; original state was preserved. Restore the key or select a new WORKSPACE_STATE_DIR.");
        byte[] key = RandomNumberGenerator.GetBytes(KeyLength);
        var query = Query(service); IntPtr data = IntPtr.Zero;
        try {
            data = CFDataCreate(IntPtr.Zero, key, key.Length);
            if (data == IntPtr.Zero) throw new IOException("Cannot allocate workspace Keychain key data.");
            Set(query, "kSecValueData", data);
            SetText(query, "kSecAttrLabel", "ChatGPT Codex Workspace — local state encryption");
            int status = SecItemAdd(query, IntPtr.Zero);
            if (status == 0) return key;
            if (status == Duplicate) {
                // Concurrent first use in different isolated state directories.
                byte[] winner = ReadKey(service);
                if (winner != null) { CryptographicOperations.ZeroMemory(key); return winner; }
            }
            throw new IOException("Cannot save workspace-state Keychain key (OSStatus " + status + "); no state was written.");
        } catch { CryptographicOperations.ZeroMemory(key); throw; }
        finally { if (data != IntPtr.Zero) CFRelease(data); CFRelease(query); }
    }
    public static byte[] Protect(byte[] plain, byte[] context, bool mayCreateKey)
    {
        byte[] key = GetOrCreateKey(Service, mayCreateKey);
        try { return Encrypt(plain, context, key); }
        finally { CryptographicOperations.ZeroMemory(key); }
    }
    public static byte[] Unprotect(byte[] encrypted, byte[] context)
    {
        // Never recreate a missing key when saved state already exists.
        byte[] key = GetOrCreateKey(Service, false);
        try { return Decrypt(encrypted, context, key); }
        finally { CryptographicOperations.ZeroMemory(key); }
    }
    internal static byte[] Encrypt(byte[] plain, byte[] context, byte[] key)
    {
        byte[] result = new byte[Magic.Length + NonceLength + TagLength + plain.Length];
        Magic.CopyTo(result, 0);
        var nonce = result.AsSpan(Magic.Length, NonceLength);
        RandomNumberGenerator.Fill(nonce);
        using (var cipher = new AesGcm(key, TagLength))
            cipher.Encrypt(nonce, plain, result.AsSpan(Magic.Length + NonceLength + TagLength), result.AsSpan(Magic.Length + NonceLength, TagLength), context);
        return result;
    }
    internal static byte[] Decrypt(byte[] encrypted, byte[] context, byte[] key)
    {
        if (encrypted.Length < Magic.Length + NonceLength + TagLength || !encrypted.AsSpan(0, Magic.Length).SequenceEqual(Magic))
            throw new CryptographicException("Unsupported workspace-state encryption format; original state was preserved.");
        byte[] plain = new byte[encrypted.Length - Magic.Length - NonceLength - TagLength];
        try {
            using (var cipher = new AesGcm(key, TagLength))
                cipher.Decrypt(encrypted.AsSpan(Magic.Length, NonceLength), encrypted.AsSpan(Magic.Length + NonceLength + TagLength), encrypted.AsSpan(Magic.Length + NonceLength, TagLength), plain, context);
            return plain;
        } catch { CryptographicOperations.ZeroMemory(plain); throw; }
    }
}
