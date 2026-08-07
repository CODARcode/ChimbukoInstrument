#if defined(__HIP_DEVICE_COMPILE__) || defined(__SYCL_DEVICE_ONLY__) || defined(__CUDA_ARCH__)
#define PERFSTUBS_TIMER_START_FUNC(A)
#define PERFSTUBS_TIMER_STOP_FUNC(A)
#define PERFSTUBS_INITIALIZE()
#else
#define PERFSTUBS_USE_TIMERS
#include "perfstubs_api/timer.h"
#endif
