using System;
using System.IO;
using System.Text;
using System.ComponentModel;

// Checks run in the actual MCP process. A successful check is an observation,
// never a grant of access or a promise about other paths or future requests.
static class WorkspaceAccess
{
    public static object Policy()
    {
        return new {
            execution_identity="current_user", workspace_is_sandbox=false,
            privilege_escalation=false, system_permissions="operating_system",
            file_operations="read, write, search, patch, history and restore within the current user's effective access",
            command_operations="installed shells with pipes; default timeout 300 seconds, explicit maximum 86400 seconds; process-tree stop; no PTY",
            history_scope="Direct file-tool changes only; shell and external side effects are not undoable here",
            permission_recovery="Use the native Local Capabilities page to check a selected directory. Change OS permissions yourself when needed; do not repeatedly retry a denied operation."
        };
    }

    public static string ErrorCode(Exception error)
    {
        var native=error as Win32Exception;
        bool denied=error is UnauthorizedAccessException;
        if(native!=null) {
#if MACOS
            denied|=native.NativeErrorCode==1||native.NativeErrorCode==13;
#else
            denied|=native.NativeErrorCode==5||native.NativeErrorCode==1314;
#endif
        }
        if(denied)return "ACCESS_DENIED";
        if(error is DirectoryNotFoundException||error is FileNotFoundException)return "PATH_NOT_FOUND";
        if(error is ArgumentException||error is NotSupportedException)return "INVALID_ARGUMENT";
        return "TOOL_ERROR";
    }
    public static object Failure(Exception error,string path)
    {
        string code=ErrorCode(error),action;
        if(code=="ACCESS_DENIED") {
#if MACOS
            action="在 Mac 应用的“本地能力”中选择该目录并检查。若 macOS 拒绝访问，在系统设置 → 隐私与安全性 → 文件与文件夹中确认本应用权限，再重新检查。Unix 文件权限、只读卷也可能导致拒绝；不要自动提权或反复重试。";
#else
            action="检查当前用户的文件权限、只读卷或系统保护设置；权限恢复后重试，不要自动提权或反复重试。";
#endif
        } else if(code=="PATH_NOT_FOUND")action="核对完整路径和上级目录；在本机重新选择已存在的位置。";
        else action="检查具体错误与输入；先确认此前操作的实际结果，再决定是否重试。";
        return new {error_code=code,message=error.Message,requested_path=path,next_action=action,retry_after_user_action=code=="ACCESS_DENIED"};
    }
    static object Outcome(string status,string message,string code=null){return new{status=status,message=message,error_code=code};}
    static object Failed(Exception error){string code=ErrorCode(error);return Outcome(code=="ACCESS_DENIED"?"denied":code=="PATH_NOT_FOUND"?"missing":"failed",error.Message,code);}

    public static object Check(string requested,bool writeTest)
    {
        string resolved=null,artifact=null;
        object read=Outcome("not_checked","尚未检查"),write=Outcome("not_checked","未进行写入检查");
        try {
            if(string.IsNullOrWhiteSpace(requested)||requested.IndexOfAny(new[]{'\0','\r','\n'})>=0||!Path.IsPathRooted(requested))throw new ArgumentException("请选择完整的本地目录路径。");
#if MACOS
            if(!Path.IsPathFullyQualified(requested))throw new ArgumentException("请选择以 / 开头的完整目录路径。");
            resolved=MacPlatform.NormalizePath(requested);
#else
            resolved=Path.GetFullPath(requested);
#endif
            if((File.GetAttributes(resolved)&FileAttributes.Directory)==0)throw new ArgumentException("请选择目录，而不是文件。");
            // Enumerate at most one entry; no recursive walk or file-content read.
            using(var entries=Directory.EnumerateFileSystemEntries(resolved).GetEnumerator())entries.MoveNext();
            read=Outcome("available","已通过实际后端读取目录，不递归扫描文件。");
        } catch(Exception error) {read=Failed(error);}
        if(writeTest&&resolved!=null) {
            string probe=Path.Combine(resolved,".local-workspace-access-"+Guid.NewGuid().ToString("N")+".tmp");
            bool created=false,succeeded=false;
            try {
                if((File.GetAttributes(resolved)&FileAttributes.Directory)==0)throw new ArgumentException("请选择目录，而不是文件。");
                using(var stream=new FileStream(probe,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                    created=true;byte[] data=Encoding.UTF8.GetBytes("Local Workspace access check\n");stream.Write(data,0,data.Length);
                }
                write=Outcome("available","已创建并写入独立临时文件。");
                succeeded=true;
            } catch(Exception error) {write=Failed(error);}
            finally {
                if(created)try {File.Delete(probe);}
                catch(Exception error) {artifact=probe;write=Outcome("cleanup_required","检查临时文件未能删除："+error.Message,"PROBE_CLEANUP_REQUIRED");}
            }
            if(succeeded&&artifact==null)write=Outcome("available","创建、写入、删除临时文件均已通过；原有文件未修改。");
        }
        return new {path=requested,canonical_path=resolved,checked_at=DateTime.UtcNow.ToString("o"),read=read,write=write,probe_file=artifact,
            scope="仅此路径、当前后端进程与检查时刻的结果。选择目录不会自动扩大 MCP 的文件范围，也不能代替 macOS 授权。"};
    }
}
