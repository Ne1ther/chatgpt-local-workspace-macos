using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

// One writer per local store; state is encrypted for the current OS user.
static class WorkspaceStore
{
    static readonly object Gate = new object();
    static FileStream lease;
    static string root;
    static bool unreadableState;
    static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 128 * 1024 * 1024, RecursionLimit = 100 }; }
    public static string Root { get { Ensure(); return root; } }
    static void Ensure()
    {
        lock (Gate) {
            if (lease != null) return;
            string configured = Environment.GetEnvironmentVariable("WORKSPACE_STATE_DIR");
            string defaultRoot;
#if MACOS
            defaultRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Application Support", "LocalWorkspacePlugin", "state-v1");
#else
            defaultRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LocalWorkspacePlugin", "state-v1");
#endif
            root = Path.GetFullPath(string.IsNullOrEmpty(configured) ? defaultRoot : configured);
            Directory.CreateDirectory(root);
#if MACOS
            if (OperatingSystem.IsMacOS()) File.SetUnixFileMode(root, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
#endif
            try { lease = new FileStream(Path.Combine(root, "owner.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { throw new IOException("Workspace state is already in use. Close the other MCP runtime or use a separate WORKSPACE_STATE_DIR."); }
        }
    }
    public static T Load<T>(string name, Func<T> empty)
    {
        lock (Gate) {
            Ensure(); string path = Path.Combine(root, name + ".bin");
            if (!File.Exists(path)) return empty();
            try {
                byte[] plain;
#if MACOS
                plain = StateKeychain.Unprotect(File.ReadAllBytes(path), Encoding.UTF8.GetBytes("LocalWorkspace/state-v1/" + name));
#else
                plain = ProtectedData.Unprotect(File.ReadAllBytes(path), Encoding.UTF8.GetBytes("LocalWorkspace/state-v1/" + name), DataProtectionScope.CurrentUser);
#endif
                try { return Serializer().Deserialize<T>(Encoding.UTF8.GetString(plain)); }
                finally { Array.Clear(plain, 0, plain.Length); }
            } catch (Exception ex) { unreadableState = true; throw new IOException("Cannot read saved workspace " + name + "; original state was preserved. " + ex.GetType().Name, ex); }
        }
    }
    public static void Save(string name, object state)
    {
        lock (Gate) {
            Ensure();
            if (unreadableState) throw new IOException("Saved workspace could not be read; original state is preserved. Restart after restoring access or repairing the saved state.");
            byte[] plain = Encoding.UTF8.GetBytes(Serializer().Serialize(state));
            if (plain.Length > 96 * 1024 * 1024) { Array.Clear(plain, 0, plain.Length); throw new IOException("Saved workspace data exceeds 96 MiB; reduce retained history."); }
            byte[] encrypted;
            try {
#if MACOS
                // A lost/locked key must not be replaced while any encrypted state exists.
                bool mayCreateKey = Directory.GetFiles(root, "*.bin").Length == 0;
                encrypted = StateKeychain.Protect(plain, Encoding.UTF8.GetBytes("LocalWorkspace/state-v1/" + name), mayCreateKey);
#else
                encrypted = ProtectedData.Protect(plain, Encoding.UTF8.GetBytes("LocalWorkspace/state-v1/" + name), DataProtectionScope.CurrentUser);
#endif
            }
            finally { Array.Clear(plain, 0, plain.Length); }
            AtomicWrite(Path.Combine(root, name + ".bin"), encrypted, true);
        }
    }
    public static void AtomicWrite(string path, byte[] data) { AtomicWrite(path, data, false); }
    static void AtomicWrite(string path, byte[] data, bool privateState)
    {
        string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
#if MACOS
        UnixFileMode targetMode = privateState ? UnixFileMode.UserRead | UnixFileMode.UserWrite :
            File.Exists(path) ? File.GetUnixFileMode(path) : UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.GroupRead | UnixFileMode.OtherRead;
#endif
        try {
#if MACOS
            // Stage privately; do not expose partially written files, and retain
            // executable/read-only bits when replacing an existing workspace file.
            using (var stream = new FileStream(temp, new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None, UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite })) { stream.Write(data, 0, data.Length); stream.Flush(true); }
            File.SetUnixFileMode(temp, targetMode);
#else
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(data, 0, data.Length); stream.Flush(true); }
#endif
            if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path);
        } finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
