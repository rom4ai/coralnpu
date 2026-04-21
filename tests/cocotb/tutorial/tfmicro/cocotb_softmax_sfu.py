# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import cocotb
import numpy as np
from bazel_tools.tools.python.runfiles import runfiles
from coralnpu_test_utils.sim_test_fixture import Fixture


class SoftmaxSfuTester:
    def __init__(self, input_size):
        self.input_size = input_size
        r = runfiles.Create()
        self.elf_file = r.Rlocation(
            "coralnpu_hw/tests/cocotb/tutorial/tfmicro/softmax_sfu_test.elf"
        )
        self.fixture = None

    async def setup(self, dut):
        self.fixture = await Fixture.Create(dut, highmem=True)
        await self.fixture.load_elf_and_lookup_symbols(
            self.elf_file,
            [
                "impl",
                "run_ref",
                "run_optimized",
                "input_size",
                "input_data",
                "ref_output",
                "opt_output",
                "ref_cycles",
                "opt_cycles",
                "ref_nonlinear_cycles",
                "opt_nonlinear_cycles",
            ],
        )

        rng = np.random.default_rng(seed=123)
        # Keep the input range bounded so the piecewise approximation remains
        # well behaved and the softmax denominator is stable.
        inputs = rng.uniform(-3.0, 3.0, self.input_size).astype(np.float32)

        await self.fixture.write_word("input_size", self.input_size)
        await self.fixture.write("input_data", inputs)
        self.inputs = inputs

    async def run(self, func_ptr: str, timeout_cycles: int):
        await self.fixture.write_ptr("impl", func_ptr)
        await self.fixture.run_to_halt(timeout_cycles=timeout_cycles)

        output_symbol = "ref_output" if func_ptr == "run_ref" else "opt_output"
        cycle_symbol = "ref_cycles" if func_ptr == "run_ref" else "opt_cycles"
        nonlinear_cycle_symbol = (
            "ref_nonlinear_cycles"
            if func_ptr == "run_ref"
            else "opt_nonlinear_cycles"
        )

        outputs = (
            await self.fixture.read(output_symbol, self.input_size * 4)
        ).view(np.float32)
        total_cycles = (await self.fixture.read(cycle_symbol, 8)).view(np.uint64)[0]
        nonlinear_cycles = (
            await self.fixture.read(nonlinear_cycle_symbol, 8)
        ).view(np.uint64)[0]
        return outputs, total_cycles, nonlinear_cycles

    async def test(self, timeout_cycles=3000000):
        ref_output, ref_cycles, ref_nonlinear_cycles = await self.run(
            "run_ref", timeout_cycles
        )
        opt_output, opt_cycles, opt_nonlinear_cycles = await self.run(
            "run_optimized", timeout_cycles
        )

        print(f"ref_cycles={ref_cycles}", flush=True)
        print(f"opt_cycles={opt_cycles}", flush=True)
        print(f"ref_nonlinear_cycles={ref_nonlinear_cycles}", flush=True)
        print(f"opt_nonlinear_cycles={opt_nonlinear_cycles}", flush=True)

        if opt_cycles > 0:
            print(f"softmax_speedup={float(ref_cycles) / opt_cycles:.2f}x", flush=True)
        if opt_nonlinear_cycles > 0:
            print(
                f"nonlinear_speedup={float(ref_nonlinear_cycles) / opt_nonlinear_cycles:.2f}x",
                flush=True,
            )

        assert np.allclose(opt_output, ref_output, atol=1e-6, rtol=1e-6)
        assert np.isclose(float(np.sum(ref_output)), 1.0, atol=1e-5)
        assert np.isclose(float(np.sum(opt_output)), 1.0, atol=1e-5)
        assert ref_cycles > 0
        assert opt_cycles > 0
        assert ref_nonlinear_cycles > 0
        assert opt_nonlinear_cycles > 0


@cocotb.test()
async def test_softmax_sfu_64(dut):
    tester = SoftmaxSfuTester(input_size=64)
    await tester.setup(dut)
    await tester.test()


@cocotb.test()
async def test_softmax_sfu_256(dut):
    tester = SoftmaxSfuTester(input_size=256)
    await tester.setup(dut)
    await tester.test(timeout_cycles=6000000)
