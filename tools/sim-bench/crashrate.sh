#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# crashrate.sh [SECONDS] - MercuryPosterExtension crash reports ReportCrash formulated in the last N seconds
S=${1:-60}
/usr/bin/log show --last ${S}s --style compact --predicate 'process == "ReportCrash" AND eventMessage CONTAINS "Formulating fatal" AND eventMessage CONTAINS "MercuryPosterExtension"' 2>/dev/null | grep -c 'Formulating fatal'
