-- awdl-vif-test: exercise AWDL interface creation (APPLE80211_IOC_VIRTUAL_IF_CREATE, role 6 = AWDL) on en5.
-- The two panics of 2026-10-17 came from the AWDL interface never running start(): attachToBpf dereferenced a NULL
-- controller. The fix (deferBSDAttach -> start(ctl) -> register -> registerService + setRunningState(false) ->
-- deferBSDAttach) is in the native kext that is running right now.
-- Expected on success: rc=0, bsd_name='awdl0', "awdl:vif started" / "awdl:vif up" in itlmt-native-trace, ifconfig awdl0
-- exists, no panic. If the machine panics here, the fix is not enough - tell me and I will take the log apart.
set out to do shell script "/Users/thanhnndev/vif_create_test en5 2>&1" with administrator privileges
set tr to ""
try
	set tr to do shell script "nvram -p | tr ';' '\\n' | grep -i awdl | tail -6"
end try
set ifs to ""
try
	set ifs to do shell script "ifconfig awdl0 2>&1 | head -4"
end try
display dialog out & return & return & "trace:" & return & tr & return & return & "ifconfig awdl0:" & return & ifs buttons {"OK"} default button 1 with title "AWDL vif create test"
