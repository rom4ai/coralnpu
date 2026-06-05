# Coral NPU Makefile
# Convenience targets for common build and test operations.
# Underlying build system: Bazel 7.4.1

BAZEL := bazel
BAZEL_FLAGS :=
RVV_TEST := //tests/cocotb:rvv_arithmetic_cocotb_test
EML_FILTER := eml_vv_test|eml_stress_test|eml_illegal_test
BASELINE_FILTER := float32_arithmetic_m1_vanilla_ops
CHISEL_TARGETS := \
    //hdl/chisel/src/coralnpu:rvv_core_mini_axi_cc_library_emit_verilog \
    //hdl/chisel/src/coralnpu:core_mini_axi_cc_library_emit_verilog \
    //hdl/chisel/src/coralnpu:rvv_core_mini_highmem_axi_cc_library_emit_verilog \
    //hdl/chisel/src/coralnpu:rvv_core_mini_itcm512kb_dtcm512kb_axi_cc_library_emit_verilog

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo "Coral NPU Build Targets"
	@echo "========================"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ============================================================
# Chisel → Verilog
# ============================================================

.PHONY: chisel
chisel: ## Compile Chisel sources to Verilog (all targets)
	$(BAZEL) build $(BAZEL_FLAGS) $(CHISEL_TARGETS)

.PHONY: chisel-rvv
chisel-rvv: ## Compile Chisel RVV core to Verilog
	$(BAZEL) build $(BAZEL_FLAGS) //hdl/chisel/src/coralnpu:rvv_core_mini_axi_cc_library_emit_verilog

# ============================================================
# Regression tests
# ============================================================

.PHONY: test
test: ## Run full RVV arithmetic regression (26 tests)
	$(BAZEL) test $(BAZEL_FLAGS) $(RVV_TEST) --test_output=errors --test_timeout=1800

.PHONY: test-all
test-all: ## Run all cocotb tests (209 targets)
	$(BAZEL) test $(BAZEL_FLAGS) //tests/cocotb:all --test_output=errors --test_timeout=1200

.PHONY: test-baseline
test-baseline: ## Run baseline regression only (float32 vanilla ops)
	$(BAZEL) test $(BAZEL_FLAGS) $(RVV_TEST) --test_filter=$(BASELINE_FILTER) --test_output=errors

.PHONY: test-eml
test-eml: ## Run EML tests only
	$(BAZEL) test $(BAZEL_FLAGS) $(RVV_TEST) --test_filter=$(EML_FILTER) --test_output=errors

.PHONY: test-eml-vv
test-eml-vv: ## Run single VEML test
	$(BAZEL) test $(BAZEL_FLAGS) $(RVV_TEST) --test_filter=eml_vv_test --test_output=streamed

.PHONY: test-core
test-core: ## Run CoreMiniAxi sim tests
	$(BAZEL) test $(BAZEL_FLAGS) //tests/cocotb:core_mini_axi_sim_cocotb --test_output=errors

.PHONY: test-rvv-core
test-rvv-core: ## Run RvvCoreMiniAxi sim tests
	$(BAZEL) test $(BAZEL_FLAGS) //tests/cocotb:rvv_core_mini_axi_sim_cocotb --test_output=errors

.PHONY: test-load-store
test-load-store: ## Run RVV load/store tests
	$(BAZEL) test $(BAZEL_FLAGS) //tests/cocotb:rvv_load_store_test_all --test_output=errors

.PHONY: test-debug
test-debug: ## Run debug module tests
	$(BAZEL) test $(BAZEL_FLAGS) //tests/cocotb:core_mini_axi_debug_cocotb //tests/cocotb:rvv_core_mini_axi_debug_cocotb --test_output=errors

# ============================================================
# Build artifacts
# ============================================================

.PHONY: build
build: ## Build all Chisel + Verilator models
	$(BAZEL) build $(BAZEL_FLAGS) $(CHISEL_TARGETS) //tests/cocotb:rvv_core_mini_axi_model

.PHONY: build-examples
build-examples: ## Build example binaries
	$(BAZEL) build $(BAZEL_FLAGS) //examples:all

.PHONY: build-sim
build-sim: ## Build standalone simulator
	$(BAZEL) build $(BAZEL_FLAGS) //tests/verilator_sim:core_mini_axi_sim

# ============================================================
# Simulator run
# ============================================================

.PHONY: sim-hello
sim-hello: build-sim build-examples ## Run hello_world on simulator
	bazel-bin/tests/verilator_sim/core_mini_axi_sim \
		--binary bazel-bin/examples/coralnpu_v2_hello_world_add_floats.elf

# ============================================================
# Cleanup
# ============================================================

.PHONY: clean
clean: ## Clean Bazel outputs
	$(BAZEL) clean

.PHONY: clean-all
clean-all: ## Expunge all Bazel caches
	$(BAZEL) clean --expunge

# ============================================================
# Utility
# ============================================================

.PHONY: lint
lint: ## Run Verilator lint on RVV core
	$(BAZEL) build $(BAZEL_FLAGS) //hdl/verilog/rvv/design:rvv_core_lint

.PHONY: format
format: ## Format BUILD and .bzl files
	buildifier -r .

.PHONY: filelist
filelist: ## Regenerate filelist.f
	@echo "See filelist.f in repo root"
	@cat filelist.f
