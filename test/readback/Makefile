# Host tests for the readback instrumentation / fix (Linux or macOS, no GPU). `make test`; `make test SAN=` without sanitizers
CC ?= cc
SAN ?= -fsanitize=address,undefined
CFLAGS ?= -std=gnu11 -Wall -Wextra -Wno-unused-function -g $(SAN)
OUT ?= .build

all: test
$(OUT):
	mkdir -p $(OUT)
$(OUT)/surfstat_test: surfstat_test.c ../../patches/nullmoth-readback/files/plugin/nvmtl_surfstat.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
$(OUT)/pend_test: pend_test.c ../../patches/nullmoth-readback/files/kexts/NVRM/accel/nvsv_pend.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
$(OUT)/sync_model_test: sync_model_test.c ../../patches/nullmoth-readback/files/kexts/NVRM/accel/nvsv_pend.h ../../patches/nullmoth-readback/files/plugin/nvmtl_surfstat.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
test: $(OUT)/surfstat_test $(OUT)/pend_test $(OUT)/sync_model_test
	$(OUT)/surfstat_test && $(OUT)/pend_test && $(OUT)/sync_model_test 2>/dev/null
clean:
	rm -rf $(OUT)
.PHONY: all test clean
