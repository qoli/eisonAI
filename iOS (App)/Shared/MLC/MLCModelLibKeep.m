#include <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR
// Force-link the Qwen3 model lib symbol so it survives archive/export stripping.
extern const unsigned char qwen3_q4f16_1_37d26ba247cc02f647af18ad629c48d2___tvm_ffi__library_bin;
__attribute__((used, visibility("default")))
const void *mlc_force_link_qwen3 =
    &qwen3_q4f16_1_37d26ba247cc02f647af18ad629c48d2___tvm_ffi__library_bin;
#endif
