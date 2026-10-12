#!/bin/bash
# Dry run: builds an auxiliary kernel collection from a scratch copy of /Library/Extensions' NullMoth kexts plus the staged
# NVRMEdpBL kext / NVRMFB, and lists the bundles it contains. Installs nothing. Needs root (kmutil rejects kexts that are
# not root:wheel): run through osascript. Log: /Users/thanhnndev/efi-audit/brightness/test-kc.log
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
B=/Users/thanhnndev/efi-audit/brightness
ST=$B/stage
[ "$(id -u)" -eq 0 ] || { echo "needs root"; exit 1; }
rm -rf $B/repo && mkdir -p $B/repo || exit 1
for k in NVAccel NVRM NVRMAGDC NVRMFB; do cp -R /Library/Extensions/$k.kext $B/repo/ || exit 1; done
cp -R $ST/NVRMEdpBL.kext $B/repo/ && cp $ST/NVRMFB $B/repo/NVRMFB.kext/Contents/MacOS/NVRMFB || exit 1
chown -R root:wheel $B/repo && chmod -R go-w $B/repo
plutil -replace OSBundleCompatibleVersion -string 0.1 $B/repo/NVRM.kext/Contents/Info.plist || exit 1
rm -f $B/aux-test.kc
kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
  -B /System/Library/KernelCollections/BootKernelExtensions.kc -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
  --repository $B/repo -A $B/aux-test.kc -z > $B/test-kc.log 2>&1
echo "kmutil rc=$?" >> $B/test-kc.log
[ -s $B/aux-test.kc ] && kmutil inspect -a x86_64 -A $B/aux-test.kc >> $B/test-kc.log 2>&1
grep -E "rc=|com.nullmoth|rror" $B/test-kc.log
