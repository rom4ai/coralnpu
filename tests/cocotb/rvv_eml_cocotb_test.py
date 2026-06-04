"""
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
"""

import os

import cocotb
import numpy as np
from rules.coco_tb.fixture import Fixture
from bazel_tools.tools.python.runfiles import runfiles


@cocotb.test()
async def eml_vv_test(dut):
    """EML VEML instruction test: element-wise exp(vs2) - ln(vs1).

    Uses .4byte-encoded VEML instruction (funct6=000001, funct3=OPIVV).
    Golden reference: np.exp(vs2) - np.log(max(vs1, epsilon)).
    Supports float32 only (SEW=32, LMUL=1, VLEN=128).
    """
    r = runfiles.Create()
    fixture = await Fixture.Create(dut)

    elf_name = "rvv_eml_test.elf"
    elf_path = r.Rlocation(
        "coralnpu_hw/tests/cocotb/rvv/arithmetics/" + elf_name
    )
    await fixture.load_elf_and_lookup_symbols(
        elf_path,
        ["in_buf_1", "in_buf_2", "out_buf"],
    )

    np_type = np.float32
    num_test_values = 4  # VLEN=128, SEW=32, LMUL=1 -> 4 elements

    # Use controlled inputs in the safe range for exp and ln
    # vs1 (y): positive values for ln domain, bounded to avoid huge outputs
    # vs2 (x): bounded range for exp to avoid overflow
    rng = np.random.default_rng(42)
    input_1 = rng.uniform(0.1, 5.0, num_test_values).astype(np_type)
    input_2 = rng.uniform(-2.0, 2.0, num_test_values).astype(np_type)
    input_d = np.zeros(num_test_values, dtype=np_type)

    await fixture.write("in_buf_1", input_1)
    await fixture.write("in_buf_2", input_2)
    await fixture.write("out_buf", input_d)

    await fixture.run_to_halt()

    actual_output = (await fixture.read("out_buf", 16)).view(np_type)

    # Golden reference: exp(vs2) - ln(vs1)
    # Use np.maximum to guard against negative/zero ln inputs
    expected_output = (
        np.exp(input_2)
        - np.log(np.maximum(input_1, np.finfo(np_type).tiny))
    ).astype(np_type)

    # Compare with tolerance for hardware LUT approximation
    # EMLUnit uses LUT-based ExpApprox and LnApprox; expect ~1-2 ULP error
    atol = 1e-3
    np.testing.assert_allclose(
        actual_output, expected_output, atol=atol, rtol=1e-4
    )
