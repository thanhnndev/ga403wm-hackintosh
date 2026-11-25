# Admin: put the ESP config of the 14:29 good boot back (config.plist.bk-addv-20261107T164437); keep the current one.
$o = "$PSScriptRoot\esp_restore.txt"
if (-not (Test-Path 'S:\')) { & mountvol S: /s; Start-Sleep 2 }
$c = 'S:\EFI\OC\config.plist'; $g = 'S:\EFI\OC\config.plist.bk-addv-20261107T164437'
$stamp = Get-Date -Format 'yyyyMMddTHHmmss'
Copy-Item $c "$c.bk-restore-$stamp" -Force
Copy-Item $g $c -Force
"backup $c.bk-restore-$stamp" | Out-File $o
"good  $((Get-FileHash $g).Hash)" | Out-File $o -Append
"now   $((Get-FileHash $c).Hash)" | Out-File $o -Append
"saved $((Get-FileHash "$c.bk-restore-$stamp").Hash)" | Out-File $o -Append
"done $(Get-Date -f s)" | Out-File "$PSScriptRoot\esp_restore.done"
