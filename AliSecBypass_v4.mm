//
//  SSLBypass_ultra_minimal.mm
//  最简版: 只 hook SecTrustEvaluate，无任何其他代码
//  如果这还闪退，说明 TrollStore 环境下 fishhook + Security.framework 完全不兼容
//

#import "fishhook.h"

static int (*orig_SecTrustEvaluate)(void *trust, void *result);

static int fake_SecTrustEvaluate(void *trust, void *result) {
    int ret = orig_SecTrustEvaluate(trust, result);
    if (result) *(int *)result = 4;
    return 0;
}

__attribute__((constructor))
static void init(void) {
    struct rebinding rebindings[] = {
        {"SecTrustEvaluate", (void *)fake_SecTrustEvaluate, (void **)&orig_SecTrustEvaluate}
    };
    rebind_symbols(rebindings, 1);
}
