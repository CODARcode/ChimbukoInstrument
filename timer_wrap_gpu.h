#ifdef __HIP__
//Fix issues with HIP doing some kind of __global__ device function compilation on the host pass
inline __device__ void* ps_timer_create_(const char *timer_name){}
inline __device__ void  ps_timer_start_(void *timer){}
inline __device__ void  ps_timer_stop_(void *timer){}
inline __device__ char* ps_make_timer_name_(const char * file, const char * func, int line){}
#endif

#if defined(__HIP_DEVICE_COMPILE__) || defined(__SYCL_DEVICE_ONLY__) || defined(__CUDA_ARCH__)
#warning "DEVICE COMPILE"
#define PERFSTUBS_TIMER_START_FUNC(A)
#define PERFSTUBS_TIMER_STOP_FUNC(A)
#define PERFSTUBS_INITIALIZE()
#else
#warning "HOST COMPILE"
#define PERFSTUBS_USE_TIMERS
#include "perfstubs_api/timer.h"
#endif
