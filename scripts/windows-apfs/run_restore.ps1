param([string]$Mode = 'dry')
$py = 'C:\Users\thanhnndev\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe'
Remove-Item "$PSScriptRoot\restore_$Mode.done" -ErrorAction SilentlyContinue
$p = Start-Process $py -ArgumentList "-I","`"$PSScriptRoot\apfs_restore.py`"",$Mode -PassThru -WindowStyle Hidden -RedirectStandardError "$PSScriptRoot\restore_$Mode.err"
if (-not $p.WaitForExit(600000)) { $p.Kill(); "KILLED" | Out-File "$PSScriptRoot\restore_$Mode.err" -Append }
"exit $($p.ExitCode) $(Get-Date -f s)" | Out-File "$PSScriptRoot\restore_$Mode.done"
