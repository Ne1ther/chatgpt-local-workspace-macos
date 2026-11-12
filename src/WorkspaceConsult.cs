using System;
using System.IO;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

// Deliberately independent of WorkspaceStore: CLI callers coexist with its exclusive owner.lock.
static class WorkspaceConsult
{
    static readonly UTF8Encoding Utf8=new UTF8Encoding(false,true);
    static readonly object Gate=new object();
    static JavaScriptSerializer Json {get{return new JavaScriptSerializer{MaxJsonLength=8*1024*1024};}}
    static string Now(){return DateTime.UtcNow.ToString("o");}
    static string Stamp(){return DateTime.UtcNow.ToString("yyyyMMddTHHmmssZ");}
    static string Text(IDictionary<string,object> map,string key,string fallback=""){object v;if(!map.TryGetValue(key,out v))return fallback;if(!(v is string))throw new ArgumentException(key+" must be a string");return (string)v;}
    static int Number(IDictionary<string,object> map,string key,int fallback,int min,int max){object v;if(!map.TryGetValue(key,out v))return fallback;if(!(v is int)&&!(v is long)&&!(v is decimal))throw new ArgumentException(key+" must be an integer");decimal n=Convert.ToDecimal(v);if(n!=Math.Truncate(n)||n<min||n>max)throw new ArgumentException(key+" must be between "+min+" and "+max);return (int)n;}
    static string Id(string id,bool generate=false){if(id.Length==0&&generate)id="pro-"+Stamp();if(!Regex.IsMatch(id,@"\A[A-Za-z0-9._-]{1,80}\z")||id=="."||id=="..")throw new ArgumentException("consult_id must match [A-Za-z0-9._-]{1,80}");return id;}
    static void PrivateDirectory(string path)
    {
        if(File.Exists(path)||(Directory.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0))throw new IOException("Consult state directory must not be a link or file: "+path);
#if MACOS
        Directory.CreateDirectory(path,UnixFileMode.UserRead|UnixFileMode.UserWrite|UnixFileMode.UserExecute);
        File.SetUnixFileMode(path,UnixFileMode.UserRead|UnixFileMode.UserWrite|UnixFileMode.UserExecute);
#else
        Directory.CreateDirectory(path);
#endif
    }
    static string Root()
    {
        string root=Environment.GetEnvironmentVariable("WORKSPACE_CONSULT_DIR");
        if(string.IsNullOrEmpty(root)){
#if MACOS
            root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"Library","Application Support","LocalWorkspacePlugin","consult-v1");
#else
            root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"LocalWorkspacePlugin","consult-v1");
#endif
        }
        root=WorkspaceServer.Full(root);PrivateDirectory(root);PrivateDirectory(Path.Combine(root,"sessions"));PrivateDirectory(Path.Combine(root,"receipts"));return root;
    }
    static string StateFile(string folder,string id){return WorkspaceServer.Full(Path.Combine(Root(),folder,Id(id)+".json"));}
    static Dictionary<string,object> Load(string path,bool optional=false)
    {
        path=WorkspaceServer.Full(path,true);if(optional&&!File.Exists(path))return new Dictionary<string,object>();
        using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
            if(stream.Length>1048576)throw new ArgumentException("Consult metadata exceeds 1 MiB");
            using(var reader=new StreamReader(stream,Utf8,true))return Json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd())??new Dictionary<string,object>();
        }
    }
    static void Atomic(string path,object value)
    {
        path=WorkspaceServer.Full(path);string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{Create(temp,Utf8.GetBytes(Json.Serialize(value)+"\n"));if(File.Exists(path))File.Replace(temp,path,null);else try{File.Move(temp,path);}catch(IOException){if(!File.Exists(path))throw;File.Replace(temp,path,null);}}
        finally{if(File.Exists(temp))File.Delete(temp);}
    }
    static void Create(string path,byte[] bytes){path=WorkspaceServer.Full(path);using(var s=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)){s.Write(bytes,0,bytes.Length);s.Flush();}}
    static string Hash(byte[] bytes){using(var sha=SHA256.Create())return Hex(sha.ComputeHash(bytes));}
    static string Hex(byte[] bytes){return BitConverter.ToString(bytes).Replace("-","").ToLowerInvariant();}
    static string FileHash(string path){using(var stream=File.OpenRead(WorkspaceServer.Full(path,true)))using(var sha=SHA256.Create())return Hex(sha.ComputeHash(stream));}
    static int Lines(string content){if(content.Length==0)return 0;return content.Count(c=>c=='\n')+(content.EndsWith("\n")?0:1);}
    static void Paths(object raw,List<string> paths)
    {
        var list=raw as IList;if(list==null||raw is string||list.Count>20)throw new ArgumentException("paths/files must be an array");
        foreach(object item in list){string path=item as string;var map=item as IDictionary<string,object>;if(path==null&&map!=null)path=Text(map,"path");if(string.IsNullOrWhiteSpace(path))throw new ArgumentException("Every bundle file needs a path");paths.Add(WorkspaceServer.Full(path,true));}
    }
    static void Manifest(Dictionary<string,object> map,List<string> paths){object raw;if(map.TryGetValue("paths",out raw))Paths(raw,paths);if(map.TryGetValue("files",out raw))Paths(raw,paths);string brief=Text(map,"brief");if(brief.Length>0)paths.Insert(0,WorkspaceServer.Full(brief,true));}
    static List<string> Unique(List<string> paths){var unique=paths.Distinct(WorkspaceContext.PathComparer).ToList();if(unique.Count>20)throw new ArgumentException("At most 20 bundle files are allowed");return unique;}
    static string BundleHash(IEnumerable<object> identities){return Hash(Utf8.GetBytes(Json.Serialize(identities.ToArray())));}
    static object Identity(string path,long size,string sha){return new{path=path,size_bytes=size,sha256=sha};}

    public static object Read(Dictionary<string,object> args)
    {
        lock(Gate){
            int per=Number(args,"max_bytes_per_file",65536,1024,262144),total=Number(args,"total_max_bytes",393216,4096,1048576);
            string id=Text(args,"consult_id"),bundle=Text(args,"bundle_path");var session=id.Length>0?Load(StateFile("sessions",Id(id)),true):new Dictionary<string,object>();
            var metadata=new Dictionary<string,object>(session);var paths=new List<string>();Manifest(session,paths);
            if(bundle.Length>0){
                string trimmed=bundle.TrimStart();object document=null;
                if(trimmed.StartsWith("{")||trimmed.StartsWith("["))document=Json.Deserialize<object>(bundle);
                else {bundle=WorkspaceServer.Full(bundle,true);if(Path.GetExtension(bundle).Equals(".json",StringComparison.OrdinalIgnoreCase))document=Load(bundle);else paths.Add(bundle);}
                var map=document as Dictionary<string,object>;if(map!=null){Manifest(map,paths);if(id.Length==0&&map.ContainsKey("consult_id"))id=Id(Text(map,"consult_id"));foreach(string key in new[]{"title","instructions","inbox_dir"})if(map.ContainsKey(key)&&!metadata.ContainsKey(key))metadata[key]=Text(map,key);}
                else if(document!=null)Paths(document,paths);
            }
            object direct;if(args.TryGetValue("paths",out direct))Paths(direct,paths);paths=Unique(paths);if(paths.Count==0)throw new ArgumentException("Provide consult_id, bundle_path or paths containing at least one file");
            var files=new List<object>();var identities=new List<object>();int used=0,truncated=0;
            foreach(string requested in paths){
                string path=WorkspaceServer.Full(requested,true);byte[] bytes;long size;string sha;int lineCount=0;bool any=false;byte last=0;
                using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))using(var digest=SHA256.Create()){
                    size=stream.Length;int budget=Math.Min(per,total-used);using(var prefix=new MemoryStream()){
                        byte[] chunk=new byte[8192];int n;while((n=stream.Read(chunk,0,chunk.Length))>0){digest.TransformBlock(chunk,0,n,chunk,0);for(int i=0;i<n;i++)if(chunk[i]==10)lineCount++;any=true;last=chunk[n-1];int keep=Math.Min(n,budget-(int)prefix.Length);if(keep>0)prefix.Write(chunk,0,keep);}
                        digest.TransformFinalBlock(new byte[0],0,0);sha=Hex(digest.Hash);bytes=prefix.ToArray();
                    }
                }
                if(any&&last!=10)lineCount++;
                // Drop an incomplete trailing UTF-8 code point at a byte boundary.
                int length=bytes.Length;if(size>length&&length>0){int start=length-1;while(start>0&&(bytes[start]&0xc0)==0x80)start--;int lead=bytes[start],need=lead>=0xf0?4:lead>=0xe0?3:lead>=0xc0?2:1;if(length-start<need)length=start;}
                string content=Utf8.GetString(bytes,0,length);int returned=Utf8.GetByteCount(content);used+=returned;bool cut=size>length;if(cut)truncated++;
                identities.Add(Identity(path,size,sha));files.Add(new{path=path,size_bytes=size,line_count=lineCount,truncated=cut,sha256=sha,content=content});
            }
            string hash=BundleHash(identities),at=Now(),thread=WorkspaceServer.CurrentThread??"unassigned";
            var status=new Dictionary<string,object>{{"status","reading"},{"consult_id",id},{"last_read_at",at},{"bundle_sha256",hash},{"thread_id",thread}};
            if(id.Length>0){foreach(var kv in metadata)session[kv.Key]=kv.Value;session["paths"]=paths.ToArray();foreach(var kv in status)session[kv.Key]=kv.Value;Atomic(StateFile("sessions",id),session);}Atomic(Path.Combine(Root(),"status.json"),status);
            return new{consult_id=id,title=Text(metadata,"title"),instructions=Text(metadata,"instructions"),inbox_dir=Text(metadata,"inbox_dir"),file_count=files.Count,total_bytes=used,truncated_count=truncated,bundle_sha256=hash,files=files};
        }
    }
    static void Complete(string id,Dictionary<string,object> receipt)
    {
        Atomic(StateFile("receipts",id),receipt);var status=new Dictionary<string,object>(receipt);status["status"]="completed";status["completed_at"]=Now();
        var session=Load(StateFile("sessions",id),true);foreach(var kv in status)session[kv.Key]=kv.Value;Atomic(StateFile("sessions",id),session);Atomic(Path.Combine(Root(),"status.json"),status);
    }
    static Dictionary<string,object> Receipt(string id,string stem,string structured,byte[] bytes,string hash,string content,Dictionary<string,object> args,Dictionary<string,object> session)
    {
        string report=WorkspaceServer.Full(stem+".md"),receiptPath=WorkspaceServer.Full(stem+".receipt.json"),structuredPath="";
        if(!string.IsNullOrWhiteSpace(structured)){
            structuredPath=WorkspaceServer.Full(stem+".structured.json");if(!File.Exists(structuredPath))Create(structuredPath,Utf8.GetBytes(structured));
            else if(FileHash(structuredPath)!=Hash(Utf8.GetBytes(structured)))throw new IOException("Structured report already exists with different content");
        }
        var receipt=new Dictionary<string,object>{{"consult_id",id},{"title",Text(args,"title",Text(session,"title"))},{"summary",Text(args,"summary")},{"report_path",report},{"receipt_path",receiptPath},{"structured_json_path",structuredPath},{"sha256",hash},{"byte_length",bytes.Length},{"line_count",Lines(content)},{"created_at",Now()},{"thread_id",WorkspaceServer.CurrentThread??"unassigned"}};
        Create(receiptPath,Utf8.GetBytes(Json.Serialize(receipt)+"\n"));Complete(id,receipt);return receipt;
    }
    public static object Submit(Dictionary<string,object> args)
    {
        lock(Gate){
            string content=Text(args,"content");if(string.IsNullOrWhiteSpace(content))throw new ArgumentException("content must be non-empty Markdown");
            string id=Id(Text(args,"consult_id"),true);var session=Load(StateFile("sessions",id),true);string inbox=Text(args,"inbox_dir",Text(session,"inbox_dir"));if(inbox.Length==0)throw new ArgumentException("inbox_dir is required without a staged session");
            inbox=WorkspaceServer.Full(inbox);string structured=Text(args,"structured_json");if(!string.IsNullOrWhiteSpace(structured))Json.Deserialize<object>(structured);
            byte[] bytes=Utf8.GetBytes(content);string hash=Hash(bytes);Directory.CreateDirectory(inbox);
            string stem=Path.Combine(inbox,id),baseStem=stem;int collision=0;
            // Find earlier timestamped reports too: retries must remain idempotent after the clock changes.
            var candidates=new List<string>{baseStem+".md"};
            candidates.AddRange(Directory.GetFiles(inbox,id+"__*.md").Where(p=>Regex.IsMatch(Path.GetFileName(p),"^"+Regex.Escape(id)+@"__\d{8}T\d{6}Z(__\d+)?\.md$")).OrderBy(p=>p,StringComparer.Ordinal));
            foreach(string candidate in candidates){
                string report=WorkspaceServer.Full(candidate,true);if(!File.Exists(report)||FileHash(report)!=hash)continue;
                string oldStem=report.Substring(0,report.Length-3),receiptPath=WorkspaceServer.Full(oldStem+".receipt.json");
                if(File.Exists(receiptPath)){
                    var existing=Load(receiptPath);if(Text(existing,"sha256")==hash&&Text(existing,"consult_id")==id&&Text(existing,"report_path")==report){Complete(id,existing);return existing;}
                }else if(!Directory.Exists(receiptPath)){
                    string attachment=WorkspaceServer.Full(oldStem+".structured.json");
                    if(!File.Exists(attachment)&&!Directory.Exists(attachment)||(!string.IsNullOrWhiteSpace(structured)&&File.Exists(attachment)&&FileHash(attachment)==Hash(Utf8.GetBytes(structured))))return Receipt(id,oldStem,structured,bytes,hash,content,args,session);
                }
            }
            while(true){
                string report=WorkspaceServer.Full(stem+".md"),receiptPath=WorkspaceServer.Full(stem+".receipt.json"),structuredPath=WorkspaceServer.Full(stem+".structured.json");
                // Reserve all sidecar names as well: no prior report, receipt or structured file is replaced.
                if(!File.Exists(report)&&!Directory.Exists(report)&&!File.Exists(receiptPath)&&!Directory.Exists(receiptPath)&&!File.Exists(structuredPath)&&!Directory.Exists(structuredPath)){
                    try{Create(report,bytes);}catch(IOException){if(!File.Exists(report))throw;collision++;stem=baseStem+"__"+Stamp()+(collision>1?"__"+collision:"");continue;}
                    return Receipt(id,stem,structured,bytes,hash,content,args,session);
                }
                collision++;stem=baseStem+"__"+Stamp()+(collision>1?"__"+collision:"");
            }
        }
    }
    static Dictionary<string,object> Status(string id)
    {
        if(id.Length==0)return Load(Path.Combine(Root(),"status.json"),true);
        var session=Load(StateFile("sessions",Id(id)),true);var receipt=Load(StateFile("receipts",id),true);if(receipt.Count>0){session["receipt"]=receipt;session["status"]="completed";}if(session.Count==0){session["consult_id"]=id;session["status"]="unknown";}return session;
    }
    public static bool TryCli(string[] args)
    {
        if(args.Length==0||!new[]{"--stage-consult","--consult-status","--consult-list"}.Contains(args[0]))return false;
        try{
            var options=new Dictionary<string,object>();var paths=new List<string>();
            string[] allowed=args[0]=="--stage-consult"?new[]{"--id","--inbox","--title","--instructions","--brief","--file"}:args[0]=="--consult-status"?new[]{"--id","--wait-seconds"}:new string[0];
            for(int i=1;i<args.Length;i++){string key=args[i];if(!allowed.Contains(key)||i+1==args.Length)throw new ArgumentException("Unknown or incomplete option: "+key);string value=args[++i];if(key=="--file"||key=="--brief")paths.Add(WorkspaceServer.Full(value,true));else{if(options.ContainsKey(key))throw new ArgumentException("Duplicate option: "+key);options[key]=value;}}
            if(args[0]=="--stage-consult"){
                string id=Id(Text(options,"--id")),inbox=WorkspaceServer.Full(Text(options,"--inbox"));paths=Unique(paths);if(paths.Count==0)throw new ArgumentException("Stage at least one --brief or --file");
                var identities=new List<object>();foreach(string path in paths){if(!File.Exists(path))throw new FileNotFoundException("Bundle file does not exist",path);identities.Add(Identity(path,new FileInfo(path).Length,FileHash(path)));}
                string hash=BundleHash(identities),bundle=WorkspaceServer.Full(Path.Combine(inbox,id+".bundle.json")),sessionPath=StateFile("sessions",id);if(File.Exists(sessionPath))throw new IOException("Consult ID already exists; use a new ID");
                var session=new Dictionary<string,object>{{"consult_id",id},{"title",Text(options,"--title")},{"instructions",Text(options,"--instructions")},{"inbox_dir",inbox},{"bundle_path",bundle},{"paths",paths.ToArray()},{"files",identities},{"file_count",paths.Count},{"bundle_sha256",hash},{"status","staged"},{"staged_at",Now()}};
                Directory.CreateDirectory(inbox);Create(bundle,Utf8.GetBytes(Json.Serialize(session)+"\n"));Create(sessionPath,Utf8.GetBytes(Json.Serialize(session)+"\n"));Atomic(Path.Combine(Root(),"status.json"),session);
                Console.WriteLine(Json.Serialize(new{ok=true,consult_id=id,title=Text(session,"title"),bundle_path=bundle,inbox_dir=inbox,file_count=paths.Count,bundle_sha256=hash,web_pro_prompt="Call read_research_bundle with consult_id="+Json.Serialize(id)+". Follow its instructions, inspect all files and disclose truncation or missing evidence. Submit your complete Markdown report through submit_pro_report with consult_id="+Json.Serialize(id)+"; include a concise summary. Return the saved report path and SHA-256."}));
            }else if(args[0]=="--consult-status"){
                int wait=0;string raw=Text(options,"--wait-seconds","0");if(!int.TryParse(raw,out wait)||wait<0||wait>3600)throw new ArgumentException("--wait-seconds must be 0..3600");
                string id=Text(options,"--id");if(id.Length>0)Id(id);var until=DateTime.UtcNow.AddSeconds(wait);Dictionary<string,object> status;
                do{status=Status(id);if(Text(status,"status")=="completed"||wait==0||DateTime.UtcNow>=until)break;System.Threading.Thread.Sleep(500);}while(true);
                Console.WriteLine(Json.Serialize(status));if(wait>0&&Text(status,"status")!="completed")Environment.ExitCode=2;
            }else{
                var ids=new HashSet<string>(StringComparer.Ordinal);foreach(string folder in new[]{"sessions","receipts"})foreach(string file in Directory.GetFiles(Path.Combine(Root(),folder),"*.json"))ids.Add(Path.GetFileNameWithoutExtension(file));
                Console.WriteLine(Json.Serialize(ids.Select(id=>Status(id)).OrderByDescending(s=>Text(s,"completed_at",Text(s,"last_read_at",Text(s,"staged_at")))).Take(100).ToArray()));
            }
        }catch(Exception error){Console.WriteLine(Json.Serialize(new{ok=false,error_code=WorkspaceAccess.ErrorCode(error),message=error.Message}));Environment.ExitCode=1;}
        return true;
    }
}
