#!/bin/bash
# present-rate.sh N: per-frame present-path costs over N seconds from the NMXAccel counters (flips off or on)
k="debug.nmxaccel_iop_ok debug.nmxaccel_beam_wait_us debug.nmxaccel_beam_copy_us debug.nmxaccel_fence_wait_us debug.nmxaccel_flip_submitted debug.nmxaccel_flip_latched debug.nmxaccel_flip_wait_us debug.nmxaccel_flip_fallback"
a=$(sysctl -n $k 2>/dev/null | tr '\n' ' '); /usr/bin/perl -e "select(undef,undef,undef,${1:-10})"; b=$(sysctl -n $k 2>/dev/null | tr '\n' ' ')
echo "$a" "$b" | awk -v t=${1:-10} '{n=8; f=$(n+1)-$1; if(f<1)f=1; printf "frames %d (%.1f fps)  beam %.2f ms  copy %.2f ms  fence %.2f ms  flips sub %d lat %d wait %.2f ms fallback %d\n", f, f/t, ($(n+2)-$2)/f/1000, ($(n+3)-$3)/f/1000, ($(n+4)-$4)/f/1000, $(n+5)-$5, $(n+6)-$6, ($(n+7)-$7)/f/1000, $(n+8)-$8}'
ps -o %cpu= -p $(pgrep WindowServer) | awk '{print "WindowServer cpu " $1 "%"}'
