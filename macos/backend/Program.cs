using System;
using System.IO;
using System.Runtime.InteropServices;

[assembly: System.Runtime.Versioning.SupportedOSPlatform("macos")]

static class Program
{
    static void Main(string[] args)
    {
        Environment.SetEnvironmentVariable("PATH", string.Join(":", new[] {
            Environment.GetEnvironmentVariable("PATH"), "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
        }));
        using var term = PosixSignalRegistration.Create(PosixSignal.SIGTERM, context => {
            context.Cancel = true;
            WorkspaceServer.Shutdown();
            Environment.Exit(0);
        });
        WorkspaceServer.Run();
    }
}
