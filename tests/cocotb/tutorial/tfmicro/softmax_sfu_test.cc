// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <cstddef>
#include <cstdint>

#include "sw/utils/utils.h"

namespace {

constexpr size_t kMaxSoftmaxInput = 256;
inline float SigmoidPiecewise(float x) {
  const bool neg = x < 0.0f;
  const float ax = neg ? -x : x;
  float y = 0.5f;

  if (neg) {
    if (ax >= 4.0f) y = 0.0f;
    else if (ax >= 3.0f) y = 0.047425873f;
    else if (ax >= 2.0f) y = 0.11920292f;
    else if (ax >= 1.5f) y = 0.18242552f;
    else if (ax >= 1.0f) y = 0.26894143f;
    else if (ax >= 0.5f) y = 0.37754068f;
    else y = 0.5f;
  } else {
    if (ax >= 4.0f) y = 1.0f;
    else if (ax >= 3.0f) y = 0.95257413f;
    else if (ax >= 2.0f) y = 0.88079708f;
    else if (ax >= 1.5f) y = 0.81757448f;
    else if (ax >= 1.0f) y = 0.73105858f;
    else if (ax >= 0.5f) y = 0.62245935f;
    else y = 0.5f;
  }
  return y;
}

inline float ExpFromSigmoid(float sigmoid) {
  if (sigmoid <= 0.0f) return 0.0f;
  if (sigmoid >= 1.0f) return 1.0e9f;
  return sigmoid / (1.0f - sigmoid);
}

inline float SoftmaxInputMax(const float* input, int32_t size) {
  float max_val = input[0];
  for (int32_t i = 1; i < size; ++i) {
    if (input[i] > max_val) max_val = input[i];
  }
  return max_val;
}

inline void ComputeDeltas(const float* input, float* deltas, int32_t size,
                          float max_val) {
  for (int32_t i = 0; i < size; ++i) {
    deltas[i] = input[i] - max_val;
  }
}

inline void ScalarSigmoid(const float* input, float* output, int32_t size) {
  for (int32_t i = 0; i < size; ++i) {
    output[i] = SigmoidPiecewise(input[i]);
  }
}

inline void VectorSigmoidSfu(const float* input, float* output, int32_t size) {
  int32_t i = 0;
  while (i < size) {
    size_t vl = 0;
    asm volatile(
        "vsetvli %[vl], %[remaining], e32, m8, ta, ma\n"
        "vle32.v v8, (%[src])\n"
        ".word 0x4e831857\n"
        "vse32.v v16, (%[dst])\n"
        : [vl] "=r"(vl)
        : [remaining] "r"(size - i),
          [src] "r"(input + i),
          [dst] "r"(output + i)
        : "memory");
    i += static_cast<int32_t>(vl);
  }
}

inline void NormalizeFromSigmoid(const float* sigmoid_values, float* output,
                                 int32_t size) {
  float sum = 0.0f;
  for (int32_t i = 0; i < size; ++i) {
    float exp_approx = ExpFromSigmoid(sigmoid_values[i]);
    output[i] = exp_approx;
    sum += exp_approx;
  }

  float inv_sum = 1.0f / sum;
  for (int32_t i = 0; i < size; ++i) {
    output[i] *= inv_sum;
  }
}

}  // namespace

extern "C" {

int32_t input_size __attribute__((section(".data")));
float input_data[kMaxSoftmaxInput] __attribute__((section(".data"), aligned(16)));
float ref_output[kMaxSoftmaxInput] __attribute__((section(".data"), aligned(16)));
float opt_output[kMaxSoftmaxInput] __attribute__((section(".data"), aligned(16)));
float ref_sigmoid[kMaxSoftmaxInput] __attribute__((section(".data"), aligned(16)));
float opt_sigmoid[kMaxSoftmaxInput] __attribute__((section(".data"), aligned(16)));

uint64_t ref_cycles __attribute__((section(".data")));
uint64_t opt_cycles __attribute__((section(".data")));
uint64_t ref_nonlinear_cycles __attribute__((section(".data")));
uint64_t opt_nonlinear_cycles __attribute__((section(".data")));

void run_ref() __attribute__((used, retain));
void run_optimized() __attribute__((used, retain));

void run_ref() {
  float deltas[kMaxSoftmaxInput];
  float max_val = SoftmaxInputMax(input_data, input_size);
  ComputeDeltas(input_data, deltas, input_size, max_val);

  uint64_t start = mcycle_read();
  uint64_t nonlinear_start = mcycle_read();
  ScalarSigmoid(deltas, ref_sigmoid, input_size);
  ref_nonlinear_cycles = mcycle_read() - nonlinear_start;
  NormalizeFromSigmoid(ref_sigmoid, ref_output, input_size);
  ref_cycles = mcycle_read() - start;
}

void run_optimized() {
  float deltas[kMaxSoftmaxInput];
  float max_val = SoftmaxInputMax(input_data, input_size);
  ComputeDeltas(input_data, deltas, input_size, max_val);

  uint64_t start = mcycle_read();
  uint64_t nonlinear_start = mcycle_read();
  VectorSigmoidSfu(deltas, opt_sigmoid, input_size);
  opt_nonlinear_cycles = mcycle_read() - nonlinear_start;
  NormalizeFromSigmoid(opt_sigmoid, opt_output, input_size);
  opt_cycles = mcycle_read() - start;
}

void (*impl)() __attribute__((section(".data"))) = run_optimized;

int main(void) {
  impl();
  return 0;
}

}  // extern "C"
