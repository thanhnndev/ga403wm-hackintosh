// SPDX-License-Identifier: BSD-3-Clause-Clear
// Profiles of the generated private-family declarations, not a portability claim.
// A profile is added only after tools/ioaccel_gen_header.py run against that OS's own SystemKernelExtensions.kc
// produces the declaration header already in the tree (25G241: byte-identical to 24H32, family 487.4.4 vs 485.2).
#pragma once
struct StrixABIProfile { const char *osBuild; int darwinMajor; const char *kernelBuild; const char *id; };
static const StrixABIProfile kStrixABIProfiles[] = {
    { "24H32", 24, "Darwin Kernel Version 24.6.0: Sun Aug 23 20:30:56 PDT 2026; root:xnu-11417.140.69.712.69~1/RELEASE_X86_64",
      "macos15-24H32-x86_64-ioaccel485.2" },
    { "25G241", 25, "Darwin Kernel Version 25.6.0: Tue Aug 18 17:46:40 PDT 2026; root:xnu-12377.161.15.700.19~2/RELEASE_X86_64",
      "macos26-25G241-x86_64-ioaccel487.4.4" },
};
