#!/usr/bin/env python3
"""Golden model and vector generator for rvv_backend_pe_wrapper."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import random


@dataclass(frozen=True)
class PEVector:
    mode: int
    src0: int
    src0_is_signed: int
    src1: int
    src1_is_signed: int
    expected: int


def mask(width: int) -> int:
    return (1 << width) - 1


def pack_fp(data_width: int, exp_width: int, man_width: int, sign_bit: int, exp_bits: int, frac_bits: int) -> int:
    return (((sign_bit & 1) << (data_width - 1))
            | ((exp_bits & mask(exp_width)) << man_width)
            | (frac_bits & mask(man_width)))


def model_int_mul(data_width: int, lhs: int, lhs_signed: int, rhs: int, rhs_signed: int) -> int:
    lhs_raw = lhs & mask(data_width)
    rhs_raw = rhs & mask(data_width)

    if lhs_signed and ((lhs_raw >> (data_width - 1)) & 1):
      lhs_val = lhs_raw - (1 << data_width)
    else:
      lhs_val = lhs_raw

    if rhs_signed and ((rhs_raw >> (data_width - 1)) & 1):
      rhs_val = rhs_raw - (1 << data_width)
    else:
      rhs_val = rhs_raw

    return (lhs_val * rhs_val) & mask(2 * data_width)


def model_fp_mul(data_width: int, exp_width: int, man_width: int, exp_bias: int, lhs: int, rhs: int) -> int:
    exp_max = mask(exp_width)
    frac_mask = mask(man_width)

    sign0 = (lhs >> (data_width - 1)) & 1
    sign1 = (rhs >> (data_width - 1)) & 1
    result_sign = sign0 ^ sign1

    exp0 = (lhs >> man_width) & exp_max
    exp1 = (rhs >> man_width) & exp_max
    frac0 = lhs & frac_mask
    frac1 = rhs & frac_mask

    zero0 = exp0 == 0 and frac0 == 0
    zero1 = exp1 == 0 and frac1 == 0
    special0 = exp0 == exp_max
    special1 = exp1 == exp_max

    if zero0 or zero1:
        return 0
    if special0 or special1:
        return (result_sign << (data_width - 1)) | (exp_max << man_width)

    if exp0 == 0:
        sig0 = frac0
        exp0_eff = 1 - exp_bias
    else:
        sig0 = (1 << man_width) | frac0
        exp0_eff = exp0 - exp_bias

    if exp1 == 0:
        sig1 = frac1
        exp1_eff = 1 - exp_bias
    else:
        sig1 = (1 << man_width) | frac1
        exp1_eff = exp1 - exp_bias

    prod_sig = sig0 * sig1
    if prod_sig == 0:
        return 0

    sig_width = man_width + 1
    prod_width = 2 * sig_width
    if (prod_sig >> (prod_width - 1)) & 1:
        norm_sig = prod_sig >> sig_width
        norm_exp = exp0_eff + exp1_eff + 1
    else:
        norm_sig = prod_sig >> man_width
        norm_exp = exp0_eff + exp1_eff

    pack_exp = norm_exp + exp_bias
    if pack_exp <= 0:
        return 0
    if pack_exp >= exp_max:
        return (result_sign << (data_width - 1)) | (exp_max << man_width)

    return (((result_sign & 1) << (data_width - 1))
            | ((pack_exp & exp_max) << man_width)
            | (norm_sig & frac_mask))


def int_vectors(mode: int, data_width: int) -> list[PEVector]:
    vectors: list[PEVector] = []
    for src0_signed in (0, 1):
        for src1_signed in (0, 1):
            for src0 in range(1 << data_width):
                for src1 in range(1 << data_width):
                    vectors.append(
                        PEVector(
                            mode=mode,
                            src0=src0,
                            src0_is_signed=src0_signed,
                            src1=src1,
                            src1_is_signed=src1_signed,
                            expected=model_int_mul(data_width, src0, src0_signed, src1, src1_signed),
                        )
                    )
    return vectors


def fp_vectors(mode: int, data_width: int, exp_width: int, man_width: int, exp_bias: int) -> list[PEVector]:
    vectors: list[PEVector] = []
    for src0 in range(1 << data_width):
        for src1 in range(1 << data_width):
            vectors.append(
                PEVector(
                    mode=mode,
                    src0=src0,
                    src0_is_signed=0,
                    src1=src1,
                    src1_is_signed=0,
                    expected=model_fp_mul(data_width, exp_width, man_width, exp_bias, src0, src1),
                )
            )
    return vectors


def sampled_fp_vectors(mode: int, data_width: int, exp_width: int, man_width: int, exp_bias: int, rng: random.Random) -> list[PEVector]:
    vectors: list[PEVector] = []
    edge_values = [
        0,
        pack_fp(data_width, exp_width, man_width, 0, 1, 0),
        pack_fp(data_width, exp_width, man_width, 1, 1, 0),
        pack_fp(data_width, exp_width, man_width, 0, exp_bias, 0),
        pack_fp(data_width, exp_width, man_width, 1, exp_bias, 0),
        pack_fp(data_width, exp_width, man_width, 0, mask(exp_width), 0),
        pack_fp(data_width, exp_width, man_width, 1, mask(exp_width), 0),
        pack_fp(data_width, exp_width, man_width, 0, 0, 1),
        pack_fp(data_width, exp_width, man_width, 1, 0, 1),
        pack_fp(data_width, exp_width, man_width, 0, mask(exp_width) - 1, mask(man_width)),
        pack_fp(data_width, exp_width, man_width, 1, mask(exp_width) - 1, mask(man_width)),
    ]

    seen: set[tuple[int, int]] = set()

    for lhs in edge_values:
        for rhs in edge_values:
            key = (lhs, rhs)
            if key in seen:
                continue
            seen.add(key)
            vectors.append(
                PEVector(
                    mode=mode,
                    src0=lhs,
                    src0_is_signed=0,
                    src1=rhs,
                    src1_is_signed=0,
                    expected=model_fp_mul(data_width, exp_width, man_width, exp_bias, lhs, rhs),
                )
            )

    for _ in range(512):
        lhs = rng.randrange(1 << data_width)
        rhs = rng.randrange(1 << data_width)
        key = (lhs, rhs)
        if key in seen:
            continue
        seen.add(key)
        vectors.append(
            PEVector(
                mode=mode,
                src0=lhs,
                src0_is_signed=0,
                src1=rhs,
                src1_is_signed=0,
                expected=model_fp_mul(data_width, exp_width, man_width, exp_bias, lhs, rhs),
            )
        )

    return vectors


def build_vectors() -> list[PEVector]:
    rng = random.Random(12345)
    vectors: list[PEVector] = []

    vectors.extend(int_vectors(0, 4))   # MXINT4
    vectors.extend(int_vectors(1, 6))   # MXINT6
    vectors.extend(int_vectors(2, 8))   # MXINT8

    vectors.extend(fp_vectors(3, 4, 2, 1, 1))   # MXFP4
    vectors.extend(fp_vectors(4, 6, 3, 2, 3))   # MXFP6
    vectors.extend(fp_vectors(5, 8, 4, 3, 7))   # MXFP8
    vectors.extend(fp_vectors(6, 4, 2, 1, 1))   # FP4
    vectors.extend(fp_vectors(7, 8, 4, 3, 7))   # FP8

    vectors.extend(sampled_fp_vectors(8, 16, 5, 10, 15, rng))    # FP16
    vectors.extend(sampled_fp_vectors(9, 16, 8, 7, 127, rng))    # BF16

    vectors.append(PEVector(mode=15, src0=0x0011, src0_is_signed=0, src1=0x0022, src1_is_signed=0, expected=0))
    return vectors


def write_vectors(output_path: Path) -> None:
    vectors = build_vectors()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="ascii") as handle:
        handle.write("# mode src0 src0_is_signed src1 src1_is_signed expected\n")
        for vector in vectors:
            handle.write(
                f"{vector.mode:d} "
                f"{vector.src0:04x} {vector.src0_is_signed:d} "
                f"{vector.src1:04x} {vector.src1_is_signed:d} "
                f"{vector.expected:04x}\n"
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Output vector file path")
    args = parser.parse_args()
    write_vectors(args.output)


if __name__ == "__main__":
    main()
