param([string]$OutputDirectory = "")
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $ProjectRoot 'dist-next' }
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath "$ProjectRoot\node_modules\@tailwindcss\cli\dist\index.mjs"){
    & node "$ProjectRoot\scripts\build-dashboard.cjs"
    if($LASTEXITCODE -ne 0){throw 'Dashboard build failed'}
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$compiler=Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if(-not(Test-Path -LiteralPath $compiler)){$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'}
if(-not(Test-Path -LiteralPath $compiler)){throw 'C# compiler not found in the system .NET Framework runtime.'}
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/win32icon:$ProjectRoot\assets\local-workspace.ico" "/out:$OutputDirectory\LocalWorkspace.exe" "/resource:$ProjectRoot\src\dashboard.html,dashboard.html" "/resource:$ProjectRoot\vendor\webview2\Microsoft.Web.WebView2.Core.dll,wv2.core.dll" "/resource:$ProjectRoot\vendor\webview2\Microsoft.Web.WebView2.WinForms.dll,wv2.winforms.dll" "/resource:$ProjectRoot\vendor\webview2\WebView2Loader.dll,wv2.loader.dll" /r:Microsoft.CSharp.dll /r:System.Security.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll "/r:$ProjectRoot\vendor\webview2\Microsoft.Web.WebView2.Core.dll" "/r:$ProjectRoot\vendor\webview2\Microsoft.Web.WebView2.WinForms.dll" "$ProjectRoot\src\Program.cs" "$ProjectRoot\src\UiKit.cs" "$ProjectRoot\src\WorkbenchHost.cs" "$ProjectRoot\src\WorkspaceServer.cs" "$ProjectRoot\src\Presentation.cs" "$ProjectRoot\src\FileSearch.cs" "$ProjectRoot\src\WorkspaceContext.cs" "$ProjectRoot\src\PatchEditor.cs" "$ProjectRoot\src\WorkspaceActivity.cs" "$ProjectRoot\src\WorkspaceDetail.cs" "$ProjectRoot\src\WorkspaceThreads.cs" "$ProjectRoot\src\LocalDashboard.cs" "$ProjectRoot\src\DashboardImages.cs" "$ProjectRoot\src\WorkspaceContracts.cs" "$ProjectRoot\src\WorkspaceTasks.cs" "$ProjectRoot\src\AttachmentImport.cs" "$ProjectRoot\src\WorkspaceDiagnostics.cs" "$ProjectRoot\src\WorkspaceStore.cs" "$ProjectRoot\src\WorkspaceCredentials.cs" "$ProjectRoot\src\WorkspaceFiles.cs" "$ProjectRoot\src\WorkspaceJournal.cs" "$ProjectRoot\src\WorkspaceRequests.cs" "$ProjectRoot\src\WorkspaceReview.cs"
if($LASTEXITCODE -ne 0){throw 'Build failed'}
Copy-Item -LiteralPath "$ProjectRoot\src\dashboard.html" -Destination "$OutputDirectory\dashboard.html" -Force
Get-Item "$OutputDirectory\LocalWorkspace.exe" | Select-Object FullName,Length
