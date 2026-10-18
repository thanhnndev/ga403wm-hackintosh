-- itl-grp19-ab: A/B the group-TX wcid inside one boot, then put it back.
--   grp19=1 for 30 s: mt76's BSS wcid 19 + its STA_REC records (reconnect at level 6 so the records go out);
--   grp19=0: back to the proven AP-wcid path, reconnect again.
-- Run:  osascript tools/itl-grp19-ab.applescript        (one administrator prompt)
-- Needs ~/itlctl (tools/itlctl.c, built next to the driver kext).
do shell script "/Users/thanhnndev/itlctl itl_grp19=1 itl_lvl=6; sleep 30; /Users/thanhnndev/itlctl itl_grp19=0 itl_lvl=6" with administrator privileges
