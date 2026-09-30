using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;

static class MacPlatform
{
    public static string NormalizePath(string path) {
        string current = Path.GetFullPath(path);
        var suffix = new System.Collections.Generic.Stack<string>();
        while(!Directory.Exists(current) && !File.Exists(current)) {
            suffix.Push(Path.GetFileName(current));
            current = Path.GetDirectoryName(current);
            if (string.IsNullOrEmpty(current)) throw new IOException("Cannot resolve path: " + path);
        }
        current = RealPath(current);
        while(suffix.Count > 0) current = Path.Combine(current, suffix.Pop());
        return current;
    }
    [DllImport("libc")] static extern int kill(int pid, int signal);
    [DllImport("libc")] static extern IntPtr realpath(string path, IntPtr buffer);
    [DllImport("libc")] static extern void free(IntPtr pointer);
    public static string RealPath(string path) {
        var pointer = realpath(path, IntPtr.Zero);
        if (pointer == IntPtr.Zero) throw new IOException("Cannot resolve workspace: " + path);
        try { return Marshal.PtrToStringUTF8(pointer); } finally { free(pointer); }
    }
    public static ProcessStartInfo Shell(string shell, string executable, string command, string cwd) {
        string launcher = Path.Combine(AppContext.BaseDirectory, "workspace-launcher");
        var info = new ProcessStartInfo(File.Exists(launcher) ? launcher : executable) {
            UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true,
            RedirectStandardError = true, WorkingDirectory = cwd,
            StandardOutputEncoding = new System.Text.UTF8Encoding(false), StandardErrorEncoding = new System.Text.UTF8Encoding(false)
        };
        if (File.Exists(launcher)) info.ArgumentList.Add(executable);
        if (shell == "pwsh") {
            info.ArgumentList.Add("-NoLogo"); info.ArgumentList.Add("-NoProfile");
            info.ArgumentList.Add("-NonInteractive"); info.ArgumentList.Add("-OutputFormat"); info.ArgumentList.Add("Text");
            info.ArgumentList.Add("-EncodedCommand");
            string pre = "$ProgressPreference='SilentlyContinue'; $ErrorActionPreference='Stop'; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $OutputEncoding=[Console]::OutputEncoding; ";
            info.ArgumentList.Add(Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(pre + command)));
        } else if (shell == "bash") {
            info.ArgumentList.Add("--noprofile"); info.ArgumentList.Add("--norc"); info.ArgumentList.Add("-c");
            info.ArgumentList.Add(command);
        } else {
            info.ArgumentList.Add("-f"); info.ArgumentList.Add("-c");
            info.ArgumentList.Add(command);
        }
        return info;
    }
    public static void Stop(Process process) {
        if (process.StartInfo.FileName.EndsWith("workspace-launcher", StringComparison.Ordinal)) {
            // The launcher creates a private process group, including grandchildren.
            kill(-process.Id, 9);
        }
        if (!process.HasExited) { try { process.Kill(true); } catch (InvalidOperationException) {} }
        process.WaitForExit(3000);
    }
    public static void Reveal(string target) {
        if (string.IsNullOrEmpty(target) || target.IndexOfAny(new[] {'\r', '\n', '\0'}) >= 0)
            throw new ArgumentException("无效的路径或地址。");
        var info = new ProcessStartInfo("/usr/bin/open") { UseShellExecute = false };
        if (Uri.TryCreate(target, UriKind.Absolute, out var url) && (url.Scheme == "https" || url.Scheme == "http")) {
            info.ArgumentList.Add(target);
        } else {
            if (!Path.IsPathFullyQualified(target)) throw new ArgumentException("请选择完整的 macOS 文件或目录路径。");
            if (!Directory.Exists(target) && !File.Exists(target)) throw new FileNotFoundException("路径已不存在或无法访问：" + target);
            if (!Directory.Exists(target)) info.ArgumentList.Add("-R");
            info.ArgumentList.Add(target);
        }
        using var process = Process.Start(info);
        if (!process.WaitForExit(4000) || process.ExitCode != 0) throw new IOException("Finder 未能打开该位置。");
    }
}
