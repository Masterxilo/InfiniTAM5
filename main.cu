﻿/*
InfiniTAM essentials/modified in a single file

Paul Frischknecht

except for (TODO: OPTIONAL DEPENDENCE) paulwl.h (and dependence on wsprep), this is self-contained

*/

/*
Compile with nvcc sm_5 or higher

To make this CUDA debuggable, be sure to adjust then environment:

NSIGHT_CUDA_DEBUGGER=1

SetEnvironment["NSIGHT_CUDA_DEBUGGER" -> "1"]
*/

// Standard/system headers
#define _CRT_SECURE_NO_WARNINGS
#define NOMINMAX
#define WINDOWS_LEAN_AND_MEAN
#include <windows.h>


#include <cuda.h>
#include <cuda_runtime_api.h>
#include <cuda_runtime.h>
#include <device_functions.h>
#include <device_launch_parameters.h>
#pragma comment(lib,"cudart")

#define _USE_MATH_DEFINES
#include <math.h>
#include <float.h>
#include <stdio.h>
#include <stdint.h>
typedef unsigned int uint;
#include <limits.h>
#include <array>
#include <string> 
#include <vector> 
#include <map>
#include <unordered_map> 

#include <tuple>
#include <string>
#include <fstream>
#include <sstream>
#include <streambuf>
#include <iostream>
#include <string>
#include <exception>
#include <iterator>
#include <memory>
using namespace std;

// Custom headers
#define WL_WSTP_MAIN
#define WL_ALLOC_CONSOLE
#include <paulwl.h>



#pragma warning(push, 4)

#ifndef __CUDACC__
#error This file can only be compiled as a .cu file by nvcc.
#endif

#ifndef _WIN64
#error cudaMallocManaged and __managed__ require 64 bits. Also, this program is made for windows.
#endif

#if defined(__CUDA_ARCH__) && __CUDA_ARCH__ < 500
#error Always use the latest cuda arch. Old versions dont support any amount of thread blocks being submitted at once.
#endif

#ifdef __CUDA_ARCH__
#define GPU_CODE                1
#define CPU_AND_GPU_CONSTANT    __constant__
#else
#define GPU_CODE                0
#define CPU_AND_GPU_CONSTANT
#endif

#define GPU_ONLY                __device__

// Declares a pointer to device-only memory.
// Used instead of the h_ d_ convention for naming pointers
#define DEVICEPTR(mem)          mem

// Declares a pointer to device-only memory which is __shared__ among the threads of the current block
#define SHAREDPTR(mem)          mem

#define KERNEL                  __global__ void

#if defined(__CUDACC__) && defined(__CUDA_ARCH__)
#define CPU_AND_GPU __device__
#else
#define CPU_AND_GPU 
#endif











// Declaration of ostream << CLASSNAME operator
#define OSTREAM(CLASSNAME) friend std::ostream& operator<<(std::ostream& os, const CLASSNAME& o)













// Sequence@@p
#define xyz(p) p.x, p.y, p.z
#define comp012(p) p[0], p[1], p[2]
#define xy(p) p.x, p.y













// Linearize xyz coordinate of thread into 3 arguments
#define threadIdx_xyz xyz(threadIdx)







































/// Whether a failed assertion triggers a debugger break.
__managed__ bool breakOnAssertion = true;

/// Whether when an assertions fails std::exception should be thrown.
/// No effect in GPU code. Used for BEGIN_SHOULD_FAIL tests only.
__managed__ bool assertionThrowException = false;

/// Used to track assertion failures on GPU in particular.
/// Must be reset manually (*_SHOULD_FAIL reset it).
__managed__ bool assertionFailed = false;

#pragma warning(disable : 4003) // assert does not need "commentFormat" and its arguments
#undef assert
#if GPU_CODE
#define assert(x,commentFormat,...) {if(!(x)) {if (!assertionThrowException) printf("%s(%i) : Assertion failed : %s.\n\tblockIdx %d %d %d, threadIdx %d %d %d\n\t<" commentFormat ">\n", __FILE__, __LINE__, #x, xyz(blockIdx), xyz(threadIdx), __VA_ARGS__); assertionFailed = true; if (breakOnAssertion) *(int*)0 = 0;/* asm("trap;"); illegal instruction*/} }
#else
#define assert(x,commentFormat,...) {if(!(x)) {char s[10000]; sprintf_s(s, "%s(%i) : Assertion failed : %s.\n\t<" commentFormat ">\n", __FILE__, __LINE__, #x, __VA_ARGS__); if (!assertionThrowException) {puts(s);MessageBoxA(0,s,"Assertion failed",0);OutputDebugStringA(s);} /*flushStd();*/ assertionFailed = true; if (breakOnAssertion) DebugBreak();  if (assertionThrowException) throw std::exception(s); }}
#endif

/// BEGIN_SHOULD_FAIL starts a block of code that should raise an assertion error.
/// Can only be used together with END_SHOULD_FAIL in the same block
// TODO support SEH via __try, __except (to catch division by 0, null pointer access etc.)
#define BEGIN_SHOULD_FAIL() {cudaDeviceSynchronize(); assert(!assertionThrowException, "BEGIN_SHOULD_FAIL blocks cannot be nested"); bool ok = false; assertionThrowException = true; breakOnAssertion = false; assert(!assertionFailed); try {

#define END_SHOULD_FAIL() } catch(const std::exception& e) { /*cout << e.what();*/ } cudaDeviceSynchronize(); assertionThrowException = false; breakOnAssertion = true; if (assertionFailed) { ok = true; assertionFailed = false; } assert(ok, "expected an exception but got none"); }

#define fatalError(commentFormat,...) {assert(false, commentFormat, __VA_ARGS__);}





























// 3d to 1d coordinate conversion (think 3-digit mixed base number, where dim is the bases and id the digits)

CPU_AND_GPU unsigned int toLinearId(const dim3 dim, const uint3 id) {
    assert(id.x < dim.x);
    assert(id.y < dim.y);
    assert(id.z < dim.z); // actually, the highest digit (or all digits) could be allowed to be anything, but then the representation would not be unique
    return dim.x * dim.y * id.z + dim.x * id.y + id.x;
}
CPU_AND_GPU unsigned int toLinearId2D(const dim3 dim, const uint3 id) {
    assert(dim.z == 1);
    return toLinearId(dim, id);
}

GPU_ONLY uint linear_threadIdx() {
    return toLinearId(blockDim, threadIdx);
}
GPU_ONLY uint linear_blockIdx() {
    return toLinearId(gridDim, blockIdx);
}

CPU_AND_GPU unsigned int volume(dim3 d) {
    return d.x*d.y*d.z;
}

GPU_ONLY uint linear_global_threadId() {
    return linear_blockIdx() * volume(blockDim) + linear_threadIdx();
}


/// Given the desired blockSize (threads per block) and total amount of tasks, compute a sufficient grid size
// Note that some blocks will not be completely occupied. You need to add manual checks in the kernels
inline dim3 getGridSize(dim3 taskSize, dim3 blockSize)
{
    return dim3((taskSize.x + blockSize.x - 1) / blockSize.x, (taskSize.y + blockSize.y - 1) / blockSize.y, (taskSize.z + blockSize.z - 1) / blockSize.z);
}



































/** Allocate a block of CUDA memory and memset it to 0 */
template<typename T> static void zeroMalloc(T*& p, const uint count = 1) {
    cudaMalloc(&p, sizeof(T) * count);
    cudaMemset(p, 0, sizeof(T) * count);
}






















// Simple mathematical functions

template<typename T>
inline T CPU_AND_GPU ROUND(T x) {
    return ((x < 0) ? (x - 0.5f) : (x + 0.5f));
}


template<typename T>
inline T CPU_AND_GPU MAX(T x, T y) {
    return x > y ? x : y;
}


template<typename T>
inline T CPU_AND_GPU MIN(T x, T y) {
    return x < y ? x : y;
}


template<typename T>
inline T CPU_AND_GPU CLAMP(T x, T a, T b) {
    return MAX((a), MIN((b), (x)));
}














// Kernel launch and error reporting

dim3 _lastLaunch_gridDim, _lastLaunch_blockDim;
#ifndef __CUDACC__
// HACK to make intellisense shut up about illegal C++ 
#define LAUNCH_KERNEL(kernelFunction, gridDim, blockDim, arguments, ...) ((void)0)
#else
#define LAUNCH_KERNEL(kernelFunction, gridDim, blockDim, ...) {\
cudaSafeCall(cudaGetLastError());\
_lastLaunch_gridDim = dim3(gridDim); _lastLaunch_blockDim = dim3(blockDim);\
kernelFunction << <gridDim, blockDim >> >(__VA_ARGS__);\
cudaSafeCall(cudaGetLastError());\
cudaSafeCall(cudaDeviceSynchronize()); /* TODO synchronizing greatly alters the execution logic */\
cudaSafeCall(cudaGetLastError());\
}

#endif
















































/// Extend this class to declar objects whose memory lies in CUDA managed memory space
/// which is accessible from CPU and GPU.
/// Classes extending this must be heap-allocated
struct Managed {
    void *operator new(size_t len){
        void *ptr;
        cudaMallocManaged(&ptr, len); // if cudaSafeCall fails here check the following: did some earlier kernel throw an assert?
        cudaDeviceSynchronize();
        return ptr;
    }

    void operator delete(void *ptr) {
        cudaDeviceSynchronize();  // did some earlier kernel throw an assert?
        cudaFree(ptr);
    }
};





































/// Sums up 64 floats
/// c.f. "Optimizing Parallel Reduction in CUDA" https://docs.nvidia.com/cuda/samples/6_Advanced/reduction/doc/reduction.pdf
///
/// sdata[0] will contain the sum 
///
/// tid up to tid+32 must be a valid indices into sdata 
/// tid should be 0 to 31
/// ! Must be run by all threads of a single warp (the 32 first threads of a block) simultaneously.
/// sdata must point to __shared__ memory
inline __device__ void warpReduce(volatile SHAREDPTR(float*) sdata, int tid) {
    // Ignore the fact that we compute some unnecessary sums.
    sdata[tid] += sdata[tid + 32];
    sdata[tid] += sdata[tid + 16];
    sdata[tid] += sdata[tid + 8];
    sdata[tid] += sdata[tid + 4];
    sdata[tid] += sdata[tid + 2];
    sdata[tid] += sdata[tid + 1];
}

/// Sums up 256 floats
/// and atomicAdd's the final sum to a float or int in global memory
template<typename T //!< int or float
>
inline __device__ void warpReduce256(
float localValue,
volatile SHAREDPTR(float*) dim_shared1,
int locId_local,
DEVICEPTR(T*) outTotal) {
    dim_shared1[locId_local] = localValue;
    __syncthreads();

    if (locId_local < 128) dim_shared1[locId_local] += dim_shared1[locId_local + 128];
    __syncthreads();
    if (locId_local < 64) dim_shared1[locId_local] += dim_shared1[locId_local + 64];
    __syncthreads();

    if (locId_local < 32) warpReduce(dim_shared1, locId_local);

    if (locId_local == 0) atomicAdd(outTotal, (T)dim_shared1[locId_local]);
}






















































// Serialization infrastructure

template<typename T>
void binwrite(ofstream& f, const T* const x) {
    auto p = f.tellp(); // DEBUG
    f.write((char*)x, sizeof(T));
    assert(f.tellp() - p == sizeof(T));
}

template<typename T>
T binread(ifstream& f) {
    T x;
    f.read((char*)&x, sizeof(T));
    return x;
}

template<typename T>
void binread(ifstream& f, T* const x) {
    f.read((char*)x, sizeof(T));
}

#define SERIALIZE_VERSION(x) static const int serialize_version = x
#define SERIALIZE_WRITE_VERSION(file) bin(file, serialize_version)
#define SERIALIZE_READ_VERSION(file) {const int sv = bin<int>(file); \
assert(sv == serialize_version\
, "Serialized version in file, '%d', does not match expected version '%d'"\
, sv, serialize_version);}

template<typename T>
void bin(ofstream& f, const T& x) {
    binwrite(f, &x);
}
template<typename T>
void bin(ifstream& f, T& x) {
    binread(f, &x);
}
template<typename T>
T bin(ifstream& f) {
    return binread<T>(f);
}

ofstream binopen_write(string fn) {
    return ofstream(fn, ios::binary);
}

ifstream binopen_read(string fn) {
    return ifstream(fn, ios::binary);
}













































// Testing framework
// Note: CANNOT USE std::vector to track all listed tests (not yet initialized?)
// this ad-hoc implementation works
const int max_tests = 10000;
int _ntests = 0;
typedef void(*Test)(void);
Test _tests[max_tests] = {0};
const char* _test_names[max_tests] = {0};

void addTest(const char*const n, void f(void)) {
    assert(_ntests < max_tests);
    _test_names[_ntests] = n;
    _tests[_ntests++] = f;
}

void runTests() {
    for (int i = 0; i < _ntests; i++) {
        cout << "Test " << i + 1 << "/" << _ntests << ": " << _test_names[i] << endl;
        _tests[i]();
    }
    cout << "=== all tests passed ===" << endl;
}

#define TEST(name) void name(); struct T##name {T##name() {addTest(#name,name);}} _T##name; void name() 















































// cudaSafeCall wrapper


// Implementation detail:
// cudaSafeCall is an expression that evaluates to 
// 0 when err is cudaSuccess (0), such that cudaSafeCall(cudaSafeCall(cudaSuccess)) will not block
// this is important because we might have legacy code that explicitly does 
// cudaSafeCall(cudaDeviceSynchronize());
// but we extended cudaDeviceSynchronize to include this already, giving
// cudaSafeCall(cudaSafeCall(cudaDeviceSynchronize()))

// it debug-breaks and returns 
bool cudaSafeCallImpl(cudaError err, const char * const expr, const char * const file, const int line);

// If err is cudaSuccess, cudaSafeCallImpl will return true, early-out of || will make DebugBreak not evaluated.
// The final expression will be 0.
// Otherwise we evaluate debug break, which returns true as well and then return 0.
#define cudaSafeCall(err) \
    !(cudaSafeCallImpl((cudaError)(err), #err, __FILE__, __LINE__) || ([]() {fatalError("CUDA error in cudaSafeCall"); return true;})() )



// Automatically wrap some common cuda functions in cudaSafeCall
#ifdef __CUDACC__ // hack to hide these from intellisense
#define cudaDeviceSynchronize(...) cudaSafeCall(cudaDeviceSynchronize(__VA_ARGS__))
#define cudaMalloc(...) cudaSafeCall(cudaMalloc(__VA_ARGS__))
#define cudaMemcpy(...) cudaSafeCall(cudaMemcpy(__VA_ARGS__))
#define cudaMemset(...) cudaSafeCall(cudaMemset(__VA_ARGS__))
#define cudaMemcpyAsync(...) cudaSafeCall(cudaMemcpyAsync(__VA_ARGS__))
#define cudaFree(...) cudaSafeCall(cudaFree(__VA_ARGS__))
#define cudaMallocManaged(...) cudaSafeCall(cudaMallocManaged(__VA_ARGS__))
#endif

/// \returns true if err is cudaSuccess
/// Fills errmsg in UNIT_TESTING build.
bool cudaSafeCallImpl(cudaError err, const char * const expr, const char * const file, const int line)
{
    if (cudaSuccess == err) return true;

    char s[10000];
    cudaGetLastError(); // Reset error flag
    const char* e = cudaGetErrorString(err);
    if (!e) e = "! cudaGetErrorString returned 0 !";

    sprintf_s(s, "\n%s(%i) : cudaSafeCall(%s)\nRuntime API error : %s.\n",
        file,
        line,
        expr,
        e);
    puts(s);
    if (err == cudaError::cudaErrorLaunchFailure) {
        printf("NOTE maybe this error signifies an illegal memory access (memcpy(0,0,4) et.al)  or failed assertion, try the CUDA debugger\n\n"
            );
    }

    if (err == cudaError::cudaErrorInvalidConfiguration) {
        printf("configuration was (%d,%d,%d), (%d,%d,%d)\n",
            xyz(_lastLaunch_gridDim),
            xyz(_lastLaunch_blockDim)
            );
    }

    if (err == cudaError::cudaErrorIllegalInstruction) {
        puts("maybe the illegal instruction was asm(trap;) of a failed assertion?");
    }


    //flushStd();

    return false;
}

































KERNEL trueTestKernel() {
    assert(true, "this should not fail on the GPU");
}

KERNEL failTestKernel() {
    fatalError("this should fail on the GPU");
}

void sehDemo() {

    __try {
        int x = 5; x /= 0;
    }
    __except (EXCEPTION_EXECUTE_HANDLER) { //< could use GetExceptionCode, GetExceptionInformation here
    }
}

TEST(trueTest) {
    assert(true, "this should not fail on the CPU");

    LAUNCH_KERNEL(trueTestKernel, 1, 1);

    BEGIN_SHOULD_FAIL();
    fatalError("this should fail on the CPU");
    END_SHOULD_FAIL();

    // cannot have the GPU assertion-fail, because this resets the device
    // TODO work around, just *exit* (return -- or exit instruction?) from the kernel on assertion failure instead of illegal instruction,
    // at least if no debugger present
    /*
    BEGIN_SHOULD_FAIL();
    LAUNCH_KERNEL(failTestKernel, 1, 1);
    END_SHOULD_FAIL();
    */

    sehDemo();
}














// 2 to 4 & X dimensional linear algebra library
// TODO consider using this with range-checked datatypes and overflow-avoiding integers

namespace vecmath {

    //////////////////////////////////////////////////////////////////////////
    //						Basic Vector Structure
    //////////////////////////////////////////////////////////////////////////

    template <class T> struct Vector2_{
        union {
            struct { T x, y; }; // standard names for components
            struct { T s, t; }; // standard names for components
            struct { T width, height; };
            T v[2];     // array access
        };
    };

    template <class T> struct Vector3_{
        union {
            struct{ T x, y, z; }; // standard names for components
            struct{ T r, g, b; }; // standard names for components
            struct{ T s, t, p; }; // standard names for components
            T v[3];
        };
    };

    template <class T> struct Vector4_ {
        union {
            struct { T x, y, z, w; }; // standard names for components
            struct { T r, g, b, a; }; // standard names for components
            struct { T s, t, p, q; }; // standard names for components
            T v[4];
        };
    };

    template <class T> struct Vector6_ {
        //union {
        T v[6];
        //};
    };

    template<class T, int s> struct VectorX_
    {
        int vsize;
        T v[s];
    };

    //////////////////////////////////////////////////////////////////////////
    // Vector class with math operators: +, -, *, /, +=, -=, /=, [], ==, !=, T*(), etc.
    //////////////////////////////////////////////////////////////////////////
    template <class T> class Vector2 : public Vector2_ < T >
    {
    public:
        typedef T value_type;
        CPU_AND_GPU inline int size() const { return 2; }

        ////////////////////////////////////////////////////////
        //  Constructors
        ////////////////////////////////////////////////////////
        CPU_AND_GPU Vector2(){} // Default constructor
        CPU_AND_GPU Vector2(const T &t) { this->x = t; this->y = t; } // Scalar constructor
        CPU_AND_GPU Vector2(const T *tp) { this->x = tp[0]; this->y = tp[1]; } // Construct from array			            
        CPU_AND_GPU Vector2(const T v0, const T v1) { this->x = v0; this->y = v1; } // Construct from explicit values
        CPU_AND_GPU Vector2(const Vector2_<T> &v) { this->x = v.x; this->y = v.y; }// copy constructor

        CPU_AND_GPU explicit Vector2(const Vector3_<T> &u)  { this->x = u.x; this->y = u.y; }
        CPU_AND_GPU explicit Vector2(const Vector4_<T> &u)  { this->x = u.x; this->y = u.y; }

        CPU_AND_GPU inline Vector2<int> toInt() const {
            return Vector2<int>((int)ROUND(this->x), (int)ROUND(this->y));
        }

        CPU_AND_GPU inline Vector2<int> toIntFloor() const {
            return Vector2<int>((int)floor(this->x), (int)floor(this->y));
        }

        CPU_AND_GPU inline Vector2<unsigned char> toUChar() const {
            Vector2<int> vi = toInt(); return Vector2<unsigned char>((unsigned char)CLAMP(vi.x, 0, 255), (unsigned char)CLAMP(vi.y, 0, 255));
        }

        CPU_AND_GPU inline Vector2<float> toFloat() const {
            return Vector2<float>((float)this->x, (float)this->y);
        }

        CPU_AND_GPU const T *getValues() const { return this->v; }
        CPU_AND_GPU Vector2<T> &setValues(const T *rhs) { this->x = rhs[0]; this->y = rhs[1]; return *this; }

        CPU_AND_GPU T area() const {
            return width * height;
        }
        // indexing operators
        CPU_AND_GPU T &operator [](int i) { return this->v[i]; }
        CPU_AND_GPU const T &operator [](int i) const { return this->v[i]; }

        // type-cast operators
        CPU_AND_GPU operator T *() { return this->v; }
        CPU_AND_GPU operator const T *() const { return this->v; }

        ////////////////////////////////////////////////////////
        //  Math operators
        ////////////////////////////////////////////////////////

        // scalar multiply assign
        CPU_AND_GPU friend Vector2<T> &operator *= (const Vector2<T> &lhs, T d) {
            lhs.x *= d; lhs.y *= d; return lhs;
        }

        // component-wise vector multiply assign
        CPU_AND_GPU friend Vector2<T> &operator *= (Vector2<T> &lhs, const Vector2<T> &rhs) {
            lhs.x *= rhs.x; lhs.y *= rhs.y; return lhs;
        }

        // scalar divide assign
        CPU_AND_GPU friend Vector2<T> &operator /= (Vector2<T> &lhs, T d) {
            if (d == 0) return lhs; lhs.x /= d; lhs.y /= d; return lhs;
        }

        // component-wise vector divide assign
        CPU_AND_GPU friend Vector2<T> &operator /= (Vector2<T> &lhs, const Vector2<T> &rhs) {
            lhs.x /= rhs.x; lhs.y /= rhs.y;	return lhs;
        }

        // component-wise vector add assign
        CPU_AND_GPU friend Vector2<T> &operator += (Vector2<T> &lhs, const Vector2<T> &rhs) {
            lhs.x += rhs.x; lhs.y += rhs.y;	return lhs;
        }

        // component-wise vector subtract assign
        CPU_AND_GPU friend Vector2<T> &operator -= (Vector2<T> &lhs, const Vector2<T> &rhs) {
            lhs.x -= rhs.x; lhs.y -= rhs.y;	return lhs;
        }

        // unary negate
        CPU_AND_GPU friend Vector2<T> operator - (const Vector2<T> &rhs) {
            Vector2<T> rv;	rv.x = -rhs.x; rv.y = -rhs.y; return rv;
        }

        // vector add
        CPU_AND_GPU friend Vector2<T> operator + (const Vector2<T> &lhs, const Vector2<T> &rhs)  {
            Vector2<T> rv(lhs); return rv += rhs;
        }

        // vector subtract
        CPU_AND_GPU friend Vector2<T> operator - (const Vector2<T> &lhs, const Vector2<T> &rhs) {
            Vector2<T> rv(lhs); return rv -= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector2<T> operator * (const Vector2<T> &lhs, T rhs) {
            Vector2<T> rv(lhs); return rv *= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector2<T> operator * (T lhs, const Vector2<T> &rhs) {
            Vector2<T> rv(lhs); return rv *= rhs;
        }

        // vector component-wise multiply
        CPU_AND_GPU friend Vector2<T> operator * (const Vector2<T> &lhs, const Vector2<T> &rhs) {
            Vector2<T> rv(lhs); return rv *= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector2<T> operator / (const Vector2<T> &lhs, T rhs) {
            Vector2<T> rv(lhs); return rv /= rhs;
        }

        // vector component-wise multiply
        CPU_AND_GPU friend Vector2<T> operator / (const Vector2<T> &lhs, const Vector2<T> &rhs) {
            Vector2<T> rv(lhs); return rv /= rhs;
        }

        ////////////////////////////////////////////////////////
        //  Comparison operators
        ////////////////////////////////////////////////////////

        // equality
        CPU_AND_GPU friend bool operator == (const Vector2<T> &lhs, const Vector2<T> &rhs) {
            return (lhs.x == rhs.x) && (lhs.y == rhs.y);
        }

        // inequality
        CPU_AND_GPU friend bool operator != (const Vector2<T> &lhs, const Vector2<T> &rhs) {
            return (lhs.x != rhs.x) || (lhs.y != rhs.y);
        }

        OSTREAM(Vector2<T>) {
            os << o.x << ", " << o.y;
            return os;
        }
    };

    template <class T> class Vector3 : public Vector3_ < T >
    {
    public:
        typedef T value_type;
        CPU_AND_GPU inline int size() const { return 3; }

        ////////////////////////////////////////////////////////
        //  Constructors
        ////////////////////////////////////////////////////////
        CPU_AND_GPU Vector3(){} // Default constructor
        CPU_AND_GPU Vector3(const T &t)	{ this->x = t; this->y = t; this->z = t; } // Scalar constructor
        CPU_AND_GPU Vector3(const T *tp) { this->x = tp[0]; this->y = tp[1]; this->z = tp[2]; } // Construct from array
        CPU_AND_GPU Vector3(const T v0, const T v1, const T v2) { this->x = v0; this->y = v1; this->z = v2; } // Construct from explicit values
        CPU_AND_GPU explicit Vector3(const Vector4_<T> &u)	{ this->x = u.x; this->y = u.y; this->z = u.z; }
        CPU_AND_GPU explicit Vector3(const Vector2_<T> &u, T v0) { this->x = u.x; this->y = u.y; this->z = v0; }

        CPU_AND_GPU inline Vector3<int> toIntRound() const {
            return Vector3<int>((int)ROUND(this->x), (int)ROUND(this->y), (int)ROUND(this->z));
        }

        CPU_AND_GPU inline Vector3<int> toInt() const {
            return Vector3<int>((int)(this->x), (int)(this->y), (int)(this->z));
        }

        CPU_AND_GPU inline Vector3<int> toInt(Vector3<float> &residual) const {
            Vector3<int> intRound = toInt();
            residual = Vector3<float>(this->x - intRound.x, this->y - intRound.y, this->z - intRound.z);
            return intRound;
        }

        CPU_AND_GPU inline Vector3<short> toShortRound() const {
            return Vector3<short>((short)ROUND(this->x), (short)ROUND(this->y), (short)ROUND(this->z));
        }

        CPU_AND_GPU inline Vector3<short> toShortFloor() const {
            return Vector3<short>((short)floor(this->x), (short)floor(this->y), (short)floor(this->z));
        }

        CPU_AND_GPU inline Vector3<int> toIntFloor() const {
            return Vector3<int>((int)floor(this->x), (int)floor(this->y), (int)floor(this->z));
        }

        /// Floors the coordinates to integer values, returns this and the residual float.
        /// Use like
        /// TO_INT_FLOOR3(int_xyz, residual_xyz, xyz)
        /// for xyz === this
        CPU_AND_GPU inline Vector3<int> toIntFloor(Vector3<float> &residual) const {
            Vector3<float> intFloor(floor(this->x), floor(this->y), floor(this->z));
            residual = *this - intFloor;
            return Vector3<int>((int)intFloor.x, (int)intFloor.y, (int)intFloor.z);
        }

        CPU_AND_GPU inline Vector3<unsigned char> toUChar() const {
            Vector3<int> vi = toIntRound(); return Vector3<unsigned char>((unsigned char)CLAMP(vi.x, 0, 255), (unsigned char)CLAMP(vi.y, 0, 255), (unsigned char)CLAMP(vi.z, 0, 255));
        }

        CPU_AND_GPU inline Vector3<float> toFloat() const {
            return Vector3<float>((float)this->x, (float)this->y, (float)this->z);
        }

        CPU_AND_GPU inline Vector3<float> normalised() const {
            float norm = 1.0f / sqrt((float)(this->x * this->x + this->y * this->y + this->z * this->z));
            return Vector3<float>((float)this->x * norm, (float)this->y * norm, (float)this->z * norm);
        }

        CPU_AND_GPU const T *getValues() const	{ return this->v; }
        CPU_AND_GPU Vector3<T> &setValues(const T *rhs) { this->x = rhs[0]; this->y = rhs[1]; this->z = rhs[2]; return *this; }

        // indexing operators
        CPU_AND_GPU T &operator [](int i) { return this->v[i]; }
        CPU_AND_GPU const T &operator [](int i) const { return this->v[i]; }

        // type-cast operators
        CPU_AND_GPU operator T *()	{ return this->v; }
        CPU_AND_GPU operator const T *() const { return this->v; }

        ////////////////////////////////////////////////////////
        //  Math operators
        ////////////////////////////////////////////////////////

        // scalar multiply assign
        CPU_AND_GPU friend Vector3<T> &operator *= (Vector3<T> &lhs, T d)	{
            lhs.x *= d; lhs.y *= d; lhs.z *= d; return lhs;
        }

        // component-wise vector multiply assign
        CPU_AND_GPU friend Vector3<T> &operator *= (Vector3<T> &lhs, const Vector3<T> &rhs) {
            lhs.x *= rhs.x; lhs.y *= rhs.y; lhs.z *= rhs.z; return lhs;
        }

        // scalar divide assign
        CPU_AND_GPU friend Vector3<T> &operator /= (Vector3<T> &lhs, T d) {
            lhs.x /= d; lhs.y /= d; lhs.z /= d; return lhs;
        }

        // component-wise vector divide assign
        CPU_AND_GPU friend Vector3<T> &operator /= (Vector3<T> &lhs, const Vector3<T> &rhs)	{
            lhs.x /= rhs.x; lhs.y /= rhs.y; lhs.z /= rhs.z; return lhs;
        }

        // component-wise vector add assign
        CPU_AND_GPU friend Vector3<T> &operator += (Vector3<T> &lhs, const Vector3<T> &rhs)	{
            lhs.x += rhs.x; lhs.y += rhs.y; lhs.z += rhs.z; return lhs;
        }

        // component-wise vector subtract assign
        CPU_AND_GPU friend Vector3<T> &operator -= (Vector3<T> &lhs, const Vector3<T> &rhs) {
            lhs.x -= rhs.x; lhs.y -= rhs.y; lhs.z -= rhs.z; return lhs;
        }

        // unary negate
        CPU_AND_GPU friend Vector3<T> operator - (const Vector3<T> &rhs)	{
            Vector3<T> rv; rv.x = -rhs.x; rv.y = -rhs.y; rv.z = -rhs.z; return rv;
        }

        // vector add
        CPU_AND_GPU friend Vector3<T> operator + (const Vector3<T> &lhs, const Vector3<T> &rhs){
            Vector3<T> rv(lhs); return rv += rhs;
        }

        // vector subtract
        CPU_AND_GPU friend Vector3<T> operator - (const Vector3<T> &lhs, const Vector3<T> &rhs){
            Vector3<T> rv(lhs); return rv -= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector3<T> operator * (const Vector3<T> &lhs, T rhs) {
            Vector3<T> rv(lhs); return rv *= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector3<T> operator * (T lhs, const Vector3<T> &rhs) {
            Vector3<T> rv(lhs); return rv *= rhs;
        }

        // vector component-wise multiply
        CPU_AND_GPU friend Vector3<T> operator * (const Vector3<T> &lhs, const Vector3<T> &rhs)	{
            Vector3<T> rv(lhs); return rv *= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector3<T> operator / (const Vector3<T> &lhs, T rhs) {
            Vector3<T> rv(lhs); return rv /= rhs;
        }

        // vector component-wise multiply
        CPU_AND_GPU friend Vector3<T> operator / (const Vector3<T> &lhs, const Vector3<T> &rhs) {
            Vector3<T> rv(lhs); return rv /= rhs;
        }

        ////////////////////////////////////////////////////////
        //  Comparison operators
        ////////////////////////////////////////////////////////

        // inequality
        CPU_AND_GPU friend bool operator != (const Vector3<T> &lhs, const Vector3<T> &rhs) {
            return (lhs.x != rhs.x) || (lhs.y != rhs.y) || (lhs.z != rhs.z);
        }

        ////////////////////////////////////////////////////////////////////////////////
        // dimension specific operations
        ////////////////////////////////////////////////////////////////////////////////

        OSTREAM(Vector3<T>) {
            os << o.x << ", " << o.y << ", " << o.z;
            return os;
        }
    };

    ////////////////////////////////////////////////////////
    //  Non-member comparison operators
    ////////////////////////////////////////////////////////

    // equality
    template <typename T1, typename T2> CPU_AND_GPU inline bool operator == (const Vector3<T1> &lhs, const Vector3<T2> &rhs){
        return (lhs.x == rhs.x) && (lhs.y == rhs.y) && (lhs.z == rhs.z);
    }

    template <class T> class Vector4 : public Vector4_ < T >
    {
    public:
        typedef T value_type;
        CPU_AND_GPU inline int size() const { return 4; }

        ////////////////////////////////////////////////////////
        //  Constructors
        ////////////////////////////////////////////////////////

        CPU_AND_GPU Vector4() {} // Default constructor
        CPU_AND_GPU Vector4(const T &t) { this->x = t; this->y = t; this->z = t; this->w = t; } //Scalar constructor
        CPU_AND_GPU Vector4(const T *tp) { this->x = tp[0]; this->y = tp[1]; this->z = tp[2]; this->w = tp[3]; } // Construct from array
        CPU_AND_GPU Vector4(const T v0, const T v1, const T v2, const T v3) { this->x = v0; this->y = v1; this->z = v2; this->w = v3; } // Construct from explicit values
        CPU_AND_GPU explicit Vector4(const Vector3_<T> &u, T v0) { this->x = u.x; this->y = u.y; this->z = u.z; this->w = v0; }
        CPU_AND_GPU explicit Vector4(const Vector2_<T> &u, T v0, T v1) { this->x = u.x; this->y = u.y; this->z = v0; this->w = v1; }

        CPU_AND_GPU inline Vector4<int> toIntRound() const {
            return Vector4<int>((int)ROUND(this->x), (int)ROUND(this->y), (int)ROUND(this->z), (int)ROUND(this->w));
        }

        CPU_AND_GPU inline Vector4<unsigned char> toUChar() const {
            Vector4<int> vi = toIntRound(); return Vector4<unsigned char>((unsigned char)CLAMP(vi.x, 0, 255), (unsigned char)CLAMP(vi.y, 0, 255), (unsigned char)CLAMP(vi.z, 0, 255), (unsigned char)CLAMP(vi.w, 0, 255));
        }

        CPU_AND_GPU inline Vector4<float> toFloat() const {
            return Vector4<float>((float)this->x, (float)this->y, (float)this->z, (float)this->w);
        }

        CPU_AND_GPU inline Vector4<T> homogeneousCoordinatesNormalize() const {
            return (this->w <= 0) ? *this : Vector4<T>(this->x / this->w, this->y / this->w, this->z / this->w, 1);
        }

        CPU_AND_GPU inline Vector3<T> toVector3() const {
            return Vector3<T>(this->x, this->y, this->z);
        }

        CPU_AND_GPU const T *getValues() const { return this->v; }
        CPU_AND_GPU Vector4<T> &setValues(const T *rhs) { this->x = rhs[0]; this->y = rhs[1]; this->z = rhs[2]; this->w = rhs[3]; return *this; }

        // indexing operators
        CPU_AND_GPU T &operator [](int i) { return this->v[i]; }
        CPU_AND_GPU const T &operator [](int i) const { return this->v[i]; }

        // type-cast operators
        CPU_AND_GPU operator T *() { return this->v; }
        CPU_AND_GPU operator const T *() const { return this->v; }

        ////////////////////////////////////////////////////////
        //  Math operators
        ////////////////////////////////////////////////////////

        // scalar multiply assign
        CPU_AND_GPU friend Vector4<T> &operator *= (Vector4<T> &lhs, T d) {
            lhs.x *= d; lhs.y *= d; lhs.z *= d; lhs.w *= d; return lhs;
        }

        // component-wise vector multiply assign
        CPU_AND_GPU friend Vector4<T> &operator *= (Vector4<T> &lhs, const Vector4<T> &rhs) {
            lhs.x *= rhs.x; lhs.y *= rhs.y; lhs.z *= rhs.z; lhs.w *= rhs.w; return lhs;
        }

        // scalar divide assign
        CPU_AND_GPU friend Vector4<T> &operator /= (Vector4<T> &lhs, T d){
            lhs.x /= d; lhs.y /= d; lhs.z /= d; lhs.w /= d; return lhs;
        }

        // component-wise vector divide assign
        CPU_AND_GPU friend Vector4<T> &operator /= (Vector4<T> &lhs, const Vector4<T> &rhs) {
            lhs.x /= rhs.x; lhs.y /= rhs.y; lhs.z /= rhs.z; lhs.w /= rhs.w; return lhs;
        }

        // component-wise vector add assign
        CPU_AND_GPU friend Vector4<T> &operator += (Vector4<T> &lhs, const Vector4<T> &rhs)	{
            lhs.x += rhs.x; lhs.y += rhs.y; lhs.z += rhs.z; lhs.w += rhs.w; return lhs;
        }

        // component-wise vector subtract assign
        CPU_AND_GPU friend Vector4<T> &operator -= (Vector4<T> &lhs, const Vector4<T> &rhs)	{
            lhs.x -= rhs.x; lhs.y -= rhs.y; lhs.z -= rhs.z; lhs.w -= rhs.w; return lhs;
        }

        // unary negate
        CPU_AND_GPU friend Vector4<T> operator - (const Vector4<T> &rhs)	{
            Vector4<T> rv; rv.x = -rhs.x; rv.y = -rhs.y; rv.z = -rhs.z; rv.w = -rhs.w; return rv;
        }

        // vector add
        CPU_AND_GPU friend Vector4<T> operator + (const Vector4<T> &lhs, const Vector4<T> &rhs) {
            Vector4<T> rv(lhs); return rv += rhs;
        }

        // vector subtract
        CPU_AND_GPU friend Vector4<T> operator - (const Vector4<T> &lhs, const Vector4<T> &rhs) {
            Vector4<T> rv(lhs); return rv -= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector4<T> operator * (const Vector4<T> &lhs, T rhs) {
            Vector4<T> rv(lhs); return rv *= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector4<T> operator * (T lhs, const Vector4<T> &rhs) {
            Vector4<T> rv(lhs); return rv *= rhs;
        }

        // vector component-wise multiply
        CPU_AND_GPU friend Vector4<T> operator * (const Vector4<T> &lhs, const Vector4<T> &rhs) {
            Vector4<T> rv(lhs); return rv *= rhs;
        }

        // scalar divide
        CPU_AND_GPU friend Vector4<T> operator / (const Vector4<T> &lhs, T rhs) {
            Vector4<T> rv(lhs); return rv /= rhs;
        }

        // vector component-wise divide
        CPU_AND_GPU friend Vector4<T> operator / (const Vector4<T> &lhs, const Vector4<T> &rhs) {
            Vector4<T> rv(lhs); return rv /= rhs;
        }

        ////////////////////////////////////////////////////////
        //  Comparison operators
        ////////////////////////////////////////////////////////

        // equality
        CPU_AND_GPU friend bool operator == (const Vector4<T> &lhs, const Vector4<T> &rhs) {
            return (lhs.x == rhs.x) && (lhs.y == rhs.y) && (lhs.z == rhs.z) && (lhs.w == rhs.w);
        }

        // inequality
        CPU_AND_GPU friend bool operator != (const Vector4<T> &lhs, const Vector4<T> &rhs) {
            return (lhs.x != rhs.x) || (lhs.y != rhs.y) || (lhs.z != rhs.z) || (lhs.w != rhs.w);
        }

        friend std::ostream& operator<<(std::ostream& os, const Vector4<T>& dt){
            os << dt.x << ", " << dt.y << ", " << dt.z << ", " << dt.w;
            return os;
        }
    };

    template <class T> class Vector6 : public Vector6_ < T >
    {
    public:
        typedef T value_type;
        CPU_AND_GPU inline int size() const { return 6; }

        ////////////////////////////////////////////////////////
        //  Constructors
        ////////////////////////////////////////////////////////

        CPU_AND_GPU Vector6() {} // Default constructor
        CPU_AND_GPU Vector6(const T &t) { this->v[0] = t; this->v[1] = t; this->v[2] = t; this->v[3] = t; this->v[4] = t; this->v[5] = t; } //Scalar constructor
        CPU_AND_GPU Vector6(const T *tp) { this->v[0] = tp[0]; this->v[1] = tp[1]; this->v[2] = tp[2]; this->v[3] = tp[3]; this->v[4] = tp[4]; this->v[5] = tp[5]; } // Construct from array
        CPU_AND_GPU Vector6(const T v0, const T v1, const T v2, const T v3, const T v4, const T v5) { this->v[0] = v0; this->v[1] = v1; this->v[2] = v2; this->v[3] = v3; this->v[4] = v4; this->v[5] = v5; } // Construct from explicit values
        CPU_AND_GPU explicit Vector6(const Vector4_<T> &u, T v0, T v1) { this->v[0] = u.x; this->v[1] = u.y; this->v[2] = u.z; this->v[3] = u.w; this->v[4] = v0; this->v[5] = v1; }
        CPU_AND_GPU explicit Vector6(const Vector3_<T> &u, T v0, T v1, T v2) { this->v[0] = u.x; this->v[1] = u.y; this->v[2] = u.z; this->v[3] = v0; this->v[4] = v1; this->v[5] = v2; }
        CPU_AND_GPU explicit Vector6(const Vector2_<T> &u, T v0, T v1, T v2, T v3) { this->v[0] = u.x; this->v[1] = u.y; this->v[2] = v0; this->v[3] = v1; this->v[4] = v2, this->v[5] = v3; }

        CPU_AND_GPU inline Vector6<int> toIntRound() const {
            return Vector6<int>((int)ROUND(this[0]), (int)ROUND(this[1]), (int)ROUND(this[2]), (int)ROUND(this[3]), (int)ROUND(this[4]), (int)ROUND(this[5]));
        }

        CPU_AND_GPU inline Vector6<unsigned char> toUChar() const {
            Vector6<int> vi = toIntRound(); return Vector6<unsigned char>((unsigned char)CLAMP(vi[0], 0, 255), (unsigned char)CLAMP(vi[1], 0, 255), (unsigned char)CLAMP(vi[2], 0, 255), (unsigned char)CLAMP(vi[3], 0, 255), (unsigned char)CLAMP(vi[4], 0, 255), (unsigned char)CLAMP(vi[5], 0, 255));
        }

        CPU_AND_GPU inline Vector6<float> toFloat() const {
            return Vector6<float>((float)this[0], (float)this[1], (float)this[2], (float)this[3], (float)this[4], (float)this[5]);
        }

        CPU_AND_GPU const T *getValues() const { return this->v; }
        CPU_AND_GPU Vector6<T> &setValues(const T *rhs) { this[0] = rhs[0]; this[1] = rhs[1]; this[2] = rhs[2]; this[3] = rhs[3]; this[4] = rhs[4]; this[5] = rhs[5]; return *this; }

        // indexing operators
        CPU_AND_GPU T &operator [](int i) { return this->v[i]; }
        CPU_AND_GPU const T &operator [](int i) const { return this->v[i]; }

        // type-cast operators
        CPU_AND_GPU operator T *() { return this->v; }
        CPU_AND_GPU operator const T *() const { return this->v; }

        ////////////////////////////////////////////////////////
        //  Math operators
        ////////////////////////////////////////////////////////

        // scalar multiply assign
        CPU_AND_GPU friend Vector6<T> &operator *= (Vector6<T> &lhs, T d) {
            lhs[0] *= d; lhs[1] *= d; lhs[2] *= d; lhs[3] *= d; lhs[4] *= d; lhs[5] *= d; return lhs;
        }

        // component-wise vector multiply assign
        CPU_AND_GPU friend Vector6<T> &operator *= (Vector6<T> &lhs, const Vector6<T> &rhs) {
            lhs[0] *= rhs[0]; lhs[1] *= rhs[1]; lhs[2] *= rhs[2]; lhs[3] *= rhs[3]; lhs[4] *= rhs[4]; lhs[5] *= rhs[5]; return lhs;
        }

        // scalar divide assign
        CPU_AND_GPU friend Vector6<T> &operator /= (Vector6<T> &lhs, T d){
            lhs[0] /= d; lhs[1] /= d; lhs[2] /= d; lhs[3] /= d; lhs[4] /= d; lhs[5] /= d; return lhs;
        }

        // component-wise vector divide assign
        CPU_AND_GPU friend Vector6<T> &operator /= (Vector6<T> &lhs, const Vector6<T> &rhs) {
            lhs[0] /= rhs[0]; lhs[1] /= rhs[1]; lhs[2] /= rhs[2]; lhs[3] /= rhs[3]; lhs[4] /= rhs[4]; lhs[5] /= rhs[5]; return lhs;
        }

        // component-wise vector add assign
        CPU_AND_GPU friend Vector6<T> &operator += (Vector6<T> &lhs, const Vector6<T> &rhs)	{
            lhs[0] += rhs[0]; lhs[1] += rhs[1]; lhs[2] += rhs[2]; lhs[3] += rhs[3]; lhs[4] += rhs[4]; lhs[5] += rhs[5]; return lhs;
        }

        // component-wise vector subtract assign
        CPU_AND_GPU friend Vector6<T> &operator -= (Vector6<T> &lhs, const Vector6<T> &rhs)	{
            lhs[0] -= rhs[0]; lhs[1] -= rhs[1]; lhs[2] -= rhs[2]; lhs[3] -= rhs[3]; lhs[4] -= rhs[4]; lhs[5] -= rhs[5];  return lhs;
        }

        // unary negate
        CPU_AND_GPU friend Vector6<T> operator - (const Vector6<T> &rhs)	{
            Vector6<T> rv; rv[0] = -rhs[0]; rv[1] = -rhs[1]; rv[2] = -rhs[2]; rv[3] = -rhs[3]; rv[4] = -rhs[4]; rv[5] = -rhs[5];  return rv;
        }

        // vector add
        CPU_AND_GPU friend Vector6<T> operator + (const Vector6<T> &lhs, const Vector6<T> &rhs) {
            Vector6<T> rv(lhs); return rv += rhs;
        }

        // vector subtract
        CPU_AND_GPU friend Vector6<T> operator - (const Vector6<T> &lhs, const Vector6<T> &rhs) {
            Vector6<T> rv(lhs); return rv -= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector6<T> operator * (const Vector6<T> &lhs, T rhs) {
            Vector6<T> rv(lhs); return rv *= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend Vector6<T> operator * (T lhs, const Vector6<T> &rhs) {
            Vector6<T> rv(lhs); return rv *= rhs;
        }

        // vector component-wise multiply
        CPU_AND_GPU friend Vector6<T> operator * (const Vector6<T> &lhs, const Vector6<T> &rhs) {
            Vector6<T> rv(lhs); return rv *= rhs;
        }

        // scalar divide
        CPU_AND_GPU friend Vector6<T> operator / (const Vector6<T> &lhs, T rhs) {
            Vector6<T> rv(lhs); return rv /= rhs;
        }

        // vector component-wise divide
        CPU_AND_GPU friend Vector6<T> operator / (const Vector6<T> &lhs, const Vector6<T> &rhs) {
            Vector6<T> rv(lhs); return rv /= rhs;
        }

        ////////////////////////////////////////////////////////
        //  Comparison operators
        ////////////////////////////////////////////////////////

        // equality
        CPU_AND_GPU friend bool operator == (const Vector6<T> &lhs, const Vector6<T> &rhs) {
            return (lhs[0] == rhs[0]) && (lhs[1] == rhs[1]) && (lhs[2] == rhs[2]) && (lhs[3] == rhs[3]) && (lhs[4] == rhs[4]) && (lhs[5] == rhs[5]);
        }

        // inequality
        CPU_AND_GPU friend bool operator != (const Vector6<T> &lhs, const Vector6<T> &rhs) {
            return (lhs[0] != rhs[0]) || (lhs[1] != rhs[1]) || (lhs[2] != rhs[2]) || (lhs[3] != rhs[3]) || (lhs[4] != rhs[4]) || (lhs[5] != rhs[5]);
        }

        friend std::ostream& operator<<(std::ostream& os, const Vector6<T>& dt){
            os << dt[0] << ", " << dt[1] << ", " << dt[2] << ", " << dt[3] << ", " << dt[4] << ", " << dt[5];
            return os;
        }
    };


    template <class T, int s> class VectorX : public VectorX_ < T, s >
    {
    public:
        typedef T value_type;
        CPU_AND_GPU inline int size() const { return this->vsize; }

        ////////////////////////////////////////////////////////
        //  Constructors
        ////////////////////////////////////////////////////////

        CPU_AND_GPU VectorX() { this->vsize = s; } // Default constructor
        CPU_AND_GPU VectorX(const T &t) { for (int i = 0; i < s; i++) this->v[i] = t; } //Scalar constructor
        CPU_AND_GPU VectorX(const T tp[s]) { for (int i = 0; i < s; i++) this->v[i] = tp[i]; } // Construct from array
        VectorX(std::array<T, s> t) : VectorX(t.data()) { } // Construct from array


        CPU_AND_GPU static inline VectorX<T, s> make_zeros() {
            VectorX<T, s> x;
            x.setZeros();
            return x;
        }

        // indexing operators
        CPU_AND_GPU T &operator [](int i) { return this->v[i]; }
        CPU_AND_GPU const T &operator [](int i) const { return this->v[i]; }


        CPU_AND_GPU inline VectorX<int, s> toIntRound() const {
            VectorX<int, s> retv;
            for (int i = 0; i < s; i++) retv[i] = (int)ROUND(this->v[i]);
            return retv;
        }

        CPU_AND_GPU inline VectorX<unsigned char, s> toUChar() const {
            VectorX<int, s> vi = toIntRound();
            VectorX<unsigned char, s> retv;
            for (int i = 0; i < s; i++) retv[i] = (unsigned char)CLAMP(vi[0], 0, 255);
            return retv;
        }

        CPU_AND_GPU inline VectorX<float, s> toFloat() const {
            VectorX<float, s> retv;
            for (int i = 0; i < s; i++) retv[i] = (float) this->v[i];
            return retv;
        }

        CPU_AND_GPU const T *getValues() const { return this->v; }
        CPU_AND_GPU VectorX<T, s> &setValues(const T *rhs) { for (int i = 0; i < s; i++) this->v[i] = rhs[i]; return *this; }
        CPU_AND_GPU void Clear(T v){
            for (int i = 0; i < s; i++)
                this->v[i] = v;
        }

        CPU_AND_GPU void setZeros(){
            Clear(0);
        }

        // type-cast operators
        CPU_AND_GPU operator T *() { return this->v; }
        CPU_AND_GPU operator const T *() const { return this->v; }

        ////////////////////////////////////////////////////////
        //  Math operators
        ////////////////////////////////////////////////////////

        // scalar multiply assign
        CPU_AND_GPU friend VectorX<T, s> &operator *= (VectorX<T, s> &lhs, T d) {
            for (int i = 0; i < s; i++) lhs[i] *= d; return lhs;
        }

        // component-wise vector multiply assign
        CPU_AND_GPU friend VectorX<T, s> &operator *= (VectorX<T, s> &lhs, const VectorX<T, s> &rhs) {
            for (int i = 0; i < s; i++) lhs[i] *= rhs[i]; return lhs;
        }

        // scalar divide assign
        CPU_AND_GPU friend VectorX<T, s> &operator /= (VectorX<T, s> &lhs, T d){
            for (int i = 0; i < s; i++) lhs[i] /= d; return lhs;
        }

        // component-wise vector divide assign
        CPU_AND_GPU friend VectorX<T, s> &operator /= (VectorX<T, s> &lhs, const VectorX<T, s> &rhs) {
            for (int i = 0; i < s; i++) lhs[i] /= rhs[i]; return lhs;
        }

        // component-wise vector add assign
        CPU_AND_GPU friend VectorX<T, s> &operator += (VectorX<T, s> &lhs, const VectorX<T, s> &rhs)	{
            for (int i = 0; i < s; i++) lhs[i] += rhs[i]; return lhs;
        }

        // component-wise vector subtract assign
        CPU_AND_GPU friend VectorX<T, s> &operator -= (VectorX<T, s> &lhs, const VectorX<T, s> &rhs)	{
            for (int i = 0; i < s; i++) lhs[i] -= rhs[i]; return lhs;
        }

        // unary negate
        CPU_AND_GPU friend VectorX<T, s> operator - (const VectorX<T, s> &rhs)	{
            VectorX<T, s> rv; for (int i = 0; i < s; i++) rv[i] = -rhs[i]; return rv;
        }

        // vector add
        CPU_AND_GPU friend VectorX<T, s> operator + (const VectorX<T, s> &lhs, const VectorX<T, s> &rhs) {
            VectorX<T, s> rv(lhs); return rv += rhs;
        }

        // vector subtract
        CPU_AND_GPU friend VectorX<T, s> operator - (const VectorX<T, s> &lhs, const VectorX<T, s> &rhs) {
            VectorX<T, s> rv(lhs); return rv -= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend VectorX<T, s> operator * (const VectorX<T, s> &lhs, T rhs) {
            VectorX<T, s> rv(lhs); return rv *= rhs;
        }

        // scalar multiply
        CPU_AND_GPU friend VectorX<T, s> operator * (T lhs, const VectorX<T, s> &rhs) {
            VectorX<T, s> rv(lhs); return rv *= rhs;
        }

        // vector component-wise multiply
        CPU_AND_GPU friend VectorX<T, s> operator * (const VectorX<T, s> &lhs, const VectorX<T, s> &rhs) {
            VectorX<T, s> rv(lhs); return rv *= rhs;
        }

        // scalar divide
        CPU_AND_GPU friend VectorX<T, s> operator / (const VectorX<T, s> &lhs, T rhs) {
            VectorX<T, s> rv(lhs); return rv /= rhs;
        }

        // vector component-wise divide
        CPU_AND_GPU friend VectorX<T, s> operator / (const VectorX<T, s> &lhs, const VectorX<T, s> &rhs) {
            VectorX<T, s> rv(lhs); return rv /= rhs;
        }

        ////////////////////////////////////////////////////////
        //  Comparison operators
        ////////////////////////////////////////////////////////

        // equality
        CPU_AND_GPU friend bool operator == (const VectorX<T, s> &lhs, const VectorX<T, s> &rhs) {
            for (int i = 0; i < s; i++) if (lhs[i] != rhs[i]) return false;
            return true;
        }

        // inequality
        CPU_AND_GPU friend bool operator != (const VectorX<T, s> &lhs, const Vector6<T> &rhs) {
            for (int i = 0; i < s; i++) if (lhs[i] != rhs[i]) return true;
            return false;
        }

        friend std::ostream& operator<<(std::ostream& os, const VectorX<T, s>& dt){
            for (int i = 0; i < s; i++) os << dt[i] << "\n";
            return os;
        }
    };

    ////////////////////////////////////////////////////////////////////////////////
    // Generic vector operations
    ////////////////////////////////////////////////////////////////////////////////

    template< class T> CPU_AND_GPU inline T sqr(const T &v) { return v*v; }

    // compute the dot product of two vectors
    template<class T> CPU_AND_GPU inline typename T::value_type dot(const T &lhs, const T &rhs) {
        typename T::value_type r = 0;
        for (int i = 0; i < lhs.size(); i++)
            r += lhs[i] * rhs[i];
        return r;
    }

    // return the squared length of the provided vector, i.e. the dot product with itself
    template< class T> CPU_AND_GPU inline typename T::value_type length2(const T &vec) {
        return dot(vec, vec);
    }

    // return the length of the provided vector
    template< class T> CPU_AND_GPU inline typename T::value_type length(const T &vec) {
        return sqrt(length2(vec));
    }

    // return the normalized version of the vector
    template< class T> CPU_AND_GPU inline T normalize(const T &vec)	{
        typename T::value_type sum = length(vec);
        return sum == 0 ? T(typename T::value_type(0)) : vec / sum;
    }

    //template< class T> CPU_AND_GPU inline T min(const T &lhs, const T &rhs) {
    //	return lhs <= rhs ? lhs : rhs;
    //}

    //template< class T> CPU_AND_GPU inline T max(const T &lhs, const T &rhs) {
    //	return lhs >= rhs ? lhs : rhs;
    //}

    //component wise min
    template< class T> CPU_AND_GPU inline T minV(const T &lhs, const T &rhs) {
        T rv;
        for (int i = 0; i < lhs.size(); i++)
            rv[i] = min(lhs[i], rhs[i]);
        return rv;
    }

    // component wise max
    template< class T>
    CPU_AND_GPU inline T maxV(const T &lhs, const T &rhs)	{
        T rv;
        for (int i = 0; i < lhs.size(); i++)
            rv[i] = max(lhs[i], rhs[i]);
        return rv;
    }


    // cross product
    template< class T>
    CPU_AND_GPU Vector3<T> cross(const Vector3<T> &lhs, const Vector3<T> &rhs) {
        Vector3<T> r;
        r.x = lhs.y * rhs.z - lhs.z * rhs.y;
        r.y = lhs.z * rhs.x - lhs.x * rhs.z;
        r.z = lhs.x * rhs.y - lhs.y * rhs.x;
        return r;
    }























    /************************************************************************/
    /* WARNING: the following 3x3 and 4x4 matrix are using column major, to	*/
    /* be consistent with OpenGL default rather than most C/C++ default.	*/
    /* In all other parts of the code, we still use row major order.		*/
    /************************************************************************/
    template <class T> class Vector2;
    template <class T> class Vector3;
    template <class T> class Vector4;
    template <class T, int s> class VectorX;

    //////////////////////////////////////////////////////////////////////////
    //						Basic Matrix Structure
    //////////////////////////////////////////////////////////////////////////

    template <class T> struct Matrix4_{
        union {
            struct { // Warning: see the header in this file for the special matrix order
                T m00, m01, m02, m03;	// |0, 4, 8,  12|    |m00, m10, m20, m30|
                T m10, m11, m12, m13;	// |1, 5, 9,  13|    |m01, m11, m21, m31|
                T m20, m21, m22, m23;	// |2, 6, 10, 14|    |m02, m12, m22, m32|
                T m30, m31, m32, m33;	// |3, 7, 11, 15|    |m03, m13, m23, m33|
            };
            T m[16];
        };
    };

    template <class T> struct Matrix3_{
        union { // Warning: see the header in this file for the special matrix order
            struct {
                T m00, m01, m02; // |0, 3, 6|     |m00, m10, m20|
                T m10, m11, m12; // |1, 4, 7|     |m01, m11, m21|
                T m20, m21, m22; // |2, 5, 8|     |m02, m12, m22|
            };
            T m[9];
        };
    };

    template<class T, int s> struct MatrixSQX_{
        int dim;
        int sq;
        T m[s*s];
    };

    template<class T>
    class Matrix3;
    //////////////////////////////////////////////////////////////////////////
    // Matrix class with math operators
    //////////////////////////////////////////////////////////////////////////
    template<class T>
    class Matrix4 : public Matrix4_ < T >
    {
    public:
        CPU_AND_GPU Matrix4() {}
        CPU_AND_GPU Matrix4(T t) { setValues(t); }
        CPU_AND_GPU Matrix4(const T *m)	{ setValues(m); }
        CPU_AND_GPU Matrix4(T a00, T a01, T a02, T a03, T a10, T a11, T a12, T a13, T a20, T a21, T a22, T a23, T a30, T a31, T a32, T a33)	{
            this->m00 = a00; this->m01 = a01; this->m02 = a02; this->m03 = a03;
            this->m10 = a10; this->m11 = a11; this->m12 = a12; this->m13 = a13;
            this->m20 = a20; this->m21 = a21; this->m22 = a22; this->m23 = a23;
            this->m30 = a30; this->m31 = a31; this->m32 = a32; this->m33 = a33;
        }

#define Rij(row, col) R.m[row + 3 * col]
        CPU_AND_GPU Matrix3<T> GetR(void) const
        {
            Matrix3<T> R;
            Rij(0, 0) = m[0 + 4 * 0]; Rij(1, 0) = m[1 + 4 * 0]; Rij(2, 0) = m[2 + 4 * 0];
            Rij(0, 1) = m[0 + 4 * 1]; Rij(1, 1) = m[1 + 4 * 1]; Rij(2, 1) = m[2 + 4 * 1];
            Rij(0, 2) = m[0 + 4 * 2]; Rij(1, 2) = m[1 + 4 * 2]; Rij(2, 2) = m[2 + 4 * 2];

            return R;
        }

        CPU_AND_GPU void SetR(const Matrix3<T>& R) {
            m[0 + 4 * 0] = Rij(0, 0); m[1 + 4 * 0] = Rij(1, 0); m[2 + 4 * 0] = Rij(2, 0);
            m[0 + 4 * 1] = Rij(0, 1); m[1 + 4 * 1] = Rij(1, 1); m[2 + 4 * 1] = Rij(2, 1);
            m[0 + 4 * 2] = Rij(0, 2); m[1 + 4 * 2] = Rij(1, 2); m[2 + 4 * 2] = Rij(2, 2);
        }
#undef Rij

        CPU_AND_GPU inline void getValues(T *mp) const	{ memcpy(mp, this->m, sizeof(T) * 16); }
        CPU_AND_GPU inline const T *getValues() const { return this->m; }
        CPU_AND_GPU inline Vector3<T> getScale() const { return Vector3<T>(this->m00, this->m11, this->m22); }

        // Element access
        CPU_AND_GPU inline T &operator()(int x, int y)	{ return at(x, y); }
        CPU_AND_GPU inline const T &operator()(int x, int y) const	{ return at(x, y); }
        CPU_AND_GPU inline T &operator()(Vector2<int> pnt)	{ return at(pnt.x, pnt.y); }
        CPU_AND_GPU inline const T &operator()(Vector2<int> pnt) const	{ return at(pnt.x, pnt.y); }
        CPU_AND_GPU inline T &at(int x, int y) { return this->m[y | (x << 2)]; }
        CPU_AND_GPU inline const T &at(int x, int y) const { return this->m[y | (x << 2)]; }

        // set values
        CPU_AND_GPU inline void setValues(const T *mp) { memcpy(this->m, mp, sizeof(T) * 16); }
        CPU_AND_GPU inline void setValues(T r)	{ for (int i = 0; i < 16; i++)	this->m[i] = r; }
        CPU_AND_GPU inline void setZeros() { memset(this->m, 0, sizeof(T) * 16); }
        CPU_AND_GPU inline void setIdentity() { setZeros(); this->m00 = this->m11 = this->m22 = this->m33 = 1; }
        CPU_AND_GPU inline void setScale(T s) { this->m00 = this->m11 = this->m22 = s; }
        CPU_AND_GPU inline void setScale(const Vector3_<T> &s) { this->m00 = s.v[0]; this->m11 = s.v[1]; this->m22 = s.v[2]; }
        CPU_AND_GPU inline void setTranslate(const Vector3_<T> &t) { for (int y = 0; y < 3; y++) at(3, y) = t.v[y]; }
        CPU_AND_GPU inline void setRow(int r, const Vector4_<T> &t){ for (int x = 0; x < 4; x++) at(x, r) = t.v[x]; }
        CPU_AND_GPU inline void setColumn(int c, const Vector4_<T> &t) { memcpy(this->m + 4 * c, t.v, sizeof(T) * 4); }

        // get values
        CPU_AND_GPU inline Vector3<T> getTranslate() const {
            Vector3<T> T;
            for (int y = 0; y < 3; y++)
                T.v[y] = m[y + 4 * 3];
            return T;
        }
        CPU_AND_GPU inline Vector4<T> getRow(int r) const { Vector4<T> v; for (int x = 0; x < 4; x++) v.v[x] = at(x, r); return v; }
        CPU_AND_GPU inline Vector4<T> getColumn(int c) const { Vector4<T> v; memcpy(v.v, this->m + 4 * c, sizeof(T) * 4); return v; }
        CPU_AND_GPU inline Matrix4 t() { // transpose
            Matrix4 mtrans;
            for (int x = 0; x < 4; x++)	for (int y = 0; y < 4; y++)
                mtrans(x, y) = at(y, x);
            return mtrans;
        }

        CPU_AND_GPU inline friend Matrix4 operator * (const Matrix4 &lhs, const Matrix4 &rhs)	{
            Matrix4 r;
            r.setZeros();
            for (int x = 0; x < 4; x++) for (int y = 0; y < 4; y++) for (int k = 0; k < 4; k++)
                r(x, y) += lhs(k, y) * rhs(x, k);
            return r;
        }

        CPU_AND_GPU inline friend Matrix4 operator + (const Matrix4 &lhs, const Matrix4 &rhs) {
            Matrix4 res(lhs.m);
            return res += rhs;
        }

        CPU_AND_GPU inline Vector4<T> operator *(const Vector4<T> &rhs) const {
            Vector4<T> r;
            r[0] = this->m[0] * rhs[0] + this->m[4] * rhs[1] + this->m[8] * rhs[2] + this->m[12] * rhs[3];
            r[1] = this->m[1] * rhs[0] + this->m[5] * rhs[1] + this->m[9] * rhs[2] + this->m[13] * rhs[3];
            r[2] = this->m[2] * rhs[0] + this->m[6] * rhs[1] + this->m[10] * rhs[2] + this->m[14] * rhs[3];
            r[3] = this->m[3] * rhs[0] + this->m[7] * rhs[1] + this->m[11] * rhs[2] + this->m[15] * rhs[3];
            return r;
        }

        // Used as a projection matrix to multiply with the Vector3
        CPU_AND_GPU inline Vector3<T> operator *(const Vector3<T> &rhs) const {
            Vector3<T> r;
            r[0] = this->m[0] * rhs[0] + this->m[4] * rhs[1] + this->m[8] * rhs[2] + this->m[12];
            r[1] = this->m[1] * rhs[0] + this->m[5] * rhs[1] + this->m[9] * rhs[2] + this->m[13];
            r[2] = this->m[2] * rhs[0] + this->m[6] * rhs[1] + this->m[10] * rhs[2] + this->m[14];
            return r;
        }

        CPU_AND_GPU inline friend Vector4<T> operator *(const Vector4<T> &lhs, const Matrix4 &rhs){
            Vector4<T> r;
            for (int x = 0; x < 4; x++)
                r[x] = lhs[0] * rhs(x, 0) + lhs[1] * rhs(x, 1) + lhs[2] * rhs(x, 2) + lhs[3] * rhs(x, 3);
            return r;
        }

        CPU_AND_GPU inline Matrix4& operator += (const T &r) { for (int i = 0; i < 16; ++i) this->m[i] += r; return *this; }
        CPU_AND_GPU inline Matrix4& operator -= (const T &r) { for (int i = 0; i < 16; ++i) this->m[i] -= r; return *this; }
        CPU_AND_GPU inline Matrix4& operator *= (const T &r) { for (int i = 0; i < 16; ++i) this->m[i] *= r; return *this; }
        CPU_AND_GPU inline Matrix4& operator /= (const T &r) { for (int i = 0; i < 16; ++i) this->m[i] /= r; return *this; }
        CPU_AND_GPU inline Matrix4 &operator += (const Matrix4 &mat) { for (int i = 0; i < 16; ++i) this->m[i] += mat.m[i]; return *this; }
        CPU_AND_GPU inline Matrix4 &operator -= (const Matrix4 &mat) { for (int i = 0; i < 16; ++i) this->m[i] -= mat.m[i]; return *this; }

        CPU_AND_GPU inline friend bool operator == (const Matrix4 &lhs, const Matrix4 &rhs) {
            bool r = lhs.m[0] == rhs.m[0];
            for (int i = 1; i < 16; i++)
                r &= lhs.m[i] == rhs.m[i];
            return r;
        }

        CPU_AND_GPU inline friend bool operator != (const Matrix4 &lhs, const Matrix4 &rhs) {
            bool r = lhs.m[0] != rhs.m[0];
            for (int i = 1; i < 16; i++)
                r |= lhs.m[i] != rhs.m[i];
            return r;
        }

        CPU_AND_GPU inline Matrix4 getInv() const {
            Matrix4 out;
            this->inv(out);
            return out;
        }
        /// Set out to be the inverse matrix of this.
        CPU_AND_GPU inline bool inv(Matrix4 &out) const {
            T tmp[12], src[16], det;
            T *dst = out.m;
            for (int i = 0; i < 4; i++) {
                src[i] = this->m[i * 4];
                src[i + 4] = this->m[i * 4 + 1];
                src[i + 8] = this->m[i * 4 + 2];
                src[i + 12] = this->m[i * 4 + 3];
            }

            tmp[0] = src[10] * src[15];
            tmp[1] = src[11] * src[14];
            tmp[2] = src[9] * src[15];
            tmp[3] = src[11] * src[13];
            tmp[4] = src[9] * src[14];
            tmp[5] = src[10] * src[13];
            tmp[6] = src[8] * src[15];
            tmp[7] = src[11] * src[12];
            tmp[8] = src[8] * src[14];
            tmp[9] = src[10] * src[12];
            tmp[10] = src[8] * src[13];
            tmp[11] = src[9] * src[12];

            dst[0] = (tmp[0] * src[5] + tmp[3] * src[6] + tmp[4] * src[7]) - (tmp[1] * src[5] + tmp[2] * src[6] + tmp[5] * src[7]);
            dst[1] = (tmp[1] * src[4] + tmp[6] * src[6] + tmp[9] * src[7]) - (tmp[0] * src[4] + tmp[7] * src[6] + tmp[8] * src[7]);
            dst[2] = (tmp[2] * src[4] + tmp[7] * src[5] + tmp[10] * src[7]) - (tmp[3] * src[4] + tmp[6] * src[5] + tmp[11] * src[7]);
            dst[3] = (tmp[5] * src[4] + tmp[8] * src[5] + tmp[11] * src[6]) - (tmp[4] * src[4] + tmp[9] * src[5] + tmp[10] * src[6]);

            det = src[0] * dst[0] + src[1] * dst[1] + src[2] * dst[2] + src[3] * dst[3];
            if (det == 0.0f)
                return false;

            dst[4] = (tmp[1] * src[1] + tmp[2] * src[2] + tmp[5] * src[3]) - (tmp[0] * src[1] + tmp[3] * src[2] + tmp[4] * src[3]);
            dst[5] = (tmp[0] * src[0] + tmp[7] * src[2] + tmp[8] * src[3]) - (tmp[1] * src[0] + tmp[6] * src[2] + tmp[9] * src[3]);
            dst[6] = (tmp[3] * src[0] + tmp[6] * src[1] + tmp[11] * src[3]) - (tmp[2] * src[0] + tmp[7] * src[1] + tmp[10] * src[3]);
            dst[7] = (tmp[4] * src[0] + tmp[9] * src[1] + tmp[10] * src[2]) - (tmp[5] * src[0] + tmp[8] * src[1] + tmp[11] * src[2]);

            tmp[0] = src[2] * src[7];
            tmp[1] = src[3] * src[6];
            tmp[2] = src[1] * src[7];
            tmp[3] = src[3] * src[5];
            tmp[4] = src[1] * src[6];
            tmp[5] = src[2] * src[5];
            tmp[6] = src[0] * src[7];
            tmp[7] = src[3] * src[4];
            tmp[8] = src[0] * src[6];
            tmp[9] = src[2] * src[4];
            tmp[10] = src[0] * src[5];
            tmp[11] = src[1] * src[4];

            dst[8] = (tmp[0] * src[13] + tmp[3] * src[14] + tmp[4] * src[15]) - (tmp[1] * src[13] + tmp[2] * src[14] + tmp[5] * src[15]);
            dst[9] = (tmp[1] * src[12] + tmp[6] * src[14] + tmp[9] * src[15]) - (tmp[0] * src[12] + tmp[7] * src[14] + tmp[8] * src[15]);
            dst[10] = (tmp[2] * src[12] + tmp[7] * src[13] + tmp[10] * src[15]) - (tmp[3] * src[12] + tmp[6] * src[13] + tmp[11] * src[15]);
            dst[11] = (tmp[5] * src[12] + tmp[8] * src[13] + tmp[11] * src[14]) - (tmp[4] * src[12] + tmp[9] * src[13] + tmp[10] * src[14]);
            dst[12] = (tmp[2] * src[10] + tmp[5] * src[11] + tmp[1] * src[9]) - (tmp[4] * src[11] + tmp[0] * src[9] + tmp[3] * src[10]);
            dst[13] = (tmp[8] * src[11] + tmp[0] * src[8] + tmp[7] * src[10]) - (tmp[6] * src[10] + tmp[9] * src[11] + tmp[1] * src[8]);
            dst[14] = (tmp[6] * src[9] + tmp[11] * src[11] + tmp[3] * src[8]) - (tmp[10] * src[11] + tmp[2] * src[8] + tmp[7] * src[9]);
            dst[15] = (tmp[10] * src[10] + tmp[4] * src[8] + tmp[9] * src[9]) - (tmp[8] * src[9] + tmp[11] * src[10] + tmp[5] * src[8]);

            out *= 1 / det;
            return true;
        }

        friend std::ostream& operator<<(std::ostream& os, const Matrix4<T>& dt) {
            for (int y = 0; y < 4; y++)
                os << dt(0, y) << ", " << dt(1, y) << ", " << dt(2, y) << ", " << dt(3, y) << "\n";
            return os;
        }

        friend std::istream& operator>>(std::istream& s, Matrix4<T>& dt) {
            for (int y = 0; y < 4; y++)
                s >> dt(0, y) >> dt(1, y) >> dt(2, y) >> dt(3, y);
            return s;
        }
    };

    template<class T>
    class Matrix3 : public Matrix3_ < T >
    {
    public:
        CPU_AND_GPU Matrix3() {}
        CPU_AND_GPU Matrix3(T t) { setValues(t); }
        CPU_AND_GPU Matrix3(const T *m)	{ setValues(m); }
        CPU_AND_GPU Matrix3(T a00, T a01, T a02, T a10, T a11, T a12, T a20, T a21, T a22)	{
            this->m00 = a00; this->m01 = a01; this->m02 = a02;
            this->m10 = a10; this->m11 = a11; this->m12 = a12;
            this->m20 = a20; this->m21 = a21; this->m22 = a22;
        }

        CPU_AND_GPU inline void getValues(T *mp) const	{ memcpy(mp, this->m, sizeof(T) * 9); }
        CPU_AND_GPU inline const T *getValues() const { return this->m; }
        CPU_AND_GPU inline Vector3<T> getScale() const { return Vector3<T>(this->m00, this->m11, this->m22); }

        // Element access
        CPU_AND_GPU inline T &operator()(int x, int y)	{ return at(x, y); }
        CPU_AND_GPU inline const T &operator()(int x, int y) const	{ return at(x, y); }
        CPU_AND_GPU inline T &operator()(Vector2<int> pnt)	{ return at(pnt.x, pnt.y); }
        CPU_AND_GPU inline const T &operator()(Vector2<int> pnt) const	{ return at(pnt.x, pnt.y); }
        CPU_AND_GPU inline T &at(int x, int y) { return this->m[x * 3 + y]; }
        CPU_AND_GPU inline const T &at(int x, int y) const { return this->m[x * 3 + y]; }

        // set values
        CPU_AND_GPU inline void setValues(const T *mp) { memcpy(this->m, mp, sizeof(T) * 9); }
        CPU_AND_GPU inline void setValues(const T r)	{ for (int i = 0; i < 9; i++)	this->m[i] = r; }
        CPU_AND_GPU inline void setZeros() { memset(this->m, 0, sizeof(T) * 9); }
        CPU_AND_GPU inline void setIdentity() { setZeros(); this->m00 = this->m11 = this->m22 = 1; }
        CPU_AND_GPU inline void setScale(T s) { this->m00 = this->m11 = this->m22 = s; }
        CPU_AND_GPU inline void setScale(const Vector3_<T> &s) { this->m00 = s[0]; this->m11 = s[1]; this->m22 = s[2]; }
        CPU_AND_GPU inline void setRow(int r, const Vector3_<T> &t){ for (int x = 0; x < 3; x++) at(x, r) = t[x]; }
        CPU_AND_GPU inline void setColumn(int c, const Vector3_<T> &t) { memcpy(this->m + 3 * c, t.v, sizeof(T) * 3); }

        // get values
        CPU_AND_GPU inline Vector3<T> getRow(int r) const { Vector3<T> v; for (int x = 0; x < 3; x++) v[x] = at(x, r); return v; }
        CPU_AND_GPU inline Vector3<T> getColumn(int c) const { Vector3<T> v; memcpy(v.v, this->m + 3 * c, sizeof(T) * 3); return v; }
        CPU_AND_GPU inline Matrix3 t() { // transpose
            Matrix3 mtrans;
            for (int x = 0; x < 3; x++)	for (int y = 0; y < 3; y++)
                mtrans(x, y) = at(y, x);
            return mtrans;
        }

        CPU_AND_GPU inline friend Matrix3 operator * (const Matrix3 &lhs, const Matrix3 &rhs)	{
            Matrix3 r;
            r.setZeros();
            for (int x = 0; x < 3; x++) for (int y = 0; y < 3; y++) for (int k = 0; k < 3; k++)
                r(x, y) += lhs(k, y) * rhs(x, k);
            return r;
        }

        CPU_AND_GPU inline friend Matrix3 operator + (const Matrix3 &lhs, const Matrix3 &rhs) {
            Matrix3 res(lhs.m);
            return res += rhs;
        }

        CPU_AND_GPU inline Vector3<T> operator *(const Vector3<T> &rhs) const {
            Vector3<T> r;
            r[0] = this->m[0] * rhs[0] + this->m[3] * rhs[1] + this->m[6] * rhs[2];
            r[1] = this->m[1] * rhs[0] + this->m[4] * rhs[1] + this->m[7] * rhs[2];
            r[2] = this->m[2] * rhs[0] + this->m[5] * rhs[1] + this->m[8] * rhs[2];
            return r;
        }

        CPU_AND_GPU inline Matrix3& operator *(const T &r) const {
            Matrix3 res(this->m);
            return res *= r;
        }

        CPU_AND_GPU inline friend Vector3<T> operator *(const Vector3<T> &lhs, const Matrix3 &rhs){
            Vector3<T> r;
            for (int x = 0; x < 3; x++)
                r[x] = lhs[0] * rhs(x, 0) + lhs[1] * rhs(x, 1) + lhs[2] * rhs(x, 2);
            return r;
        }

        CPU_AND_GPU inline Matrix3& operator += (const T &r) { for (int i = 0; i < 9; ++i) this->m[i] += r; return *this; }
        CPU_AND_GPU inline Matrix3& operator -= (const T &r) { for (int i = 0; i < 9; ++i) this->m[i] -= r; return *this; }
        CPU_AND_GPU inline Matrix3& operator *= (const T &r) { for (int i = 0; i < 9; ++i) this->m[i] *= r; return *this; }
        CPU_AND_GPU inline Matrix3& operator /= (const T &r) { for (int i = 0; i < 9; ++i) this->m[i] /= r; return *this; }
        CPU_AND_GPU inline Matrix3& operator += (const Matrix3 &mat) { for (int i = 0; i < 9; ++i) this->m[i] += mat.m[i]; return *this; }
        CPU_AND_GPU inline Matrix3& operator -= (const Matrix3 &mat) { for (int i = 0; i < 9; ++i) this->m[i] -= mat.m[i]; return *this; }

        CPU_AND_GPU inline friend bool operator == (const Matrix3 &lhs, const Matrix3 &rhs) {
            bool r = lhs[0] == rhs[0];
            for (int i = 1; i < 9; i++)
                r &= lhs[i] == rhs[i];
            return r;
        }

        CPU_AND_GPU inline friend bool operator != (const Matrix3 &lhs, const Matrix3 &rhs) {
            bool r = lhs[0] != rhs[0];
            for (int i = 1; i < 9; i++)
                r |= lhs[i] != rhs[i];
            return r;
        }

        /// Matrix determinant
        CPU_AND_GPU inline T det() const {
            return (this->m11*this->m22 - this->m12*this->m21)*this->m00 + (this->m12*this->m20 - this->m10*this->m22)*this->m01 + (this->m10*this->m21 - this->m11*this->m20)*this->m02;
        }

        /// The inverse matrix for float/double type
        CPU_AND_GPU inline bool inv(Matrix3 &out) const {
            T determinant = det();
            if (determinant == 0) {
                out.setZeros();
                return false;
            }

            out.m00 = (this->m11*this->m22 - this->m12*this->m21) / determinant;
            out.m01 = (this->m02*this->m21 - this->m01*this->m22) / determinant;
            out.m02 = (this->m01*this->m12 - this->m02*this->m11) / determinant;
            out.m10 = (this->m12*this->m20 - this->m10*this->m22) / determinant;
            out.m11 = (this->m00*this->m22 - this->m02*this->m20) / determinant;
            out.m12 = (this->m02*this->m10 - this->m00*this->m12) / determinant;
            out.m20 = (this->m10*this->m21 - this->m11*this->m20) / determinant;
            out.m21 = (this->m01*this->m20 - this->m00*this->m21) / determinant;
            out.m22 = (this->m00*this->m11 - this->m01*this->m10) / determinant;
            return true;
        }

        friend std::ostream& operator<<(std::ostream& os, const Matrix3<T>& dt)	{
            for (int y = 0; y < 3; y++)
                os << dt(0, y) << ", " << dt(1, y) << ", " << dt(2, y) << "\n";
            return os;
        }
    };

    template<class T, int s>
    class MatrixSQX : public MatrixSQX_ < T, s >
    {
    public:
        CPU_AND_GPU MatrixSQX() { this->dim = s; this->sq = s*s; }
        CPU_AND_GPU MatrixSQX(T t) { this->dim = s; this->sq = s*s; setValues(t); }
        CPU_AND_GPU MatrixSQX(const T *m)	{ this->dim = s; this->sq = s*s; setValues(m); }
        CPU_AND_GPU MatrixSQX(const T m[s][s])	{ this->dim = s; this->sq = s*s; setValues((T*)m); }

        CPU_AND_GPU inline void getValues(T *mp) const	{ memcpy(mp, this->m, sizeof(T) * 16); }
        CPU_AND_GPU inline const T *getValues() const { return this->m; }

        CPU_AND_GPU static inline MatrixSQX<T, s> make_aaT(const VectorX<float, s>& a) {
            float a_aT[s][s];
            for (int c = 0; c < s; c++)
                for (int r = 0; r < s; r++)
                    a_aT[c][r] = a[c] * a[r];
            return a_aT;
        }

        CPU_AND_GPU static inline MatrixSQX<T, s> make_zeros() {
            MatrixSQX<T, s> x;
            x.setZeros();
            return x;
        }

        // Element access
        CPU_AND_GPU inline T &operator()(int x, int y)	{ return at(x, y); }
        CPU_AND_GPU inline const T &operator()(int x, int y) const	{ return at(x, y); }
        CPU_AND_GPU inline T &operator()(Vector2<int> pnt)	{ return at(pnt.x, pnt.y); }
        CPU_AND_GPU inline const T &operator()(Vector2<int> pnt) const	{ return at(pnt.x, pnt.y); }
        CPU_AND_GPU inline T &at(int x, int y) { return this->m[y * s + x]; }
        CPU_AND_GPU inline const T &at(int x, int y) const { return this->m[y * s + x]; }

        // indexing operators
        CPU_AND_GPU T &operator [](int i) { return this->m[i]; }
        CPU_AND_GPU const T &operator [](int i) const { return this->m[i]; }

        // set values
        CPU_AND_GPU inline void setValues(const T *mp) { for (int i = 0; i < s*s; i++) this->m[i] = mp[i]; }
        CPU_AND_GPU inline void setValues(T r)	{ for (int i = 0; i < s*s; i++)	this->m[i] = r; }
        CPU_AND_GPU inline void setZeros() { for (int i = 0; i < s*s; i++)	this->m[i] = 0; }
        CPU_AND_GPU inline void setIdentity() { setZeros(); for (int i = 0; i < s*s; i++) this->m[i + i*s] = 1; }

        // get values
        CPU_AND_GPU inline VectorX<T, s> getRow(int r) const { VectorX<T, s> v; for (int x = 0; x < s; x++) v[x] = at(x, r); return v; }
        CPU_AND_GPU inline VectorX<T, s> getColumn(int c) const { Vector4<T> v; for (int x = 0; x < s; x++) v[x] = at(c, x); return v; }
        CPU_AND_GPU inline MatrixSQX<T, s> getTranspose()
        { // transpose
            MatrixSQX<T, s> mtrans;
            for (int x = 0; x < s; x++)	for (int y = 0; y < s; y++)
                mtrans(x, y) = at(y, x);
            return mtrans;
        }

        CPU_AND_GPU inline friend  MatrixSQX<T, s> operator * (const  MatrixSQX<T, s> &lhs, const  MatrixSQX<T, s> &rhs)	{
            MatrixSQX<T, s> r;
            r.setZeros();
            for (int x = 0; x < s; x++) for (int y = 0; y < s; y++) for (int k = 0; k < s; k++)
                r(x, y) += lhs(k, y) * rhs(x, k);
            return r;
        }

        CPU_AND_GPU inline friend MatrixSQX<T, s> operator + (const MatrixSQX<T, s> &lhs, const MatrixSQX<T, s> &rhs) {
            MatrixSQX<T, s> res(lhs.m);
            return res += rhs;
        }

        CPU_AND_GPU inline MatrixSQX<T, s>& operator += (const T &r) { for (int i = 0; i < s*s; ++i) this->m[i] += r; return *this; }
        CPU_AND_GPU inline MatrixSQX<T, s>& operator -= (const T &r) { for (int i = 0; i < s*s; ++i) this->m[i] -= r; return *this; }
        CPU_AND_GPU inline MatrixSQX<T, s>& operator *= (const T &r) { for (int i = 0; i < s*s; ++i) this->m[i] *= r; return *this; }
        CPU_AND_GPU inline MatrixSQX<T, s>& operator /= (const T &r) { for (int i = 0; i < s*s; ++i) this->m[i] /= r; return *this; }
        CPU_AND_GPU inline MatrixSQX<T, s> &operator += (const MatrixSQX<T, s> &mat) { for (int i = 0; i < s*s; ++i) this->m[i] += mat.m[i]; return *this; }
        CPU_AND_GPU inline MatrixSQX<T, s> &operator -= (const MatrixSQX<T, s> &mat) { for (int i = 0; i < s*s; ++i) this->m[i] -= mat.m[i]; return *this; }

        CPU_AND_GPU inline friend bool operator == (const MatrixSQX<T, s> &lhs, const MatrixSQX<T, s> &rhs) {
            bool r = lhs[0] == rhs[0];
            for (int i = 1; i < s*s; i++)
                r &= lhs[i] == rhs[i];
            return r;
        }

        CPU_AND_GPU inline friend bool operator != (const MatrixSQX<T, s> &lhs, const MatrixSQX<T, s> &rhs) {
            bool r = lhs[0] != rhs[0];
            for (int i = 1; i < s*s; i++)
                r |= lhs[i] != rhs[i];
            return r;
        }

        friend std::ostream& operator<<(std::ostream& os, const MatrixSQX<T, s>& dt) {
            for (int y = 0; y < s; y++)
            {
                for (int x = 0; x < s; x++) os << dt(x, y) << "\t";
                os << "\n";
            }
            return os;
        }
    };

































    inline float assertFinite(float value) {
#ifdef _DEBUG
        assert(_fpclass(value) == _FPCLASS_PD || _fpclass(value) == _FPCLASS_PN || _fpclass(value) == _FPCLASS_PZ ||
            _fpclass(value) == _FPCLASS_ND || _fpclass(value) == _FPCLASS_NN || _fpclass(value) == _FPCLASS_NZ
            , "value = %f is not finite", value);
#endif
        return value;
    }

    // Solve Ax = b for A symmetric positive-definite
    // Usually, A = B^TB and b = B^Ty, as present in the normal-equations for solving linear least-squares problems
    class Cholesky
    {
    private:
        std::vector<float> cholesky;
        int size, rank;

    public:
        // Solve Ax = b for A symmetric positive-definite of size*size
        template<int m>
        static VectorX<float, m> solve(
            const MatrixSQX<float, m>& mat,
            const VectorX<float, m>&  b) {

            auto x = VectorX<float, m>();
            solve((const float*)mat.m, m, (const float*)b.v, x.v);
            return x;

        }

        // Solve Ax = b for A symmetric positive-definite of size*size
        static void solve(const float* mat, int size, const float* b, float* result) {
            Cholesky cholA(mat, size);
            cholA.Backsub(result, b);
        }

        /// \f[A = LL*\f]
        /// Produces Cholesky decomposition of the
        /// symmetric, positive-definite matrix mat of dimension size*size
        /// \f$L\f$ is a lower triangular matrix with real and positive diagonal entries
        ///
        /// Note: assertFinite is used to detect singular matrices and other non-supported cases.
        Cholesky(const float *mat, int size)
        {
            this->size = size;
            this->cholesky.resize(size*size);

            for (int i = 0; i < size * size; i++) cholesky[i] = assertFinite(mat[i]);

            for (int c = 0; c < size; c++)
            {
                float inv_diag = 1;
                for (int r = c; r < size; r++)
                {
                    float val = cholesky[c + r * size];
                    for (int c2 = 0; c2 < c; c2++)
                        val -= cholesky[c + c2 * size] * cholesky[c2 + r * size];

                    if (r == c)
                    {
                        cholesky[c + r * size] = assertFinite(val);
                        if (val == 0) { rank = r; }
                        inv_diag = 1.0f / val;
                    }
                    else
                    {
                        cholesky[r + c * size] = assertFinite(val);
                        cholesky[c + r * size] = assertFinite(val * inv_diag);
                    }
                }
            }

            rank = size;
        }

        /// Solves \f[Ax = b\f]
        /// by
        /// * solving Ly = b for y by forward substitution, and then
        /// * solving L*x = y for x by back substitution.
        void Backsub(
            float *x,  //!< out \f$x\f$
            const float *b //!< input \f$b\f$
            ) const
        {
            // Forward
            std::vector<float> y(size);
            for (int i = 0; i < size; i++)
            {
                float val = b[i];
                for (int j = 0; j < i; j++) val -= cholesky[j + i * size] * y[j];
                y[i] = val;
            }

            for (int i = 0; i < size; i++) y[i] /= cholesky[i + i * size];

            // Backward
            for (int i = size - 1; i >= 0; i--)
            {
                float val = y[i];
                for (int j = i + 1; j < size; j++) val -= cholesky[i + j * size] * x[j];
                x[i] = val;
            }
        }
    };

    TEST(testCholesky) {
        float m[] = {
            1, 0,
            0, 1
        };
        float b[] = {1, 2};
        float r[2];
        Cholesky::solve(m, 2, b, r);
        assert(r[0] == b[0] && r[1] == b[1]);
    }
























































    typedef unsigned char uchar;
    typedef unsigned short ushort;
    typedef unsigned long ulong;

    typedef class Matrix3<float> Matrix3f;
    typedef class Matrix4<float> Matrix4f;

    typedef class Vector2<short> Vector2s;
    typedef class Vector2<int> Vector2i;
    inline dim3 getGridSize(Vector2i taskSize, dim3 blockSize)
    {
        return getGridSize(dim3(taskSize.x, taskSize.y), blockSize);
    }
    typedef class Vector2<float> Vector2f;
    typedef class Vector2<double> Vector2d;

    typedef class Vector3<short> Vector3s;
    typedef class Vector3<double> Vector3d;
    typedef class Vector3<int> Vector3i;
    typedef class Vector3<uint> Vector3ui;
    typedef class Vector3<uchar> Vector3u;
    typedef class Vector3<float> Vector3f;
    typedef Vector3f UnitVector;

    typedef class Vector4<float> Vector4f;
    typedef class Vector4<int> Vector4i;
    typedef class Vector4<short> Vector4s;
    typedef class Vector4<uchar> Vector4u;

    typedef class Vector6<float> Vector6f;

#ifndef TO_INT_ROUND3
#define TO_INT_ROUND3(x) (x).toIntRound()
#endif

#ifndef TO_INT_ROUND4
#define TO_INT_ROUND4(x) (x).toIntRound()
#endif

#ifndef TO_INT_FLOOR3
#define TO_INT_FLOOR3(inted, coeffs, in) inted = (in).toIntFloor(coeffs)
#endif

#ifndef TO_SHORT_FLOOR3
#define TO_SHORT_FLOOR3(x) (x).toShortFloor()
#endif

#ifndef TO_UCHAR3
#define TO_UCHAR3(x) (x).toUChar()
#endif

#ifndef TO_FLOAT3
#define TO_FLOAT3(x) (x).toFloat()
#endif

#ifndef TO_SHORT3
#define TO_SHORT3(p) Vector3s(p.x, p.y, p.z)
#endif

#ifndef TO_VECTOR3
#define TO_VECTOR3(a) (a).toVector3()
#endif

#ifndef IS_EQUAL3
#define IS_EQUAL3(a,b) (((a).x == (b).x) && ((a).y == (b).y) && ((a).z == (b).z))
#endif

    inline CPU_AND_GPU Vector4f toFloat(Vector4u c) {
        return c.toFloat();
    }

    inline CPU_AND_GPU Vector4f toFloat(Vector4f c) {
        return c;
    }
    inline CPU_AND_GPU float toFloat(float c) {
        return c;
    }





























    /// Alternative/external implementation of axis-angle rotation matrix construction
    /// axis does not need to be normalized.
    /// c.f. ITMPose
    Matrix3f createRotation(const Vector3f & _axis, float angle)
    {
        Vector3f axis = normalize(_axis);
        float si = sinf(angle);
        float co = cosf(angle);

        Matrix3f ret;
        ret.setIdentity();

        ret *= co;
        for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c) ret.at(c, r) += (1.0f - co) * axis[c] * axis[r];

        Matrix3f skewmat;
        skewmat.setZeros();
        skewmat.at(1, 0) = -axis.z;
        skewmat.at(0, 1) = axis.z;
        skewmat.at(2, 0) = axis.y;
        skewmat.at(0, 2) = -axis.y;
        skewmat.at(2, 1) = -axis.x; // should be axis.x?! c.f. infinitam
        skewmat.at(1, 2) = axis.x;// should be -axis.x;
        skewmat *= si;
        ret += skewmat;

        return ret;
    }




















#define Rij(row, col) R.m[row + 3 * col]

    /** \brief
    Represents a rigid body pose with rotation and translation
    parameters.

    When used as a camera pose, by convention, this represents the world-to-camera transform.
    */
    class ITMPose
    {
    private:
        void SetRPartOfM(const Matrix3f& R) {
            M.SetR(R);
        }

        /** This is the minimal representation of the pose with
        six parameters. The three rotation parameters are
        the Lie algebra representation of SO3.
        */
        union
        {
            float all[6];
            struct {
                float tx, ty, tz;
                float rx, ry, rz;
            }each;
            struct {
                Vector3f t;
                // r is an "Euler vector", i.e. the vector "axis of rotation (u) * theta" (axis angle representation)
                Vector3f r;
            };
        } params;

        /** The pose as a 4x4 transformation matrix (world-to-camera transform, modelview
        matrix).
        */
        Matrix4f M;

        /** This will update the minimal parameterisation from
        the current modelview matrix.
        */
        void SetParamsFromModelView();

        /** This will update the "modelview matrix" M from the
        minimal representation.
        */
        void SetModelViewFromParams();
    public:

        void SetFrom(float tx, float ty, float tz, float rx, float ry, float rz);
        void SetFrom(const Vector3f &translation, const Vector3f &rotation);
        void SetFrom(const Vector6f &tangent);

        /// float tx, float ty, float tz, float rx, float ry, float rz
        void SetFrom(const float pose[6]);
        void SetFrom(const ITMPose *pose);

        /** This will multiply a pose @p pose on the right, i.e.
        this = this * pose.
        */
        void MultiplyWith(const ITMPose *pose);

        const Matrix4f & GetM(void) const
        {
            return M;
        }

        Matrix3f GetR(void) const;
        Vector3f GetT(void) const;

        void GetParams(Vector3f &translation, Vector3f &rotation);

        void SetM(const Matrix4f & M);

        void SetR(const Matrix3f & R);
        void SetT(const Vector3f & t);
        void SetRT(const Matrix3f & R, const Vector3f & t);

        Matrix4f GetInvM(void) const;
        void SetInvM(const Matrix4f & invM);

        /** This will enforce the orthonormality constraints on
        the rotation matrix. It's recommended to call this
        function after manipulating the matrix M.
        */
        void Coerce(void);

        ITMPose(const ITMPose & src);
        ITMPose(const Matrix4f & src);
        ITMPose(float tx, float ty, float tz, float rx, float ry, float rz);
        ITMPose(const Vector6f & tangent);
        explicit ITMPose(const float pose[6]);

        ITMPose(void);

        /** This builds a Pose based on its exp representation (c.f. exponential map in lie algebra, matrix exponential...)
        */
        static ITMPose exp(const Vector6f& tangent);
    };

    ITMPose::ITMPose(void) { this->SetFrom(0, 0, 0, 0, 0, 0); }

    ITMPose::ITMPose(float tx, float ty, float tz, float rx, float ry, float rz)
    {
        this->SetFrom(tx, ty, tz, rx, ry, rz);
    }
    ITMPose::ITMPose(const float pose[6]) { this->SetFrom(pose); }
    ITMPose::ITMPose(const Matrix4f & src) { this->SetM(src); }
    ITMPose::ITMPose(const Vector6f & tangent) { this->SetFrom(tangent); }
    ITMPose::ITMPose(const ITMPose & src) { this->SetFrom(&src); }

    void ITMPose::SetFrom(float tx, float ty, float tz, float rx, float ry, float rz)
    {
        this->params.each.tx = tx;
        this->params.each.ty = ty;
        this->params.each.tz = tz;
        this->params.each.rx = rx;
        this->params.each.ry = ry;
        this->params.each.rz = rz;

        this->SetModelViewFromParams();
    }

    void ITMPose::SetFrom(const Vector3f &translation, const Vector3f &rotation)
    {
        this->params.each.tx = translation.x;
        this->params.each.ty = translation.y;
        this->params.each.tz = translation.z;
        this->params.each.rx = rotation.x;
        this->params.each.ry = rotation.y;
        this->params.each.rz = rotation.z;

        this->SetModelViewFromParams();
    }

    void ITMPose::SetFrom(const Vector6f &tangent)
    {
        this->params.each.tx = tangent[0];
        this->params.each.ty = tangent[1];
        this->params.each.tz = tangent[2];
        this->params.each.rx = tangent[3];
        this->params.each.ry = tangent[4];
        this->params.each.rz = tangent[5];

        this->SetModelViewFromParams();
    }

    void ITMPose::SetFrom(const float pose[6])
    {
        SetFrom(pose[0], pose[1], pose[2], pose[3], pose[4], pose[5]);
    }

    void ITMPose::SetFrom(const ITMPose *pose)
    {
        this->params.each.tx = pose->params.each.tx;
        this->params.each.ty = pose->params.each.ty;
        this->params.each.tz = pose->params.each.tz;
        this->params.each.rx = pose->params.each.rx;
        this->params.each.ry = pose->params.each.ry;
        this->params.each.rz = pose->params.each.rz;

        M = pose->M;
    }

    // init M from params
    void ITMPose::SetModelViewFromParams()
    {
        // w is an "Euler vector", i.e. the vector "axis of rotation (u) * theta" (axis angle representation)
        const Vector3f w = params.r;
        const float theta_sq = dot(w, w), theta = sqrt(theta_sq);
        const float inv_theta = 1.0f / theta;

        const Vector3f t = params.t;

        float A, B, C;
        /*
        Limit for t approximating theta

        A = lim_{t -> theta} Sin[t]/t
        B = lim_{t -> theta} (1 - Cos[t])/t^2
        C = lim_{t -> theta} (1 - A)/t^2
        */
        if (theta_sq < 1e-6f) // dont divide by very small or zero theta - use taylor series expansion of involved functions instead
        {
            A = 1 - theta_sq / 6 + theta_sq*theta_sq / 120; // Series[a, {t, 0, 4}]
            B = 1 / 2.f - theta_sq / 24;  //  Series[b, {t, 0, 2}]
            C = 1 / 6.f - theta_sq / 120; // Series[c, {t, 0, 2}]
        }
        else {
            A = sinf(theta) * inv_theta;
            B = (1.0f - cosf(theta)) * (inv_theta * inv_theta);
            C = (1.0f - A) * (inv_theta * inv_theta);
        }
        // TODO why isnt T = t?
        const Vector3f crossV = cross(w, t);
        const Vector3f cross2 = cross(w, crossV);
        const Vector3f T = t + B * crossV + C * cross2;

        // w = t u, u \in S^2, t === theta
        // R = exp(w . L) = I + sin(t) (u . L) + (1 - cos(t)) (u . L)^2
        // u . L == [u]_x, the matrix computing the left cross product with u (u x *)
        // L = (L_x, L_y, L_z) the lie algebra basis
        // c.f. https://en.wikipedia.org/wiki/Rotation_group_SO(3)#Exponential_map
        Matrix3f R;
        const float wx2 = w.x * w.x, wy2 = w.y * w.y, wz2 = w.z * w.z;
        Rij(0, 0) = 1.0f - B*(wy2 + wz2);
        Rij(1, 1) = 1.0f - B*(wx2 + wz2);
        Rij(2, 2) = 1.0f - B*(wx2 + wy2);

        float a, b;
        a = A * w.z, b = B * (w.x * w.y);
        Rij(0, 1) = b - a;
        Rij(1, 0) = b + a;

        a = A * w.y, b = B * (w.x * w.z);
        Rij(0, 2) = b + a;
        Rij(2, 0) = b - a;

        a = A * w.x, b = B * (w.y * w.z);
        Rij(1, 2) = b - a;
        Rij(2, 1) = b + a;

        // Copy to M
        SetRPartOfM(R);
        M.setTranslate(T);

        M.m[3 + 4 * 0] = 0.0f; M.m[3 + 4 * 1] = 0.0f; M.m[3 + 4 * 2] = 0.0f; M.m[3 + 4 * 3] = 1.0f;
    }

    // init params from M
    void ITMPose::SetParamsFromModelView()
    {
        // Compute this->params.r = resultRot;
        Vector3f resultRot;
        const Matrix3f R = GetR();

        const float cos_angle = (R.m00 + R.m11 + R.m22 - 1.0f) * 0.5f;
        resultRot.x = (Rij(2, 1) - Rij(1, 2)) * 0.5f;
        resultRot.y = (Rij(0, 2) - Rij(2, 0)) * 0.5f;
        resultRot.z = (Rij(1, 0) - Rij(0, 1)) * 0.5f;

        const float sin_angle_abs = length(resultRot);

        if (cos_angle > M_SQRT1_2)
        {
            if (sin_angle_abs)
            {
                const float p = asinf(sin_angle_abs) / sin_angle_abs;
                resultRot *= p;
            }
        }
        else
        {
            if (cos_angle > -M_SQRT1_2)
            {
                const float p = acosf(cos_angle) / sin_angle_abs;
                resultRot *= p;
            }
            else
            {
                const float angle = (float)M_PI - asinf(sin_angle_abs);
                const float d0 = Rij(0, 0) - cos_angle;
                const float d1 = Rij(1, 1) - cos_angle;
                const float d2 = Rij(2, 2) - cos_angle;

                Vector3f r2;

                if (fabsf(d0) > fabsf(d1) && fabsf(d0) > fabsf(d2)) {
                    r2.x = d0;
                    r2.y = (Rij(1, 0) + Rij(0, 1)) * 0.5f;
                    r2.z = (Rij(0, 2) + Rij(2, 0)) * 0.5f;
                }
                else {
                    if (fabsf(d1) > fabsf(d2)) {
                        r2.x = (Rij(1, 0) + Rij(0, 1)) * 0.5f;
                        r2.y = d1;
                        r2.z = (Rij(2, 1) + Rij(1, 2)) * 0.5f;
                    }
                    else {
                        r2.x = (Rij(0, 2) + Rij(2, 0)) * 0.5f;
                        r2.y = (Rij(2, 1) + Rij(1, 2)) * 0.5f;
                        r2.z = d2;
                    }
                }

                if (dot(r2, resultRot) < 0.0f) { r2 *= -1.0f; }

                r2 = normalize(r2);

                resultRot = angle * r2;
            }
        }

        this->params.r = resultRot;

        // Compute this->params.t = rottrans
        const Vector3f T = GetT();
        const float theta = length(resultRot);

        const float shtot = (theta > 0.00001f) ?
            sinf(theta * 0.5f) / theta :
            0.5f; // lim_{t -> theta} sin(t/2)/t, lim_{t -> 0} sin(t/2)/t = 0.5

        const ITMPose halfrotor(
            0.0f, 0.0f, 0.0f,
            resultRot.x * -0.5f, resultRot.y * -0.5f, resultRot.z * -0.5f
            );

        Vector3f rottrans = halfrotor.GetR() * T;

        const float param = dot(T, resultRot) *
            (
            (theta > 0.001f) ?
            (1 - 2 * shtot) / (theta * theta) :
            1 / 24.f // Series[(1 - 2*Sin[t/2]/t)/(t^2), {t, 0, 1}] = 1/24
            );

        rottrans -= resultRot * param;

        rottrans /= 2 * shtot;

        this->params.t = rottrans;
    }

    ITMPose ITMPose::exp(const Vector6f& tangent)
    {
        return ITMPose(tangent);
    }

    void ITMPose::MultiplyWith(const ITMPose *pose)
    {
        M = M * pose->M;
        this->SetParamsFromModelView();
    }

    Matrix3f ITMPose::GetR(void) const
    {
        return M.GetR();
    }

    Vector3f ITMPose::GetT(void) const
    {
        return M.getTranslate();
    }

    void ITMPose::GetParams(Vector3f &translation, Vector3f &rotation)
    {
        translation.x = this->params.each.tx;
        translation.y = this->params.each.ty;
        translation.z = this->params.each.tz;

        rotation.x = this->params.each.rx;
        rotation.y = this->params.each.ry;
        rotation.z = this->params.each.rz;
    }

    void ITMPose::SetM(const Matrix4f & src)
    {
        M = src;
        SetParamsFromModelView();
    }

    void ITMPose::SetR(const Matrix3f & R)
    {
        SetRPartOfM(R);
        SetParamsFromModelView();
    }

    void ITMPose::SetT(const Vector3f & t)
    {
        M.setTranslate(t);

        SetParamsFromModelView();
    }

    void ITMPose::SetRT(const Matrix3f & R, const Vector3f & t)
    {
        SetRPartOfM(R);
        M.setTranslate(t);

        SetParamsFromModelView();
    }

    Matrix4f ITMPose::GetInvM(void) const
    {
        Matrix4f ret;
        M.inv(ret);
        return ret;
    }

    void ITMPose::SetInvM(const Matrix4f & invM)
    {
        invM.inv(M);
        SetParamsFromModelView();
    }

    void ITMPose::Coerce(void)
    {
        SetParamsFromModelView();
        SetModelViewFromParams();
    }











    // Framework for building and solving (linear) least squares fitting problems on the GPU
    // c.f. constructAndSolve.nb

    namespace LeastSquares {


        /// Exchange information
        __managed__ long long transform_reduce_resultMemory[100 * 100]; // use only in one module

        template <typename T>
        CPU_AND_GPU T& transform_reduce_result() {
            assert(sizeof(T) <= sizeof(transform_reduce_resultMemory));
            return *(T*)transform_reduce_resultMemory;
        }

        /// Constructor must define
        /// Constructor::ExtraData(), add, atomicAdd
        /// static const uint Constructor::m
        /// bool Constructor::generate(const uint i, VectorX<float, m>& , float& bi)
        template<typename Constructor>
        struct AtA_Atb_Add {
            static const uint m = Constructor::m;
            typedef typename MatrixSQX<float, m> AtA;
            typedef typename VectorX<float, m> Atb;
            typedef typename Constructor::ExtraData ExtraData;

            struct ElementType {
                typename AtA _AtA;
                typename Atb _Atb;
                typename ExtraData _extraData;
                CPU_AND_GPU ElementType() {} // uninitialized on purpose
                CPU_AND_GPU ElementType(AtA _AtA, Atb _Atb, ExtraData _extraData) : _AtA(_AtA), _Atb(_Atb), _extraData(_extraData) {}
            };

            static GPU_ONLY bool generate(const uint i, ElementType& out) {
                // Some threads contribute zero
                VectorX<float, m> ai; float bi;
                if (!Constructor::generate(i, ai, bi, out._extraData)) return false;

                // Construct ai_aiT (an outer product matrix) and ai_bi
                out._AtA = MatrixSQX<float, m>::make_aaT(ai);
                out._Atb = ai * bi;
                return true;
            }

            static CPU_AND_GPU ElementType neutralElement() {
                return ElementType(
                    AtA::make_zeros(),
                    Atb::make_zeros(),
                    ExtraData());
            }

            static GPU_ONLY ElementType operate(ElementType & l, ElementType & r) {
                return ElementType(
                    l._AtA + r._AtA,
                    l._Atb + r._Atb,
                    ExtraData::add(l._extraData, r._extraData)
                    );
            }

            static GPU_ONLY void atomicOperate(DEVICEPTR(ElementType&) result, ElementType & integrand) {
                for (int r = 0; r < m*m; r++)
                    atomicAdd(
                    &result._AtA[r],
                    integrand._AtA[r]);

                for (int r = 0; r < m; r++)
                    atomicAdd(
                    &result._Atb[r],
                    integrand._Atb[r]);

                ExtraData::atomicAdd(result._extraData, integrand._extraData);
            }
        };


        const int MAX_REDUCE_BLOCK_SIZE = 4 * 4 * 4; // TODO this actually depends on shared memory demand of Constructor (::m, ExtraData etc.) -- template-specialize on it?

        template<class Constructor>
        KERNEL transform_reduce_if_device(const uint n) {
            const uint tid = linear_threadIdx();
            assert(tid < MAX_REDUCE_BLOCK_SIZE, "tid %d", tid);
            const uint i = linear_global_threadId();

            const uint _REDUCE_BLOCK_SIZE = volume(blockDim);

            // Whether this thread block needs to compute a prefix sum
            __shared__ bool shouldPrefix;
            shouldPrefix = false;
            __syncthreads();

            __shared__ typename Constructor::ElementType reduced_elements[MAX_REDUCE_BLOCK_SIZE]; // this is pretty heavy on shared memory!

            typename Constructor::ElementType& ei = reduced_elements[tid];
            if (i >= n || !Constructor::generate(i, ei)) {
                ei = Constructor::neutralElement();
            }
            else
                shouldPrefix = true;

            __syncthreads();

            if (!shouldPrefix) return;
            // only if at least one thread in the thread block gets here do we do the prefix sum.

            // tree reduction into reduced_elements[0]
            for (int offset = _REDUCE_BLOCK_SIZE / 2; offset >= 1; offset /= 2) {
                if (tid >= offset) return;

                reduced_elements[tid] = Constructor::operate(reduced_elements[tid], reduced_elements[tid + offset]);

                __syncthreads();
            }

            assert(tid == 0);

            // Sum globally, using atomics
            auto& result = transform_reduce_result<Constructor::ElementType>();
            Constructor::atomicOperate(result, reduced_elements[0]);
        }

        CPU_AND_GPU bool isPowerOf2(unsigned int x) {
#if GPU_CODE
            return __popc(x) <= 1;
#else
            return __popcnt(x) <= 1;
#endif
        }

        /**
        Constructor must provide:
        * Constructor::ElementType
        * Constructor::generate(i) which will be called with i from 0 to n and may return false causing its result to be replaced with
        * CPU_AND_GPU Constructor::neutralElement()
        * Constructor::operate and atomicOperate define the binary operation

        Constructor::generate is run once in each CUDA thread.
        The division into threads *can* be manually specified -- doing so will not significantly affect the outcome if the Constructor is agnostic to threadIdx et.al.
        If gridDim and/or blockDim are nonzero, it will be checked for conformance with n (must be bigger than or equal).
        gridDim can be left 0,0,0 in which case it is computed as ceil(n/volume(blockDim)),1,1.

        volume(blockDim) must be a power of 2 (for reduction) and <= MAX_REDUCE_BLOCK_SIZE

        Both gridDim and blockDim default to one-dimension.
        */
        template<class Constructor>
        Constructor::ElementType
            transform_reduce_if(const uint n, dim3 gridDim = dim3(0, 0, 0), dim3 blockDim = dim3(0, 0, 0)) {
            // Configure kernel scheduling
            if (gridDim.x == 0) {
                assert(gridDim.y == gridDim.z && gridDim.z == 0);

                if (blockDim.x == 0) {
                    assert(blockDim.y == blockDim.z && blockDim.z == 0);
                    blockDim = dim3(MAX_REDUCE_BLOCK_SIZE, 1, 1); // default to one-dimension
                }

                gridDim = dim3(ceil(n / volume(blockDim)), 1, 1); // default to one-dimension
            }
            assert(isPowerOf2(volume(blockDim)));

            assert(volume(gridDim)*volume(blockDim) >= n, "must have enough threads to generate each element");
            assert(volume(blockDim) > 0);
            assert(volume(blockDim) <= MAX_REDUCE_BLOCK_SIZE);

            // Set up storage for result
            transform_reduce_result<typename Constructor::ElementType>() = Constructor::neutralElement();

            LAUNCH_KERNEL(
                (transform_reduce_if_device<Constructor>),
                gridDim, blockDim,
                n);
            cudaDeviceSynchronize();

            return transform_reduce_result<Constructor::ElementType>();
        }

        /**
        Build A^T A and A^T b where A is <n x m and b has <n elements.

        Row i (0-based) of A and b[i] are generated by bool Constructor::generate(uint i, VectorX<float, m> out_ai, float& out_bi).
        It is thrown away if generate returns false.
        */
        template<class Constructor>
        AtA_Atb_Add<Constructor>::ElementType construct(const uint n, dim3 gridDim = dim3(0, 0, 0), dim3 blockDim = dim3(0, 0, 0)) {
            assert(Constructor::m < 100);
            return transform_reduce_if<AtA_Atb_Add<Constructor>>(n, gridDim, blockDim);
        }

        /// Given a Constructor with method
        ///     static __device__ Constructor::generate(uint i, VectorX<float, m> out_ai, float& out_bi)
        /// and static uint Constructor::m
        /// build the equation system Ax = b with out_ai, out_bi in the i-th row/entry of A or b
        /// Then solve this in the least-squares sense and return x.
        ///
        /// i goes from 0 to n-1.
        ///
        /// Custom scheduling can be used and any custom Constructor::ExtraData can be summed up over all i.
        ///
        /// \see construct
        template<class Constructor>
        AtA_Atb_Add<Constructor>::Atb constructAndSolve(int n, dim3 gridDim, dim3 blockDim, Constructor::ExtraData& out_extra_sum) {
            auto result = construct<Constructor>(n, gridDim, blockDim);
            out_extra_sum = result._extraData;
            cout << result._AtA << endl;
            cout << result._Atb << endl;

            return Cholesky::solve(result._AtA, result._Atb);
        }
    }








    void approxEqual(float a, float b, const float eps = 0.00001) {
        assert(abs(a - b) < eps, "%f != %f mod %f", a, b, eps);
    }


    void approxEqual(Matrix4f a, Matrix4f b, const float eps = 0.00001) {
        for (int i = 0; i < 4 * 4; i++)
            approxEqual(a.m[i], b.m[i], eps);
    }

    void approxEqual(Matrix3f a, Matrix3f b, const float eps = 0.00001) {
        for (int i = 0; i < 3 * 3; i++)
            approxEqual(a.m[i], b.m[i], eps);
    }

    TEST(testPose) {
        Matrix3f m = createRotation(Vector3f(0, 0, 0), 0);
        Matrix3f id; id.setIdentity();
        approxEqual(m, id);

        {
            Matrix3f rot = createRotation(Vector3f(0, 0, 1), M_PI);
            Matrix3f rot_ = {
                -1, 0, 0,
                0, -1, 0,
                0, 0, 1
            };
            ITMPose pose(0, 0, 0,
                0, 0, M_PI);
            approxEqual(rot, rot_);
            approxEqual(rot, pose.GetR());
        }
    {
#define ran (rand() / (1.f * RAND_MAX))
        Vector3f axis(ran, ran, ran);
        axis = axis.normalised(); // axis must have unit length for itmPose
        float angle = rand() / (1.f * RAND_MAX);

        ITMPose pose(0, 0, 0,
            axis.x*angle, axis.y*angle, axis.z*angle);

        Matrix3f rot = createRotation(axis, angle);
        approxEqual(rot, pose.GetR());
#undef ran
    }
    }

    TEST(testMatrix) {
        // Various ways of accessing matrix elements 
        Matrix4f m;
        m.setZeros();
        // at(x,y), mxy (not myx!, i.e. both syntaxes give the column first, then the row, different from standard maths)
        m.at(1, 0) = 1;
        m.at(0, 1) = 2;

        Matrix4f n;
        n.setZeros();
        n.m10 = 1;
        n.m01 = 2;
        /* m = n =
        0 1 0 0
        2 0 0 0
        0 0 0 0
        0 0 0 0*/

        approxEqual(m, n);

        Vector4f v(1, 8, 1, 2);
        assert(m*v == Vector4f(8, 2, 0, 0));
        assert(n*v == Vector4f(8, 2, 0, 0));
    }

    // TODO test constructAndSolve
}
using namespace vecmath;




















// voxel coordinate systems [

/// Size of a voxel, usually given in meters.
/// In world space coordinates. 

#define voxelSize (Scene::getCurrentScene()->getVoxelSize()) // 0.005f
#define oneOverVoxelSize (1.0f / voxelSize)

/** @} */
/** \brief
Encodes the world-space width of the band of the truncated
signed distance transform that is actually stored
in the volume. This is again usually specified in
meters (world coordinates).
Note that thus, the resulting width in voxels is @ref mu
divided by @ref voxelSize (times two -> on both sides of the surface).
Also, a voxel storing the value 1 has world-space-distance mu from the surface.
(the stored -1 to 1 SDF values are understood as fractions of mu)

Must be greater than voxelSize -> defined automatically from voxelSize
*/
#define voxelSize_to_mu(vs) (4*vs)// TODO is this heuristic ok?
#define mu voxelSize_to_mu(voxelSize)//0.02f

/**
Size of the thin shell region for volumetric refinement-from-shading computation.
Must be smaller than mu and should be bigger than voxelSize

In world space coordinates (meters).
*/
#define t_shell (mu/2.f)// TODO is this heuristic ok?


/// In world space coordinates.
#define voxelBlockSize (voxelSize*SDF_BLOCK_SIZE)
#define oneOverVoxelBlockWorldspaceSize (1.0f / (voxelBlockSize))



/// (0,0,0) is the lower corner of the first voxel *block*, (1,1,1) its upper corner,
/// voxelBlockCoordinate (1,1,1) corresponds to (voxelBlockSize, voxelBlockSize, voxelBlockSize) in world coordinates.
#define voxelBlockCoordinates (Scene::getCurrentScene()->voxelBlockCoordinates_)

/// (0,0,0) is the lower corner of the voxel, (1,1,1) its upper corner,
/// a position corresponding to (voxelSize, voxelSize, voxelSize) in world coordinates.
/// aka "voxel-fractional-world-coordinates"
#define voxelCoordinates (Scene::getCurrentScene()->voxelCoordinates_)


// ]






















/// depth threshold for the  tracker
/// For ITMDepthTracker: ICP distance threshold for lowest resolution (later iterations use lower distances)
/// In world space squared -- TODO maybe define heuristically from voxelsize/mus
#define depthTrackerICPMaxThreshold (0.1f * 0.1f)

/// For ITMDepthTracker: ICP iteration termination threshold
#define depthTrackerTerminationThreshold 1e-3f



/** \brief
Up to @ref maxW observations per voxel are averaged.
Beyond that a sliding average is computed.
*/
#define maxW 100

/** @{ */
/** \brief
Fallback parameters: consider only parts of the
scene from @p viewFrustum_min in front of the camera
to a distance of @p viewFrustum_max (world-space distance). Usually the
actual depth range should be determined
automatically by a ITMLib::Engine::ITMVisualisationEngine.

aka.
viewRange_min depthRange
zmin zmax
*/
#define viewFrustum_min 0.2f
#define viewFrustum_max 6.0f

//////////////////////////////////////////////////////////////////////////
// Voxel Hashing definition and helper functions
//////////////////////////////////////////////////////////////////////////

// amount of voxels along one side of a voxel block
#define SDF_BLOCK_SIZE 8

// SDF_BLOCK_SIZE^3, amount of voxels in a voxel block
#define SDF_BLOCK_SIZE3 (SDF_BLOCK_SIZE * SDF_BLOCK_SIZE * SDF_BLOCK_SIZE)

// (Maximum) Number of actually stored blocks (i.e. maximum load the hash-table can actually have -- yes, we can never fill all buckets)
// is much smaller than SDF_BUCKET_NUM for efficiency reasons. 
// doesn't make sense for this to be bigger than SDF_GLOBAL_BLOCK_NUM
// localVBA's size
// memory hog if too large, main limitation for scene size
#define SDF_LOCAL_BLOCK_NUM  0x8000 //0x10000	//	0x40000

#define SDF_BUCKET_NUM 0x100000			// Number of Hash Bucket, must be 2^n and bigger than SDF_LOCAL_BLOCK_NUM
#define SDF_HASH_MASK (SDF_BUCKET_NUM-1)// Used for get hashing value of the bucket index, "x & (uint)SDF_HASH_MASK" is the same as "x % SDF_BUCKET_NUM"
#define SDF_EXCESS_LIST_SIZE 0x20000	// Size of excess list, used to handle collisions. Also max offset (unsigned short) value.

// TODO rename to SDF_TOTAL_HASH_POSITIONS
#define SDF_GLOBAL_BLOCK_NUM (SDF_BUCKET_NUM+SDF_EXCESS_LIST_SIZE)	// Number of globally stored blocks == size of ordered + unordered part of hash table































// Memory-block and 'image'/large-matrix management
namespace memory {

    enum MemoryCopyDirection { CPU_TO_CPU, CPU_TO_CUDA, CUDA_TO_CPU, CUDA_TO_CUDA };
    enum MemoryDeviceType { MEMORYDEVICE_CPU, MEMORYDEVICE_CUDA };
    enum MemoryBlockState { SYNCHRONIZED, CPU_AHEAD, GPU_AHEAD };

    void testMemblock();

    /// Pointer to block of mutable memory, consistent in GPU and CPU memory.
    /// 
    /*
    Notes:
    * always aquire pointers to the memory anew using GetData
    * when CPU memory is considered ahead, GPU memory must be updated via manual request from the host-side -- GPU cannot pull memory it needs
    * should be more efficient than CUDA managed memory (?)

    */
    template <typename T>
    struct MemoryBlock : public Managed
    {
    private:
        friend void testMemblock();
        mutable MemoryBlockState state;

        T* data_cpu;
        DEVICEPTR(T)* data_cuda;

        size_t dataSize__;
        void dataSize_(size_t dataSize) { dataSize__ = dataSize; }

    public:
        CPU_AND_GPU size_t dataSize_() const { return dataSize__; }
        __declspec(property(get = dataSize_, put = dataSize_)) size_t dataSize;

        void Allocate(size_t dataSize) {
            this->dataSize = dataSize;

            data_cpu = new T[dataSize];
            cudaMalloc((T**)&data_cuda, dataSizeInBytes());

            Clear(0);
        }

        MemoryBlock(size_t dataSize) {
            Allocate(dataSize);
            assert(SYNCHRONIZED == state);
        }

        virtual ~MemoryBlock() {
            delete[] data_cpu;
            cudaFree(data_cuda);

            // HACK DEBUGGING set state to illegal values [
            data_cpu = data_cuda = (T*)0xffffffffffffffffUI64;
            dataSize = 0xffffffffffffffffUI64;
            state = (MemoryBlockState)0xffffffff;
            // ]
        }

        void Synchronize() const {
            if (state == GPU_AHEAD) cudaMemcpy(data_cpu, data_cuda, dataSizeInBytes(), cudaMemcpyDeviceToHost);
            else if (state == CPU_AHEAD) cudaMemcpy(data_cuda, data_cpu, dataSizeInBytes(), cudaMemcpyHostToDevice);
            else assert(state == SYNCHRONIZED);
            cudaDeviceSynchronize();
            state = SYNCHRONIZED;
        }

        bool operator==(const MemoryBlock& other) const {

            auto y = memcmp(data_cpu, other.data_cpu, MIN(other.dataSizeInBytes(), dataSizeInBytes())); // DEBUG

            if (other.dataSizeInBytes() != dataSizeInBytes())
                return false;
            Synchronize();
            auto z = memcmp(data_cpu, other.data_cpu, MIN(other.dataSizeInBytes(), dataSizeInBytes())); // DEBUG

            other.Synchronize();

            auto w = memcmp(data_cpu, other.data_cpu, other.dataSizeInBytes());
            cudaDeviceSynchronize(); // memcmp fails otherwise with -1 when cuda is still running
            auto x = memcmp(data_cpu, other.data_cpu, other.dataSizeInBytes());
            assert(x == y);
            return x == 0;
        }

        void SetFrom(const MemoryBlock& copyFrom) {
            copyFrom.Synchronize();
            Allocate(copyFrom.dataSize);
            assert(this->dataSizeInBytes() == copyFrom.dataSizeInBytes());
            memcpy(data_cpu, copyFrom.data_cpu, copyFrom.dataSizeInBytes());
            state = CPU_AHEAD;
            assert(memcmp(data_cpu, copyFrom.data_cpu, copyFrom.dataSizeInBytes()) == 0);

            Synchronize();

            assert(*this == copyFrom);
            assert(SYNCHRONIZED == state);
        }

        MemoryBlock(const MemoryBlock& copyFrom) {
            SetFrom(copyFrom);
            assert(SYNCHRONIZED == state);
        }

        SERIALIZE_VERSION(1);
        void serialize(ofstream& file) {
            Synchronize();
            auto p = file.tellp(); // DEBUG

            SERIALIZE_WRITE_VERSION(file);
            bin(file, dataSize);
            bin(file, (size_t)sizeof(T));
            file.write((const char*)data_cpu, dataSizeInBytes());

            assert(file.tellp() - p == sizeof(int) + sizeof(size_t) * 2 + dataSizeInBytes(), "%I64d != %I64d",
                file.tellp() - p,
                sizeof(int) + sizeof(size_t) * 2 + dataSizeInBytes());
        }

        void SetFrom(char* data, size_t dataSize) {
            Allocate(dataSize);
            memcpy((char*)data_cpu, data, dataSizeInBytes());
            state = CPU_AHEAD;
            Synchronize();
        }

        // loses current data
        void deserialize(ifstream& file) {
            SERIALIZE_READ_VERSION(file);

            Allocate(bin<size_t>(file));
            assert(bin<size_t>(file) == sizeof(T));

            file.read((char*)data_cpu, dataSizeInBytes());
            state = CPU_AHEAD;
            Synchronize();
        }

        CPU_AND_GPU size_t dataSizeInBytes() const {
            return dataSize * sizeof(T);
        }

        /** Get the data pointer on CPU or GPU. */
        CPU_AND_GPU DEVICEPTR(T)* const GetData(MemoryDeviceType memoryType)
        {
            switch (memoryType)
            {
#if !GPU_CODE
            case MEMORYDEVICE_CPU:
                Synchronize();
                state = CPU_AHEAD;
                return data_cpu;
#endif
            case MEMORYDEVICE_CUDA:
#if !GPU_CODE
                Synchronize();
#endif
                assert(state != CPU_AHEAD);
                state = GPU_AHEAD;
                return data_cuda;
            }
            fatalError("error on GetData: unknown memory type %d", memoryType);
            return 0;
        }

        CPU_AND_GPU const DEVICEPTR(T)* const GetData(MemoryDeviceType memoryType) const
        {
            switch (memoryType)
            {
#if !GPU_CODE
            case MEMORYDEVICE_CPU:
                Synchronize();
                return data_cpu;
#endif
            case MEMORYDEVICE_CUDA:
#if !GPU_CODE
                Synchronize();
#endif
                assert(state == SYNCHRONIZED);
                return data_cuda;
            }
            fatalError("error on const GetData: unknown memory type %d", memoryType);
            return 0;
        }


#ifdef __CUDA_ARCH__
        /** Get the data pointer on CPU or GPU. */
        GPU_ONLY DEVICEPTR(T)* GetData() { return GetData(MEMORYDEVICE_CUDA); }
        GPU_ONLY const DEVICEPTR(T)* GetData() const { return GetData(MEMORYDEVICE_CUDA); }
#else
        inline T* GetData() { return GetData(MEMORYDEVICE_CPU); }
        inline const T* GetData() const { return GetData(MEMORYDEVICE_CPU); }
#endif

        // convenience & bounds checking
        CPU_AND_GPU /*possibly DEVICEPTR */ DEVICEPTR(T&) operator[] (unsigned int i) {
            assert(i < dataSize, "%d >= %d -- MemoryBlock access out of range", i, dataSize);
            return GetData()[i];
        }

        /** Set all data to the byte given by @p defaultValue. */
        void Clear(unsigned char defaultValue = 0)
        {
            memset(data_cpu, defaultValue, dataSizeInBytes());
            cudaMemset(data_cuda, defaultValue, dataSizeInBytes());
            state = SYNCHRONIZED;
        }
    };

    __managed__ int* data;
    KERNEL set_data() {
        data[1] = 42;
    }
    KERNEL check_data() {
        assert(data[1] == 42);
    }

    TEST(testMemblock) {
        cudaDeviceSynchronize();
        auto mem = new MemoryBlock<int>(10);
        assert(mem->dataSize == 10);
        assert(mem->state == SYNCHRONIZED);

        mem->GetData(MEMORYDEVICE_CPU);
        assert(mem->state == CPU_AHEAD);

        mem->GetData(MEMORYDEVICE_CUDA);
        assert(mem->state == GPU_AHEAD);

        mem->Clear(0);
        assert(mem->state == SYNCHRONIZED);

        auto const* const cmem = mem;
        cmem->GetData(MEMORYDEVICE_CPU);
        assert(mem->state == SYNCHRONIZED);
        cmem->GetData(MEMORYDEVICE_CUDA);
        assert(mem->state == SYNCHRONIZED);

        mem->GetData()[1] = 42;
        assert(mem->state == CPU_AHEAD);
        data = mem->GetData(MEMORYDEVICE_CUDA);
        assert(mem->state == GPU_AHEAD);
        LAUNCH_KERNEL(check_data, 1, 1);
        cudaDeviceSynchronize();

        mem->Clear(0);

        // NOTE wrongly assumes that everything is still clean because we *reused the pointer* (data) instead of claiming it again
        // consequently, memory will not be equal, but state will still say SYNCHRONIZED!
        LAUNCH_KERNEL(set_data, 1, 1);
        cudaDeviceSynchronize();
        assert(mem->state == SYNCHRONIZED);
        LAUNCH_KERNEL(check_data, 1, 1);
        cudaDeviceSynchronize();
        assert(mem->GetData()[1] == 0);

        // re-requesting fixes the problem and syncs the buffers again
        mem->Clear(0);
        data = mem->GetData(MEMORYDEVICE_CUDA);
        LAUNCH_KERNEL(set_data, 1, 1);
        LAUNCH_KERNEL(check_data, 1, 1);
        cudaDeviceSynchronize();
        assert(mem->GetData()[1] == 42);
    }

#define GPUCHECK(p, val) LAUNCH_KERNEL(check,1,1,(char* )p,val);
    KERNEL check(char* p, char val) {
        assert(*p == val);
    }

    TEST(testMemoryBlockSerialize) {
        MemoryBlock<int> b(1);
        b[0] = 0xbadf00d;
        GPUCHECK(b.GetData(MEMORYDEVICE_CUDA), 0x0d);
        BEGIN_SHOULD_FAIL();
        GPUCHECK(b.GetData(MEMORYDEVICE_CUDA), 0xba);
        END_SHOULD_FAIL();

        auto fn = "o.bin";
        {
            b.serialize(binopen_write(fn));
        }

    {
        b.deserialize(binopen_read(fn));
    }
    assert(b[0] == 0xbadf00d);
    assert(b.dataSize == 1);

    b.Clear();

    {
        b.deserialize(binopen_read(fn));
    }
    assert(b[0] == 0xbadf00d);
    GPUCHECK(b.GetData(MEMORYDEVICE_CUDA), 0x0d);
    assert(b.dataSize == 1);


    MemoryBlock<int> c(100);
    assert(c.dataSize == 100);
    GPUCHECK(c.GetData(MEMORYDEVICE_CUDA), 0);

    {
        c.deserialize(binopen_read(fn));
    }
    assert(c[0] == 0xbadf00d);
    assert(c.dataSize == 1);
    GPUCHECK(c.GetData(MEMORYDEVICE_CUDA), 0x0d);

    }

    TEST(testMemoryBlockCopyCompare) {
        MemoryBlock<int> ma(100);
        MemoryBlock<int> mb(100);
        MemoryBlock<int> mc(90);

        assert(mb == mb);
        assert(mb == ma);
        ma.Clear(1);
        assert(!(mb == ma));
        assert(!(mb == mc));
        assert(!(mb == ma));

        MemoryBlock<int> md(ma);
        assert(ma == md);
    }












    /** \brief
    Represents images, templated on the pixel type

    Managed
    */
    template <typename T>
    class Image : public MemoryBlock < T >
    {
    public:
        /** Size of the image in pixels. */
        Vector2<int> noDims;

        /** Initialize an empty image of the given size
        */
        Image(Vector2<int> noDims = Vector2<int>(1, 1)) : MemoryBlock<T>(noDims.area()), noDims(noDims) {}

        void EnsureDims(Vector2<int> noDims) {
            if (this->noDims == noDims) return;
            this->noDims = noDims;
            Allocate(noDims.area());
        }

    };


#define ITMFloatImage Image<float>
#define ITMFloat2Image Image<Vector2f>
#define ITMFloat4Image Image<Vector4f>
#define ITMShortImage Image<short>
#define ITMShort3Image Image<Vector3s>
#define ITMShort4Image Image<Vector4s>
#define ITMUShortImage Image<ushort>
#define ITMUIntImage Image<uint>
#define ITMIntImage Image<int>
#define ITMUCharImage Image<uchar>
#define ITMUChar4Image Image<Vector4u>
#define ITMBoolImage Image<bool>


}
using namespace memory;








































// Camera calibration parameters, used to convert pixel coordinates to camera coordinates/rays
class ITMIntrinsics
{
public:
    CPU_AND_GPU ITMIntrinsics(void)
    {
        // standard calibration parameters for Kinect RGB camera. Not accurate
        fx = 580;
        fy = 580;
        px = 320;
        py = 240;
        sizeX = 640;
        sizeY = 480;
    }

    __declspec(property(get = all_, put = all_)) Vector4f all;

    CPU_AND_GPU Vector4f all_() const {
        return Vector4f(fx, fy, px, py);
    }

    void all_(Vector4f v) {
        fx = v.x;
        fy = v.y;
        px = v.z;
        py = v.w;
    }

    union {
        struct {
            float fx, fy, px, py;
        };

        struct {
            float focalLength[2], centerPoint[2];
        };
    };
    uint sizeX, sizeY;

    CPU_AND_GPU Vector2i imageSize() const {
        return Vector2i(sizeX, sizeY);
    }

    void imageSize(Vector2i size) {
        sizeX = size.x;
        sizeY = size.y;
    }
};

/** \brief
Represents the extrinsic calibration between RGB and depth
cameras, i.e. the conversion from RGB camera-coordinates to depth-camera-coordinates and back

TODO use Coordinates class
*/
class ITMExtrinsics
{
public:
    /** The transformation matrix representing the
    extrinsic calibration data.
    */
    Matrix4f calib;
    /** Inverse of the above. */
    Matrix4f calib_inv;

    /** Setup from a given 4x4 matrix, where only the upper
    three rows are used. More specifically, m00...m22
    are expected to contain a rotation and m30...m32
    contain the translation.
    */
    void SetFrom(const Matrix4f & src)
    {
        this->calib = src;
        this->calib_inv.setIdentity();
        for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c) this->calib_inv.m[r + 4 * c] = this->calib.m[c + 4 * r];
        for (int r = 0; r < 3; ++r) {
            float & dest = this->calib_inv.m[r + 4 * 3];
            dest = 0.0f;
            for (int c = 0; c < 3; ++c) dest -= this->calib.m[c + 4 * r] * this->calib.m[c + 4 * 3];
        }
    }

    ITMExtrinsics()
    {
        Matrix4f m;
        m.setZeros();
        m.m00 = m.m11 = m.m22 = m.m33 = 1.0;
        SetFrom(m);
    }
};

/** \brief
Represents the joint RGBD calibration parameters.
*/
class ITMRGBDCalib
{
public:
    ITMIntrinsics intrinsics_rgb;
    ITMIntrinsics intrinsics_d;

    /** @brief
    M_d * worldPoint = trafo_rgb_to_depth.calib * M_rgb * worldPoint

    M_rgb * worldPoint = trafo_rgb_to_depth.calib_inv * M_d * worldPoint
    */
    ITMExtrinsics trafo_rgb_to_depth;
};



































template<typename T>
struct IllegalColor {
    static CPU_AND_GPU T make();
};
inline CPU_AND_GPU float IllegalColor<float>::make() {
    return -1;
}
inline CPU_AND_GPU Vector4f IllegalColor<Vector4f>::make() {
    return Vector4f(0, 0, 0, -1);
}
inline CPU_AND_GPU bool isLegalColor(float c) {
    return c >= 0;
}
inline CPU_AND_GPU bool isLegalColor(Vector4f c) {
    return c.w >= 0;
}
inline CPU_AND_GPU bool isLegalColor(Vector4u c) {
    // NOTE this should never be called -- withHoles should be false for a Vector4u
    // implementing this just calms the compiler
    fatalError("isLegalColor is not implemented for Vector4u");
    return false;
}

























// Local/per pixel Image processing library


/// Linearized pixel index
CPU_AND_GPU inline int pixelLocId(const int x, const int y, const Vector2i &imgSize) {
    return x + y * imgSize.x;
}

/// Sample image without interpolation at integer location
template<typename T> CPU_AND_GPU
inline T sampleNearest(
const T *source,
int x, int y,
const Vector2i & imgSize)
{
    return source[pixelLocId(x, y, imgSize)];
}

/// Sample image without interpolation at rounded location
template<typename T> CPU_AND_GPU
inline T sampleNearest(
const T *source,
const Vector2f & pt_image,
const Vector2i & imgSize) {
    return source[
        pixelLocId(
            (int)(pt_image.x + 0.5f),
            (int)(pt_image.y + 0.5f),
            imgSize)];
}

/// Whether interpolation should return an illegal color when holes make interpolation impossible
#define WITH_HOLES true
/// Sample 4 channel image with bilinear interpolation (T_IN::toFloat must return Vector4f)
/// IF withHoles == WITH_HOLES: returns makeIllegalColor<OUT>() when any of the four surrounding pixels is illegal (has negative w).
template<typename T_OUT, //!< Vector4f or float
    bool withHoles = false, typename T_IN> CPU_AND_GPU inline Vector4f interpolateBilinear(
    const T_IN * const source,
    const Vector2f & position, const Vector2i & imgSize)
{
    T_OUT result;
    Vector2i p; Vector2f delta;

    p.x = (int)floor(position.x); p.y = (int)floor(position.y);
    delta.x = position.x - p.x; delta.y = position.y - p.y;

#define sample(dx, dy) sampleNearest(source, p.x + dx, p.y + dy, imgSize);
    T_IN a = sample(0, 0);
    T_IN b = sample(1, 0);
    T_IN c = sample(0, 1);
    T_IN d = sample(1, 1);
#undef sample

    if (withHoles && (!isLegalColor(a) || !isLegalColor(b) || !isLegalColor(c) || !isLegalColor(d))) return IllegalColor<T_OUT>::make();

    /**
    ------> dx
    | a b
    | c d
    dy
    \/
    */
    result =
        toFloat(a) * (1.0f - delta.x) * (1.0f - delta.y) +
        toFloat(b) * delta.x * (1.0f - delta.y) +
        toFloat(c) * (1.0f - delta.x) * delta.y +
        toFloat(d) * delta.x * delta.y;

    return result;
}


// === forEachPixelNoImage ===
template<typename F>
static KERNEL forEachPixelNoImage_device(Vector2i imgSize) {
    const int
        x = threadIdx.x + blockIdx.x * blockDim.x,
        y = threadIdx.y + blockIdx.y * blockDim.y;

    if (x > imgSize.x - 1 || y > imgSize.y - 1) return;
    const int locId = pixelLocId(x, y, imgSize);

    F::process(x, y, locId);
}

#define forEachPixelNoImage_process() GPU_ONLY static void process(const int x, const int y, const int locId)
/** apply
F::process(int x, int y, int locId)
to each (hypothetical) pixel in the image

locId runs through values generated by pixelLocId(x, y, imgSize);
*/
template<typename F>
static void forEachPixelNoImage(Vector2i imgSize) {
    const dim3 blockSize(16, 16);
    LAUNCH_KERNEL(
        forEachPixelNoImage_device<F>,
        getGridSize(dim3(xy(imgSize)), blockSize),
        blockSize,
        imgSize);
}















namespace TestForEachPixel {
    const int W = 5;
    const int H = 7;
    __managed__ int fipcounter = 0;
    struct DoForEachPixel {
        forEachPixelNoImage_process() {
            assert(x >= 0 && x < W);
            assert(y >= 0 && y < H);
            atomicAdd(&fipcounter, 1);
        }
    };

    TEST(testForEachPixelNoImage) {
        fipcounter = 0;
        forEachPixelNoImage<DoForEachPixel>(Vector2i(W, H));
        cudaDeviceSynchronize();
        assert(fipcounter == W * H);
    }

}








































template<bool withHoles = false, typename T>
CPU_AND_GPU inline void filterSubsample(
    DEVICEPTR(T) *imageData_out, int x, int y, Vector2i newDims,
    const T *imageData_in, Vector2i oldDims)
{
    int src_pos_x = x * 2, src_pos_y = y * 2;
    T pixel_out = 0.0f, pixel_in;
    float no_good_pixels = 0.0f;

#define sample(dx,dy) \
    pixel_in = imageData_in[(src_pos_x + dx) + (src_pos_y + dy) * oldDims.x]; \
	if (!withHoles || isLegalColor(pixel_in)) { pixel_out += pixel_in; no_good_pixels++; }

    sample(0, 0);
    sample(1, 0);
    sample(0, 1);
    sample(1, 1);
#undef sample

    if (no_good_pixels > 0) pixel_out /= no_good_pixels;
    else if (withHoles) pixel_out = IllegalColor<T>::make();

    imageData_out[pixelLocId(x, y, newDims)] = pixel_out;
}

// device functions
#define FILTER(FILTERNAME)\
template<bool withHoles, typename T>\
static KERNEL FILTERNAME ## _device(T *imageData_out, Vector2i newDims, const T *imageData_in, Vector2i oldDims) {\
    int x = threadIdx.x + blockIdx.x * blockDim.x, y = threadIdx.y + blockIdx.y * blockDim.y;\
    if (x > newDims.x - 1 || y > newDims.y - 1) return;\
    FILTERNAME<withHoles>(imageData_out, x, y, newDims, imageData_in, oldDims);\
}

FILTER(filterSubsample)



// host methods
#define FILTERMETHOD(METHODNAME, WITHHOLES)\
            template<typename T>\
                void METHODNAME (Image<T> *image_out, const Image<T> *image_in) {\
                    Vector2i oldDims = image_in->noDims; \
                    Vector2i newDims; newDims.x = image_in->noDims.x / 2; newDims.y = image_in->noDims.y / 2; \
                    \
                    image_out->EnsureDims(newDims); \
                    \
                    const T *imageData_in = image_in->GetData(MEMORYDEVICE_CUDA); \
                    T *imageData_out = image_out->GetData(MEMORYDEVICE_CUDA); \
                    \
                    dim3 blockSize(16, 16); \
                    dim3 gridSize((int)ceil((float)newDims.x / (float)blockSize.x), (int)ceil((float)newDims.y / (float)blockSize.y)); \
                    \
                    LAUNCH_KERNEL(filterSubsample_device<WITHHOLES>, gridSize, blockSize,\
imageData_out, newDims, imageData_in, oldDims); \
            }

FILTERMETHOD(FilterSubsample, false)
FILTERMETHOD(FilterSubsampleWithHoles, WITH_HOLES)






























// Pinhole-camera computations, c.f. RayImage, DepthImage in coordinates::

/// Computes a position in camera space given a 2d image coordinate and a depth.
/// \f$ z K^{-1}u\f$
/// \param x,y \f$ u\f$
CPU_AND_GPU inline Vector4f depthTo3D(
const Vector4f & viewIntrinsics, //!< K
const int & x, const int & y,
const float &depth //!< z
) {
    /// Note: division by projection parameters .x, .y, i.e. fx and fy.
    /// The function below takes <inverse projection parameters> which have 1/fx, 1/fy, cx, cy
    Vector4f o;
    o.x = depth * ((float(x) - viewIntrinsics.z) / viewIntrinsics.x);
    o.y = depth * ((float(y) - viewIntrinsics.w) / viewIntrinsics.y);
    o.z = depth;
    o.w = 1.0f;
    return o;
}


CPU_AND_GPU inline bool projectNoBounds(
    Vector4f projParams, Vector4f pt_camera, Vector2f& pt_image) {
    if (pt_camera.z <= 0) return false;

    pt_image.x = projParams.x * pt_camera.x / pt_camera.z + projParams.z;
    pt_image.y = projParams.y * pt_camera.y / pt_camera.z + projParams.w;

    return true;
}

/// $$\\pi(K p)$$
/// Projects pt_model, given in camera coordinates to 2d image coordinates (dropping depth).
/// \returns false when point projects outside of image
CPU_AND_GPU inline bool project(
    Vector4f projParams, //!< K 
    const Vector2i & imgSize,
    Vector4f pt_camera, //!< p
    Vector2f& pt_image) {
    if (!projectNoBounds(projParams, pt_camera, pt_image)) return false;

    if (pt_image.x < 0 || pt_image.x > imgSize.x - 1 || pt_image.y < 0 || pt_image.y > imgSize.y - 1) return false;
    // for inner points, when we compute gradients
    // was used like that in computeUpdatedVoxelDepthInfo
    //if ((pt_image.x < 1) || (pt_image.x > imgSize.x - 2) || (pt_image.y < 1) || (pt_image.y > imgSize.y - 2)) return -1;

    return true;
}

/// Reject pixels on the right lower boundary of the image 
// (which have an incomplete forward-neighborhood)
CPU_AND_GPU inline bool projectExtraBounds(
    Vector4f projParams, const Vector2i & imgSize,
    Vector4f pt_camera, Vector2f& pt_image) {
    if (!projectNoBounds(projParams, pt_camera, pt_image)) return false;

    if (pt_image.x < 0 || pt_image.x > imgSize.x - 2 || pt_image.y < 0 || pt_image.y > imgSize.y - 2) return false;

    return true;
}









// Concept of a rectilinear, aribtrarily rotated and scaled coordinate system
// we use the following rigid coordinate systems: 
// world, camera (depth and color), voxel, voxel-block coordinates
// all these coordinates cover the whole world and are interconvertible by homogeneous matrix multiplication
// in these spaces, we refer to points and rays

namespace coordinates {


    class Point;
    class Vector;
    class Ray;
    class CoordinateSystem;

    /// Coordinate systems live in managed memory and are identical when their pointers are.
    __managed__ CoordinateSystem* globalcs = 0;
    class CoordinateSystem : public Managed {
    private:
        //CoordinateSystem(const CoordinateSystem&); // TODO should we really allow copying?
        void operator=(const CoordinateSystem&);

        CPU_AND_GPU Point toGlobalPoint(Point p)const;
        CPU_AND_GPU Point fromGlobalPoint(Point p)const;
        CPU_AND_GPU Vector toGlobalVector(Vector p)const;
        CPU_AND_GPU Vector fromGlobalVector(Vector p)const;
    public:
        const Matrix4f toGlobal;
        const Matrix4f fromGlobal;
        explicit CoordinateSystem(const Matrix4f& toGlobal) : toGlobal(toGlobal), fromGlobal(toGlobal.getInv()) {
            assert(toGlobal.GetR().det() != 0);
        }

        /// The world or global space coodinate system.
        /// Measured in meters if cameras and depth computation are calibrated correctly.
        CPU_AND_GPU static CoordinateSystem* global() {

            if (!globalcs) {
#if GPU_CODE
                fatalError("Global coordinate system does not yet exist. It cannot be instantiated on the GPU. Aborting.");
#else
                Matrix4f m;
                m.setIdentity();
                globalcs = new CoordinateSystem(m);
#endif
            }

            assert(globalcs);
            return globalcs;
        }

        CPU_AND_GPU Point convert(Point p)const;
        CPU_AND_GPU Vector convert(Vector p)const;
        CPU_AND_GPU Ray convert(Ray p)const;
    };

    // Represents anything that lives in some coordinate system.
    // Entries are considered equal only when they have the same coordinates.
    // They are comparable only if in the same coordinate system.
    class CoordinateEntry {
    public:
        const CoordinateSystem* coordinateSystem;
        friend CoordinateSystem;
        CPU_AND_GPU CoordinateEntry(const CoordinateSystem* coordinateSystem) : coordinateSystem(coordinateSystem) {}
    };

    // an origin-less direction in some coordinate system
    // not affected by translations
    // might represent a surface normal (if normalized) or the direction from one point to another
    class Vector : public CoordinateEntry {
    private:
        friend Point;
        friend CoordinateSystem;
    public:
        const Vector3f direction;
        // copy constructor ok
        // assignment will not be possible

        CPU_AND_GPU explicit Vector(const CoordinateSystem* coordinateSystem, Vector3f direction) : CoordinateEntry(coordinateSystem), direction(direction) {
        }
        CPU_AND_GPU bool operator==(const Vector& rhs) const {
            assert(coordinateSystem == rhs.coordinateSystem);
            return direction == rhs.direction;
        }
        CPU_AND_GPU Vector operator*(const float rhs) const {
            return Vector(coordinateSystem, direction * rhs);
        }
        CPU_AND_GPU float dot(const Vector& rhs) const {
            assert(coordinateSystem == rhs.coordinateSystem);
            return ::dot(direction, rhs.direction);
        }
        CPU_AND_GPU Vector operator-(const Vector& rhs) const {
            assert(coordinateSystem == rhs.coordinateSystem);
            return Vector(coordinateSystem, direction - rhs.direction);
        }
    };

    class Point : public CoordinateEntry {
    private:
        friend CoordinateSystem;
    public:
        const Vector3f location;
        // copy constructor ok

        // Assignment // TODO instead of allowing assignment, rendering Points mutable (!)
        // use a changing reference-to-a-Point instead (a pointer for example)
        CPU_AND_GPU void operator=(const Point& rhs) {
            coordinateSystem = rhs.coordinateSystem;
            const_cast<Vector3f&>(location) = rhs.location;
        }

        CPU_AND_GPU explicit Point(const CoordinateSystem* coordinateSystem, Vector3f location) : CoordinateEntry(coordinateSystem), location(location) {
        }
        CPU_AND_GPU bool operator==(const Point& rhs) const {
            assert(coordinateSystem == rhs.coordinateSystem);
            return location == rhs.location;
        }
        CPU_AND_GPU Point operator+(const Vector& rhs) const {
            assert(coordinateSystem == rhs.coordinateSystem);
            return Point(coordinateSystem, location + rhs.direction);
        }

        /// Gives a vector that points from rhs to this.
        /// Think 'the location of this as seen from rhs' or 'how to get to this coordinate given one already got to rhs' ('how much energy do we still need to invest in each direction)
        CPU_AND_GPU Vector operator-(const Point& rhs) const {
            assert(coordinateSystem == rhs.coordinateSystem);
            return Vector(coordinateSystem, location - rhs.location);
        }
    };

    /// Oriented line segment
    // TODO does this allow scaling or not?
    class Ray {
    public:
        const Point origin;
        const Vector direction;

        CPU_AND_GPU Ray(Point& origin, Vector& direction) : origin(origin), direction(direction) {
            assert(origin.coordinateSystem == direction.coordinateSystem);
        }
        CPU_AND_GPU Point endpoint() {
            Point p = origin + direction;
            assert(p.coordinateSystem == origin.coordinateSystem);
            return p;
        }
    };


    inline CPU_AND_GPU Point CoordinateSystem::toGlobalPoint(Point p) const {
        return Point(global(), Vector3f(this->toGlobal * Vector4f(p.location, 1)));
    }
    inline CPU_AND_GPU Point CoordinateSystem::fromGlobalPoint(Point p) const {
        assert(p.coordinateSystem == global());
        return Point(this, Vector3f(this->fromGlobal * Vector4f(p.location, 1)));
    }
    inline CPU_AND_GPU Vector CoordinateSystem::toGlobalVector(Vector v) const {
        return Vector(global(), this->toGlobal.GetR() *v.direction);
    }
    inline CPU_AND_GPU Vector CoordinateSystem::fromGlobalVector(Vector v) const {
        assert(v.coordinateSystem == global());
        return Vector(this, this->fromGlobal.GetR() *v.direction);
    }
    inline CPU_AND_GPU Point CoordinateSystem::convert(Point p) const {
        Point o = this->fromGlobalPoint(p.coordinateSystem->toGlobalPoint(p));
        assert(o.coordinateSystem == this);
        return o;
    }
    inline CPU_AND_GPU Vector CoordinateSystem::convert(Vector p) const {
        Vector o = this->fromGlobalVector(p.coordinateSystem->toGlobalVector(p));
        assert(o.coordinateSystem == this);
        return o;
    }
    inline CPU_AND_GPU Ray CoordinateSystem::convert(Ray p) const {
        return Ray(convert(p.origin), convert(p.direction));
    }


    void initCoordinateSystems() {
        CoordinateSystem::global(); // access to make sure it exists

    }


}
using namespace coordinates;










/// Base class storing a camera calibration, eye coordinate system and an image taken with a camera thusly calibrated.
/// Given correct calibration and no scaling, the resulting points are in world-scale, i.e. meter units.
template<typename T>
class CameraImage : public Managed {
private:
    void operator=(const CameraImage& ci);
    CameraImage(const CameraImage&);
public:
    Image<T>*const image; // TODO should the image have to be const?
    const CoordinateSystem* eyeCoordinates; // const ITMPose* const pose // pose->GetM is fromGlobal matrix of coord system; <- inverse is toGlobal // TODO should this encapsulate a copy? // TODO should the eyeCoordinates have to be const?
    const ITMIntrinsics cameraIntrinsics;// const ITMIntrinsics* const cameraIntrinsics;

    CameraImage(
        Image<T>*const image,
        const CoordinateSystem* const eyeCoordinates,
        const ITMIntrinsics cameraIntrinsics) :
        image(image), eyeCoordinates(eyeCoordinates), cameraIntrinsics(cameraIntrinsics) {
        //assert(image->noDims.area() > 1); // don't force this, the image we reference is allowed to change later on
    }

    CPU_AND_GPU Vector2i imgSize()const {
        return image->noDims;
    }

    CPU_AND_GPU Vector4f projParams() const {
        return cameraIntrinsics.all;
    }
    /// 0,0,0 in eyeCoordinates
    CPU_AND_GPU Point location() const {
        return Point(eyeCoordinates, Vector3f(0, 0, 0));
    }

    /// Returns a ray starting at the camera origin and passing through the virtual camera plane
    /// pixel coordinates must be valid with regards to image size
    CPU_AND_GPU Ray getRayThroughPixel(Vector2i pixel, float depth) const {
        assert(pixel.x >= 0 && pixel.x < image->noDims.width); // imgSize(). causes 1>J:/Masterarbeit/Implementation/InfiniTAM5/main.cu(4691): error : expected a field name -- compiler error?
        assert(pixel.y >= 0 && pixel.y < image->noDims.height);   
        Vector4f f = depthTo3D(projParams(), pixel.x, pixel.y, depth);
        assert(f.z == depth);
        return Ray(location(), Vector(eyeCoordinates, f.toVector3()));
    }
#define EXTRA_BOUNDS true
    /// \see project
    /// If extraBounds = EXTRA_BOUNDS is specified, the point is considered to lie outside of the image
    /// if it cannot later be interpolated (the outer bounds are shrinked by one pixel)
    // TODO in a 2x2 image, any point in [0,2]^2 can be given a meaningful, bilinearly interpolated color...
    // did I maybe mean more complex derivatives, for normals?
    /// \returns false when point projects outside of virtual image plane
    CPU_AND_GPU bool project(Point p, Vector2f& pt_image, bool extraBounds = false) const {
        Point p_ec = eyeCoordinates->convert(p);
        assert(p_ec.coordinateSystem == eyeCoordinates);
        if (extraBounds)
            return ::projectExtraBounds(projParams(), imgSize(), Vector4f(p_ec.location, 1.f), pt_image);
        else
            return ::project(projParams(), imgSize(), Vector4f(p_ec.location, 1.f), pt_image);
    }
};

/// Constructs getRayThroughPixel endpoints for depths specified in an image.
class DepthImage : public CameraImage<float> {
public:
    DepthImage(
        Image<float>*const image,
        const CoordinateSystem* const eyeCoordinates,
        const ITMIntrinsics cameraIntrinsics) :
        CameraImage(image, eyeCoordinates, cameraIntrinsics) {}

    CPU_AND_GPU Point getPointForPixel(Vector2i pixel) const {
        float depth = sampleNearest(image->GetData(), pixel.x, pixel.y, imgSize());
        Ray r = getRayThroughPixel(pixel, depth);
        Point p = r.endpoint();
        assert(p.coordinateSystem == eyeCoordinates);
        return p;
    }
};

/// Treats a raster of locations (x,y,z,1) \in Vector4f as points specified in pointCoordinates.
/// The data may have holes, undefined data, which must be Vector4f IllegalColor<Vector4f>::make() (0,0,0,-1 /*only w is checked*/)
///
/// The assumption is that the location in image[x,y] was recorded by
/// intersecting a ray through pixel (x,y) of this camera with something.
/// Thus, the corresponding point lies in the extension of the ray-for-pixel, but possibly in another coordinate system.
///
/// The coordinate system 'pointCoordinates' does not have to be the same as eyeCoordinates, it might be 
/// global() coordinates.
/// getPointForPixel will return a point in pointCoordinates with .location as specified in the image.
///
/// Note: This is a lot different from the depth image, where the assumption is always that the depths are 
/// the z component in eyeCoordinates. Here, the coordinate system of the data in the image (pointCoordinates) can be anything.
///
/// We use this to store intersection points (in world coordinates) obtained by raytracing from a certain camera location.
class PointImage : public CameraImage<Vector4f> {
public:
    PointImage(
        Image<Vector4f>*const image,
        const CoordinateSystem* const pointCoordinates,

        const CoordinateSystem* const eyeCoordinates,
        const ITMIntrinsics cameraIntrinsics) :
        CameraImage(image, eyeCoordinates, cameraIntrinsics), pointCoordinates(pointCoordinates) {}

    const CoordinateSystem* const pointCoordinates;

    CPU_AND_GPU Point getPointForPixel(Vector2i pixel) const {
        return Point(pointCoordinates, sampleNearest(image->GetData(), pixel.x, pixel.y, imgSize()).toVector3());
    }

    /// Uses bilinear interpolation to deduce points between raster locations.
    /// out_isIllegal is set to true or false depending on whether the given point falls in a 'hole' (undefined/missing data) in the image
    CPU_AND_GPU Point getPointForPixelInterpolated(Vector2f pixel, bool& out_isIllegal) const {
        out_isIllegal = false;
        // TODO should this always consider holes?
        auto point = interpolateBilinear<Vector4f, WITH_HOLES>(
            image->GetData(),
            pixel,
            imgSize());
        if (!isLegalColor(point)) out_isIllegal = true;
        // TODO handle holes
        return Point(pointCoordinates, point.toVector3());
    }
};

/// Treats a raster of locations and normals as rays, specified in pointCoordinates.
/// Pixel (x,y) is associated to the ray startin at pointImage[x,y] into the direction normalImage[x,y],
/// where both coordinates are taken to be pointCoordinates.
///
/// This data is generated from intersecting rays with a surface.
class RayImage : public PointImage {
public:
    RayImage(
        Image<Vector4f>*const pointImage,
        Image<Vector4f>*const normalImage,
        const CoordinateSystem* const pointCoordinates,

        const CoordinateSystem* const eyeCoordinates,
        const ITMIntrinsics cameraIntrinsics) :
        PointImage(pointImage, pointCoordinates, eyeCoordinates, cameraIntrinsics), normalImage(normalImage) {
        assert(normalImage->noDims == pointImage->noDims);
    }
    Image<Vector4f>* const normalImage; // Image may change

    CPU_AND_GPU Ray getRayForPixel(Vector2i pixel) const {
        Point origin = getPointForPixel(pixel);
        auto direction = sampleNearest(normalImage->GetData(), pixel.x, pixel.y, imgSize()).toVector3();
        return Ray(origin, Vector(pointCoordinates, direction));
    }

    /// pixel should have been produced with
    /// project(x,pixel,EXTRA_BOUNDS)
    CPU_AND_GPU Ray getRayForPixelInterpolated(Vector2f pixel, bool& out_isIllegal) const {
        out_isIllegal = false;
        Point origin = getPointForPixelInterpolated(pixel, out_isIllegal);
        // TODO should this always consider holes?
        auto direction = interpolateBilinear<Vector4f, WITH_HOLES>(
            normalImage->GetData(),
            pixel,
            imgSize());
        if (!isLegalColor(direction)) out_isIllegal = true;
        // TODO handle holes
        return Ray(origin, Vector(pointCoordinates, direction.toVector3()));
    }
};
























CPU_AND_GPU void testCS(CoordinateSystem* o) {
    auto g = CoordinateSystem::global();
    assert(g);

    Point a = Point(o, Vector3f(0.5, 0.5, 0.5));
    assert(a.coordinateSystem == o);
    Point b = g->convert(a);
    assert(b.coordinateSystem == g);
    assert(!(b == Point(g, Vector3f(1, 1, 1))));
    assert((b == Point(g, Vector3f(0.25, 0.25, 0.25))));

    // Thus:
    Point c = o->convert(Point(g, Vector3f(1, 1, 1)));
    assert(c.coordinateSystem == o);
    assert(!(c == Point(o, Vector3f(1, 1, 1))));
    assert((c == Point(o, Vector3f(2, 2, 2))));

    Point d = o->convert(c);
    assert(c == d);

    Point e = o->convert(g->convert(c));
    assert(c == e);
    assert(g->convert(c) == Point(g, Vector3f(1, 1, 1)));

    Point f = o->convert(g->convert(o->convert(c)));
    assert(c == f);

    // +
    Point q = Point(g, Vector3f(1, 1, 2)) + Vector(g, Vector3f(1, 1, 0));
    assert(q.location == Vector3f(2, 2, 2));

    // -
    {
        Vector t = Point(g, Vector3f(0, 0, 0)) - Point(g, Vector3f(1, 1, 2));
        assert(t.direction == Vector3f(-1, -1, -2));
    }

    {
        Vector t = Vector(g, Vector3f(0, 0, 0)) - Vector(g, Vector3f(1, 1, 2));
        assert(t.direction == Vector3f(-1, -1, -2));
    }

    // * scalar
    {
        Vector t = Vector(g, Vector3f(1, 1, 2)) * (-1);
        assert(t.direction == Vector3f(-1, -1, -2));
    }

    // dot (angle if the coordinate system is orthogonal and the vectors unit)
    assert(Vector(o, Vector3f(1, 2, 3)).dot(Vector(o, Vector3f(3, 2, 1))) == 1 * 3 + 2 * 2 + 1 * 3);
}

KERNEL ktestCS(CoordinateSystem* o) {
    testCS(o);
}
__managed__ CoordinateSystem* cs;
CPU_AND_GPU void testCi(
    const DepthImage* const di,
    const PointImage* const pi) {
    Vector2i imgSize(640, 480);
    assert(di->location() == Point(cs, Vector3f(0, 0, 0)));
    {
        auto r1 = di->getRayThroughPixel(Vector2i(0, 0), 1);
        assert(r1.origin == Point(cs, Vector3f(0, 0, 0)));
        assert(!(r1.direction == Vector(cs, Vector3f(0, 0, 1))));

        auto r2 = di->getRayThroughPixel(imgSize / 2, 1);
        assert(r2.origin == Point(cs, Vector3f(0, 0, 0)));
        assert(!(r2.direction == r1.direction));
        assert(r2.direction == Vector(cs, Vector3f(0, 0, 1)));
    }
    {
        auto r = di->getRayThroughPixel(imgSize / 2, 2);
        assert(r.origin == Point(cs, Vector3f(0, 0, 0)));
        assert(r.direction == Vector(cs, Vector3f(0, 0, 2)));
    }
    {
        auto r = di->getPointForPixel(Vector2i(0, 0));
        assert(r == Point(cs, Vector3f(0, 0, 0)));
    }
    {
        auto r = di->getPointForPixel(Vector2i(1, 0));
        assert(!(r == Point(cs, Vector3f(0, 0, 0))));
        assert(r.location.z == 1);
        auto ray = di->getRayThroughPixel(Vector2i(1, 0), 1);
        assert(ray.endpoint() == r);
    }


    assert(pi->location() == Point(cs, Vector3f(0, 0, 0)));
    assert(CoordinateSystem::global()->convert(pi->location()) == Point(CoordinateSystem::global(), Vector3f(0, 0, 1)));
    assert(
        cs->convert(Point(CoordinateSystem::global(), Vector3f(0, 0, 0)))
        ==
        Point(cs, Vector3f(0, 0, -1))
        );

    {
        auto r = pi->getPointForPixel(Vector2i(0, 0));
        assert(r == Point(cs, Vector3f(0, 0, 0)));
    }
    {
        auto r = pi->getPointForPixel(Vector2i(1, 0));
        assert(r == Point(cs, Vector3f(1, 1, 1)));
    }

    Vector2f pt_image;
    assert(pi->project(Point(CoordinateSystem::global(), Vector3f(0, 0, 2)), pt_image));
    assert(pt_image == (1 / 2.f) * imgSize.toFloat());// *(1 / 2.f));

    assert(pi->project(Point(di->eyeCoordinates, Vector3f(0, 0, 1)), pt_image));
    assert(pt_image == (1 / 2.f) * imgSize.toFloat());// *(1 / 2.f));
    assert(!pi->project(Point(CoordinateSystem::global(), Vector3f(0, 0, 0)), pt_image));

    assert(Point(di->eyeCoordinates, Vector3f(0, 0, 1))
        ==
        di->eyeCoordinates->convert(Point(CoordinateSystem::global(), Vector3f(0, 0, 2)))
        );
}

KERNEL ktestCi(
    const DepthImage* const di,
    const PointImage* const pi) {

    testCi(di, pi);
}
TEST(testCameraImage) {
    ITMIntrinsics intrin;
    Vector2i imgSize(640, 480);
    auto depthImage = new ITMFloatImage(imgSize);
    auto pointImage = new ITMFloat4Image(imgSize);

    depthImage->GetData()[1] = 1;
    pointImage->GetData()[1] = Vector4f(1, 1, 1, 1);
    // must submit manually
    depthImage->Synchronize();
    pointImage->Synchronize();

    Matrix4f cameraToWorld;
    cameraToWorld.setIdentity();
    cameraToWorld.setTranslate(Vector3f(0, 0, 1));
    cs = new CoordinateSystem(cameraToWorld);
    auto di = new DepthImage(depthImage, cs, intrin);
    auto pi = new PointImage(pointImage, cs, cs, intrin);

    testCi(di, pi);

    // must submit manually
    depthImage->Synchronize();
    pointImage->Synchronize();

    LAUNCH_KERNEL(ktestCi, 1, 1, di, pi);

}


TEST(testCS) {
    // o gives points with twice as large coordinates as the global coordinate system
    Matrix4f m;
    m.setIdentity();
    m.setScale(0.5); // scale down by half to get the global coordinates of the point
    auto o = new CoordinateSystem(m);

    testCS(o);
    LAUNCH_KERNEL(ktestCS, 1, 1, o);
}













































/** \brief
Represents a single "view", i.e. RGB and depth images along
with all intrinsic, relative and extrinsic calibration information

This defines a point-cloud with 'valid half-space-pseudonormals' for each point:
We know that the observed points have a normal that lies in the same half-space as the direction towards the camera,
otherwise we could not have observed them.
*/
class ITMView : public Managed {
    /// RGB colour image.
    ITMUChar4Image * const rgbData;

    /// Float valued depth image converted from disparity image, 
    /// if available according to @ref inputImageType.
    ITMFloatImage * const depthData;

    Vector2i imgSize_d() const {
        assert(depthImage->imgSize().area() > 1);
        return depthImage->imgSize();
    }
public:

    /// Intrinsic calibration information for the view.
    ITMRGBDCalib const * const calib;

    CameraImage<Vector4u> * const colorImage;

    /// Float valued depth image converted from disparity image, 
    /// if available according to @ref inputImageType.
    DepthImage * const depthImage;

    // \param M_d world-to-view matrix
    void ChangePose(Matrix4f M_d) {
        assert(&M_d);
        assert(abs(M_d.GetR().det() - 1) < 0.00001);
        // TODO delete old ones!
        auto depthCs = new CoordinateSystem(M_d.getInv());
        depthImage->eyeCoordinates = depthCs;

        Matrix4f M_rgb = calib->trafo_rgb_to_depth.calib_inv * M_d;
        auto colorCs = new CoordinateSystem(M_rgb.getInv());
        colorImage->eyeCoordinates = colorCs;
    }

    ITMView(const ITMRGBDCalib &calibration) : ITMView(&calibration) {};

    ITMView(const ITMRGBDCalib *calibration) :
        calib(new ITMRGBDCalib(*calibration)),
        rgbData(new ITMUChar4Image(calibration->intrinsics_rgb.imageSize())),

        depthData(new ITMFloatImage(calibration->intrinsics_d.imageSize())),

        depthImage(new DepthImage(depthData, CoordinateSystem::global(), calib->intrinsics_d)),
        colorImage(new CameraImage<Vector4u>(rgbData, CoordinateSystem::global(), calib->intrinsics_rgb)) {
        assert(colorImage->eyeCoordinates == CoordinateSystem::global());
        assert(depthImage->eyeCoordinates == CoordinateSystem::global());

        Matrix4f M; M.setIdentity();
        ChangePose(M);
        assert(!(colorImage->eyeCoordinates == CoordinateSystem::global()));
        assert(!(depthImage->eyeCoordinates == CoordinateSystem::global()));
        assert(!(colorImage->eyeCoordinates == depthImage->eyeCoordinates));
    }
    
    void ITMView::ChangeImages(ITMUChar4Image *rgbImage, ITMFloatImage *depthImage);
};

/// current depth & color image
__managed__ ITMView * currentView = 0;

#define INVALID_DEPTH (-1.f)


void ITMView::ChangeImages(ITMUChar4Image *rgbImage, ITMFloatImage *depthImage)
{
    rgbData->SetFrom(*rgbImage);
    depthData->SetFrom(*depthImage);
}
















/**
Voxel block coordinates.

This is the coarsest integer grid laid over our 3d space.

Multiply by SDF_BLOCK_SIZE to get voxel coordinates,
and then by ITMSceneParams::voxelSize to get world coordinates.

using short (Vector3*s*) to reduce storage requirements of hash map // TODO could use another type for accessing convenience/alignment speed
*/
typedef Vector3s VoxelBlockPos;
// Default voxel block pos, used for debugging
#define INVALID_VOXEL_BLOCK_POS Vector3s(SHRT_MIN, SHRT_MIN, SHRT_MIN)



















/** \brief
Stores the information of a single voxel in the volume
*/
class ITMVoxel
{
private:
    // signed distance, fixed comma 16 bit int, converted to snorm [-1, 1] range as described by OpenGL standard (?)/terminology as in DirectX11
    short sdf;  // saving storage
public:
    /** Value of the truncated signed distance transformation, in [-1, 1] (scaled by truncation distance mu when storing) */
    CPU_AND_GPU void setSDF_initialValue() { sdf = 32767; }
    CPU_AND_GPU float getSDF() const { return (float)(sdf) / 32767.0f; }
    CPU_AND_GPU void setSDF(float x) {
        assert(x >= -1 && x <= 1);
        sdf = (short)((x)* 32767.0f);
    }

    /** Number of fused observations that make up @p sdf. */
    uchar w_depth;

    /** RGB colour information stored for this voxel, 0-255 per channel. */
    Vector3u clr; // C(v) 

    /** Number of observations that made up @p clr. */
    uchar w_color;

    // for vsfs:

    //! unknowns of our objective
    float luminanceAlbedo; // a(v)
    //float refinedDistance; // D'(v)

    // chromaticity and intensity are
    // computed from C(v) on-the-fly -- TODO visualize those two

    // \in [0,1]
    CPU_AND_GPU float intensity() const {
        // TODO is this how luminance should be computed?
        Vector3f color = clr.toFloat() / 255.f;
        return (color.r + color.g + color.b) / 3.f;
    }

    /// \f$\Gamma(v)\f$
    // \in [0,255]^3
    CPU_AND_GPU Vector3f chromaticity() const {
        return clr.toFloat() / intensity();
    }
    

    // NOTE not used inially when memory is just allocated and reinterpreted, but used on each allocation
    CPU_AND_GPU ITMVoxel()
    {
        setSDF_initialValue();
        w_depth = 0;
        clr = (uchar)0;
        w_color = 0;

        // start with constant white albedo
        //luminanceAlbedo = 1.f;
    }
};

struct ITMVoxelBlock {
    CPU_AND_GPU void resetVoxels() {
        for (auto& i : blockVoxels) i = ITMVoxel();
    }

    /// compute voxelLocalId to access blockVoxels
    // TODO Vector3i is too general for the tightly limited range of valid values, c.f. assert statements below
    // TODO unify and document the use of 'localPos'/'globalPos' variable names
    CPU_AND_GPU ITMVoxel* getVoxel(Vector3i localPos) {
        assert(localPos.x >= 0 && localPos.x < SDF_BLOCK_SIZE);
        assert(localPos.y >= 0 && localPos.y < SDF_BLOCK_SIZE);
        assert(localPos.z >= 0 && localPos.z < SDF_BLOCK_SIZE);

        return &blockVoxels[
            // Note that x changes fastest here, while in a mathematica 3D array with indices {x,y,z}
            // x changes slowest!
            localPos.x + localPos.y * SDF_BLOCK_SIZE + localPos.z * SDF_BLOCK_SIZE * SDF_BLOCK_SIZE
        ];
    }

    CPU_AND_GPU VoxelBlockPos getPos() const {
        return pos_;
    }

    __declspec(property(get = getPos)) VoxelBlockPos pos;

    /// Initialize pos and reset data
    CPU_AND_GPU void reinit(VoxelBlockPos pos) {
        pos_ = pos;

        resetVoxels();
    }

    //private:
    /// pos is Mutable, 
    /// because this voxel block might represent any part of space, and it might be freed and reallocated later to represent a different part
    VoxelBlockPos pos_;

    ITMVoxel blockVoxels[SDF_BLOCK_SIZE3];
};




























/// Allocate sizeof(T) * count bytes and initialize it from device memory.
/// Used for debugging GPU memory from host 
template<typename T>
auto_ptr<T*> mallocAsDeviceCopy(DEVICEPTR(T*) p, uint count) {
    T* x = new T[count];
    cudaMemcpy(x, p, count * sizeof(T), cudaMemcpyDeviceToHost);
    return x;
}





















// GPU HashMap

// Forward declarations
template<typename Hasher, typename AllocCallback> class HashMap;
template<typename Hasher, typename AllocCallback>
KERNEL performAllocationKernel(typename HashMap<Hasher, AllocCallback>* hashMap);

#define hprintf(...) //printf(__VA_ARGS__) // enable for verbose radio debug messages

struct VoidSequenceIdAllocationCallback {
    template<typename T>
    static CPU_AND_GPU void allocate(T, int sequenceId) {}
};
/**
Implements a

    key -> sequence#

mapping on the GPU, where keys for which allocation is requested get assigned unique, 
consecutive unsigned integer numbers ('sequence numbers')
starting at 1.

These sequence numbers might be used to index into a pre-allocated list of objects.
This can be used to store sparse key-value data.

Stores at most Hasher::BUCKET_NUM + EXCESS_NUM - 1 entries.

After a series of 
    requestAllocation(key)
calls, 
    performAllocations()
must be called to make 
    getSequenceId(key)
return a unique nonzero value for key.

*Allocation is not guaranteed in only one requestAllocation(key) -> performAllocations() cycle*
At most one entry will be allocated per hash(key) in one such cycle.

c.f. ismar15infinitam.pdf

Note: As getSequenceId(key) reads from global memory it might be advisable to cache results,
especially when it is expected that the same entry is accessed multiple times from the same thread.

    In particular, when you index into a custom large datastructure with the result of this, you might want to copy
    the accessed data to __shared__ memory for optimum performance.

TODO Can we provide this functionality from here? Maybe force the creation of some object including a cache to access this.
TODO make public
TODO allow freeing entries
TODO allow choosing reliable allocation (using atomics...)
*/
/* Implementation: See HashMap.png */
template<
    typename Hasher, //!< must have static CPU_AND_GPU function uint Hasher::hash(const KeyType&) which generates values from 0 to Hasher::BUCKET_NUM-1 
    typename SequenceIdAllocationCallback = VoidSequenceIdAllocationCallback //!< must have static CPU_AND_GPU void  allocate(KeyType k, int sequenceId) function
>
class HashMap : public Managed {
public:
    typedef Hasher::KeyType KeyType;

private:
    static const uint BUCKET_NUM = Hasher::BUCKET_NUM;
    const uint EXCESS_NUM;
    CPU_AND_GPU uint NUMBER_TOTAL_ENTRIES() const {
        return (BUCKET_NUM + EXCESS_NUM);
    }

    struct HashEntry {
    public:
        CPU_AND_GPU bool isAllocated() {
            return sequenceId != 0;
        }
        CPU_AND_GPU bool hasNextExcessList() {
            assert(isAllocated());
            return nextInExcessList != 0;
        }
        CPU_AND_GPU uint getNextInExcessList() {
            assert(hasNextExcessList() && isAllocated());
            return nextInExcessList;
        }

        CPU_AND_GPU bool hasKey(const KeyType& key) {
            assert(isAllocated());
            return this->key == key;
        }

        CPU_AND_GPU void linkToExcessListEntry(const uint excessListId) {
            assert(!hasNextExcessList() && isAllocated() && excessListId >= 1);// && excessListId < EXCESS_NUM);
            // also, the excess list entry should exist and this should be the only entry linking to it
            // all entries in the excess list before this one should be allocated
            nextInExcessList = excessListId;
        }

        CPU_AND_GPU void allocate(const KeyType& key, const uint sequenceId) {
            assert(!isAllocated() && nextInExcessList == 0);
            assert(sequenceId > 0);
            this->key = key;
            this->sequenceId = sequenceId;

            SequenceIdAllocationCallback::allocate(key, sequenceId);

            hprintf("allocated %d\n", sequenceId);
        }

        CPU_AND_GPU uint getSequenceId() {
            assert(isAllocated());
            return sequenceId;
        }
    private:
        KeyType key;
        /// any of 1 to lowestFreeExcessListEntry-1
        /// 0 means this entry ends a list of excess entries and/or is not allocated
        uint nextInExcessList;
        /// any of 1 to lowestFreeSequenceNumber-1
        /// 0 means this entry is not allocated
        uint sequenceId;
    };

public:
    /// BUCKET_NUM + EXCESS_NUM many, information for the next round of allocations
    /// Note that equal hashes will clash only once

    /// Whether the corresponding entry should be allocated
    /// 0 or 1 
    /// TODO could save memory (&bandwidth) by using a bitmap
    MemoryBlock<uchar> needsAllocation;

    /// With which key the corresponding entry should be allocated
    /// TODO if there where an 'illegal key' entry, the above would not be needed. However, we would need to read 
    // a full key instead of 1 byte in more threads.
    /// State undefined for entries that don't need allocation
    MemoryBlock<KeyType> naKey;

    // TODO how much does separating allocation and requesting allocation really help?

//private:
    /// BUCKET_NUM + EXCESS_NUM many
    /// Indexed by Hasher::hash() return value
    // or BUCKET_NUM + HashEntry.nextInExcessList (which is any of 1 to lowestFreeExcessListEntry-1)
    MemoryBlock<HashEntry> hashMap_then_excessList;

private:
    CPU_AND_GPU HashEntry& hashMap(const uint hash) {
        assert(hash < BUCKET_NUM);
        return hashMap_then_excessList[hash];
    }
    CPU_AND_GPU HashEntry& excessList(const uint excessListEntry) {
        assert(excessListEntry >= 1 && excessListEntry < EXCESS_NUM);
        return hashMap_then_excessList[BUCKET_NUM + excessListEntry];
    }


    /// Sequence numbers already used up. Starts at 1 (sequence number 0 is used to signify non-allocated)
    uint lowestFreeSequenceNumber;

    /// Excess list slots already used up. Starts at 1 (one safeguard entry)
    uint lowestFreeExcessListEntry;

    /// Follows the excess list starting at hashMap[Hasher::hash(key)]
    /// until either hashEntry.key == key, returning true
    /// or until hashEntry does not exist or hashEntry.key != key but there is no further entry, returns false in that case.
    CPU_AND_GPU bool findEntry(const KeyType& key,//!< [in]
        HashEntry& hashEntry, //!< [out]
        uint& hashMap_then_excessList_entry //!< [out]
        ) {
        hashMap_then_excessList_entry = Hasher::hash(key);
        hprintf("%d %d\n", hashMap_then_excessList_entry, BUCKET_NUM);
        assert(hashMap_then_excessList_entry < BUCKET_NUM);
        hashEntry = hashMap(hashMap_then_excessList_entry);

        if (!hashEntry.isAllocated()) return false;
        if (hashEntry.hasKey(key)) return true;

        // try excess list
        int safe = 0;
        while (hashEntry.hasNextExcessList()) {
            hashEntry = excessList(hashMap_then_excessList_entry = hashEntry.getNextInExcessList());
            hashMap_then_excessList_entry += BUCKET_NUM; // the hashMap_then_excessList_entry must include the offset by BUCKET_NUM
            if (hashEntry.hasKey(key)) return true;
            if (safe++ > 100) fatalError("excessive amount of steps in excess list");
        }
        return false;
    }

    CPU_AND_GPU void allocate(HashEntry& hashEntry, const KeyType & key) {
#if GPU_CODE
        hashEntry.allocate(key, atomicAdd(&lowestFreeSequenceNumber, 1));
#else /* assume single-threaded cpu */
        hashEntry.allocate(key, lowestFreeSequenceNumber++);
#endif
    }

    friend KERNEL performAllocationKernel<Hasher, SequenceIdAllocationCallback>(typename HashMap<Hasher, SequenceIdAllocationCallback>* hashMap);


    /// Given a key that does not yet exist, find a location in the hashMap_then_excessList
    /// that can be used to insert the key (or is the end of the current excess list for the keys with the same hash as this)
    /// returns (uint)-1 if the key already exists
    CPU_AND_GPU uint findLocationForKey(const KeyType& key) {
        hprintf("findLocationForKey \n");

        HashEntry hashEntry;
        uint hashMap_then_excessList_entry;

        bool alreadyExists = findEntry(key, hashEntry, hashMap_then_excessList_entry);
        if (alreadyExists) {
            hprintf("already exists\n");
            return -1;
        }
        hprintf("request goes to %d\n", hashMap_then_excessList_entry);

        assert(hashMap_then_excessList_entry != BUCKET_NUM &&
            hashMap_then_excessList_entry < NUMBER_TOTAL_ENTRIES());
        return hashMap_then_excessList_entry;
    }
    
    /// hashMap_then_excessList_entry is an index into hashMap_then_excessList that is either free or the current
    /// end of the excess list for keys with the same hash as key.
    /// \returns the sequence number of the newly allocated entry
    CPU_AND_GPU uint performSingleAllocation(const KeyType& key, const uint hashMap_then_excessList_entry) {
        if (hashMap_then_excessList_entry == (uint)-1) return -1;
        if (hashMap_then_excessList_entry >= NUMBER_TOTAL_ENTRIES()) return -1;

        // Allocate in place if not allocated
        HashEntry& hashEntry = hashMap_then_excessList[hashMap_then_excessList_entry];

        if (!hashEntry.isAllocated()) {
            hprintf("not allocated\n", hashMap_then_excessList_entry);
            allocate(hashEntry, key);
            goto done;
        }

        hprintf("hashEntry %d\n", hashEntry.getSequenceId());

        // If existing, allocate new and link parent to child
#if GPU_CODE
        const uint excessListId = atomicAdd(&lowestFreeExcessListEntry, 1);
#else /* assume single-threaded cpu code */
        const uint excessListId = lowestFreeExcessListEntry++;
#endif

        HashEntry& newHashEntry = excessList(excessListId);
        assert(!newHashEntry.isAllocated());
        hashEntry.linkToExcessListEntry(excessListId);
        assert(hashEntry.getNextInExcessList() == excessListId);

        allocate(newHashEntry, key);
        hprintf("newHashEntry.getSequenceId() = %d\n", newHashEntry.getSequenceId());

        done:
#ifdef _DEBUG
        // we should now find this entry:
        HashEntry e; uint _;
        bool found = findEntry(key, e, _);
        assert(found && e.getSequenceId() > 0);
        hprintf("%d = findEntry(), e.seqId = %d\n", found, e.getSequenceId());
#endif
        return e.getSequenceId();
    }

    /// Perform allocation per-thread function, extracting key from naKey, then using performSingleAllocation 
    /// at the known _entry location
    GPU_ONLY void performAllocation(const uint hashMap_then_excessList_entry) {
        if (hashMap_then_excessList_entry >= NUMBER_TOTAL_ENTRIES()) return;
        if (!needsAllocation[hashMap_then_excessList_entry]) return;
        assert(hashMap_then_excessList_entry != BUCKET_NUM); // never allocate guard
        hprintf("performAllocation %d\n", hashMap_then_excessList_entry);


        needsAllocation[hashMap_then_excessList_entry] = false;
        KeyType key = naKey[hashMap_then_excessList_entry];

        const auto sid = performSingleAllocation(key, hashMap_then_excessList_entry);
        assert(sid > 0);
    }


public:
    HashMap(const uint EXCESS_NUM //<! must be at least one
        ) : EXCESS_NUM(EXCESS_NUM),
        needsAllocation(NUMBER_TOTAL_ENTRIES()),
        naKey(NUMBER_TOTAL_ENTRIES()),
        hashMap_then_excessList(NUMBER_TOTAL_ENTRIES())

    {
        assert(EXCESS_NUM >= 1);
        cudaDeviceSynchronize();

        lowestFreeSequenceNumber = lowestFreeExcessListEntry = 1;
    }

    CPU_AND_GPU // could be CPU only if it where not for debugging (and dumping) - do we need it at all?
        uint getLowestFreeSequenceNumber() {
#if !GPU_CODE
        cudaDeviceSynchronize();
#endif
        return lowestFreeSequenceNumber;
    }
    /*
    uint countAllocatedEntries() {
    return getLowestFreeSequenceNumber() - 1;
    }
    */

    // TODO should this ad-hoc crude serialization be part of this class?

    void serialize(ofstream& file) {
        bin(file, NUMBER_TOTAL_ENTRIES());
        bin(file, EXCESS_NUM);
        bin(file, lowestFreeSequenceNumber);
        bin(file, lowestFreeExcessListEntry);

        needsAllocation.serialize(file);
        naKey.serialize(file);
        hashMap_then_excessList.serialize(file);
    }

    /*
    reads from the binary file:
    - lowestFreeSequenceNumber
    - lowestFreeExcessListEntry
    - needsAllocation (ideally this is not in a dirty state currently, i.e. all 0)
    - naKey (ditto)
    - hashMap_then_excessList
    version and size of these structures in the file must match (full binary dump)
    */
    // loses current data
    void deserialize(ifstream& file) {
        assert(NUMBER_TOTAL_ENTRIES() == bin<uint>(file));
        assert(EXCESS_NUM == bin<uint>(file));
        bin(file, lowestFreeSequenceNumber);
        bin(file, lowestFreeExcessListEntry);

        needsAllocation.deserialize(file);
        naKey.deserialize(file);
        hashMap_then_excessList.deserialize(file);
    }

    /**
    Requests allocation for a specific key.
    Only one request can be made per hash(key) before performAllocations must be called.
    Further requests will be ignored.
    */
    GPU_ONLY void requestAllocation(const KeyType& key) {
        hprintf("requestAllocation \n");

        uint hashMap_then_excessList_entry = findLocationForKey(key);

        if (hashMap_then_excessList_entry == (uint)-1) {
            hprintf("already exists\n");
            return;
        }

        assert(hashMap_then_excessList_entry != BUCKET_NUM &&
            hashMap_then_excessList_entry < NUMBER_TOTAL_ENTRIES());

        // not strictly necessary, ordering is random anyways
        if (needsAllocation[hashMap_then_excessList_entry]) {
            hprintf("already requested\n");
            return;
        }

        needsAllocation[hashMap_then_excessList_entry] = true;
        naKey[hashMap_then_excessList_entry] = key;
    }

    // during performAllocations
#define THREADS_PER_BLOCK 256 // TODO which value works best?

    /**
    Allocates entries that requested allocation. Allocates at most one entry per hash(key).
    Further requests can allocate colliding entries.
    */
    void performAllocations() {
        //cudaSafeCall(cudaGetError());
        cudaSafeCall(cudaDeviceSynchronize()); // Managed this is not accessible when still in use?
        LAUNCH_KERNEL(performAllocationKernel, // Note: trivially parallelizable for-each type task
            /// Scheduling strategy: Fixed number of threads per block, working on all entries (to find those that have needsAllocation set)
            (uint)ceil(NUMBER_TOTAL_ENTRIES() / (1. * THREADS_PER_BLOCK)),
            THREADS_PER_BLOCK,
            this);
#ifdef _DEBUG
        cudaSafeCall(cudaDeviceSynchronize());  // detect problems (failed assertions) early where this kernel is called
#endif
        cudaSafeCall(cudaGetLastError());
    }

    /// Allocate and assign a sequence number for the given key.
    /// Note: Potentially slower than requesting a whole bunch, then allocating all at once, use as fallback.
    /// \returns the sequence number of the newly allocated entry
    CPU_AND_GPU uint performSingleAllocation(const KeyType& key) {
        return performSingleAllocation(key, findLocationForKey(key));
    }

    /// \returns 0 if the key is not allocated
    CPU_AND_GPU uint getSequenceNumber(const KeyType& key) {
        HashEntry hashEntry; uint _;
        if (!findEntry(key, hashEntry, _)) return 0;
        return hashEntry.getSequenceId();
    }
};

template<typename Hasher, typename AllocCallback>
KERNEL performAllocationKernel(typename HashMap<Hasher, AllocCallback>* hashMap) {
    assert(blockDim.x == THREADS_PER_BLOCK && blockDim.y == 1 && blockDim.z == 1);
    assert(
        gridDim.x*blockDim.x >= hashMap->NUMBER_TOTAL_ENTRIES() && // all entries covered
        gridDim.y == 1 &&
        gridDim.z == 1);
    assert(linear_global_threadId() == blockIdx.x*THREADS_PER_BLOCK + threadIdx.x);
    hashMap->performAllocation(blockIdx.x*THREADS_PER_BLOCK + threadIdx.x);
}







namespace HashMapTests {


    template<typename T>
    struct Z3Hasher {
        typedef T KeyType;
        static const uint BUCKET_NUM = 0x1000; // Number of Hash Bucket, must be 2^n (otherwise we have to use % instead of & below)

        static CPU_AND_GPU uint hash(const T& blockPos) {
            return (((uint)blockPos.x * 73856093u) ^ ((uint)blockPos.y * 19349669u) ^ ((uint)blockPos.z * 83492791u))
                & // optimization - has to be % if BUCKET_NUM is not a power of 2 // TODO can the compiler not figure this out?
                (uint)(BUCKET_NUM - 1);
        }
    };


    KERNEL get(HashMap<Z3Hasher<Vector3s>>* myHash, Vector3s q, int* o) {
        *o = myHash->getSequenceNumber(q);
    }

    KERNEL alloc(HashMap<Z3Hasher<Vector3s>>* myHash) {
        int p = blockDim.x * blockIdx.x + threadIdx.x;
        myHash->requestAllocation(p);
    }

    KERNEL assertfalse() {
        assert(false);
    }


    TEST(testZ3Hasher) {
        // insert a lot of points (n) into a large hash just for fun
        HashMap<Z3Hasher<Vector3s>>* myHash = new HashMap<Z3Hasher<Vector3s>>(0x2000);

        const int n = 1000;
        LAUNCH_KERNEL(alloc, n, 1, myHash);

        myHash->performAllocations();
        puts("after alloc");
        // should be some permutation of 1:n
        vector<bool> found; found.resize(n + 1);
        int* p; cudaMallocManaged(&p, sizeof(int));
        for (int i = 0; i < n; i++) {
            LAUNCH_KERNEL(get,
                1, 1,
                myHash, Vector3s(i, i, i), p);
            cudaSafeCall(cudaDeviceSynchronize()); // to read managed p
            printf("Vector3s(%i,%i,%i) -> %d\n", i, i, i, *p);

            assert(!found[*p]);
            found[*p] = 1;
        }
    }

    // n hasher test suite
    // trivial hash function n -> n
    struct NHasher{
        typedef int KeyType;
        static const uint BUCKET_NUM = 1; // can play with other values, the tests should support it
        static CPU_AND_GPU uint hash(const int& n) {
            return n % BUCKET_NUM;//& (BUCKET_NUM-1);
        }
    };

    KERNEL get(HashMap<NHasher>* myHash, int p, int* o) {
        *o = myHash->getSequenceNumber(p);
    }

    KERNEL alloc(HashMap<NHasher>* myHash, int p, int* o) {
        myHash->requestAllocation(p);
    }

    TEST(testNHasher) {
        int n = NHasher::BUCKET_NUM;
        auto myHash = new HashMap<NHasher>(1 + 1); // space for BUCKET_NUM entries only, and 1 collision handling entry

        int* p; cudaMallocManaged(&p, sizeof(int));

        for (int i = 0; i < n; i++) {

            LAUNCH_KERNEL(alloc,
                1, 1,
                myHash, i, p);
        }
        myHash->performAllocations();

        // an additional alloc at another key not previously seen (e.g. BUCKET_NUM) 
        // this will use the excess list
        LAUNCH_KERNEL(alloc, 1, 1, myHash, NHasher::BUCKET_NUM, p);
        myHash->performAllocations();

        // an additional alloc at another key not previously seen (e.g. BUCKET_NUM + 1) makes it crash cuz no excess list space is left
        //alloc << <1, 1 >> >(myHash, NHasher::BUCKET_NUM + 1, p);
        myHash->performAllocations(); // performAllocations is always fine to call when no extra allocations where made

        puts("after alloc");
        // should be some permutation of 1:BUCKET_NUM
        bool found[NHasher::BUCKET_NUM + 1] = {0};
        for (int i = 0; i < n; i++) {
            LAUNCH_KERNEL(get, 1, 1, myHash, i, p);
            cudaDeviceSynchronize();
            printf("%i -> %d\n", i, *p);
            assert(!found[*p]);
            //assert(*p != i+1); // numbers are very unlikely to be in order -- nah it happens
            found[*p] = 1;
        }

    }

    // zero hasher test suite
    // trivial hash function with one bucket.
    // This will allow the allocation of only one block at a time
    // and all blocks will be in the same list.
    // The numbers will be in order.
    struct ZeroHasher{
        typedef int KeyType;
        static const uint BUCKET_NUM = 0x1;
        static CPU_AND_GPU uint hash(const int&) { return 0; }
    };

    KERNEL get(HashMap<ZeroHasher>* myHash, int p, int* o) {
        *o = myHash->getSequenceNumber(p);
    }

    KERNEL alloc(HashMap<ZeroHasher>* myHash, int p, int* o) {
        myHash->requestAllocation(p);
    }

    TEST(testZeroHasher) {
        int n = 10;
        auto myHash = new HashMap<ZeroHasher>(n); // space for BUCKET_NUM(1) + excessnum(n-1) = n entries
        assert(myHash->getLowestFreeSequenceNumber() == 1);
        int* p; cudaMallocManaged(&p, sizeof(int));

        const int extra = 0; // doing one more will crash it at
        // Assertion `excessListEntry >= 1 && excessListEntry < EXCESS_NUM` failed.

        // Keep requesting allocation until all have been granted
        for (int j = 0; j < n + extra; j++) { // request & perform alloc cycle
            for (int i = 0; i < n + extra
                ; i++) {
                LAUNCH_KERNEL(alloc, 1, 1, myHash, i, p); // only one of these allocations will get through at a time
            }
            myHash->performAllocations();

            puts("after alloc");
            for (int i = 0; i < n; i++) {
                LAUNCH_KERNEL(get, 1, 1, myHash, i, p);
                cudaDeviceSynchronize();
                printf("%i -> %d\n", i, *p);
                // expected result
                assert(i <= j ? *p == i + 1 : *p == 0);
            }
        }

        assert(myHash->getLowestFreeSequenceNumber() != 1);
    }
}










































































// Scene, stores VoxelBlocks
// accessed via 'currentScene' to reduce amount of parameters passed to kernels
// TODO maybe prefer passing (statelessness), remove 'current' notion (is this a pipeline like OpenGL with state?)


// see doForEachAllocatedVoxel for T
#define doForEachAllocatedVoxel_process() static GPU_ONLY void process(const ITMVoxelBlock* vb, ITMVoxel* const v, const Vector3i localPos, const Vector3i globalPos, const Point globalPoint)


template<typename T>
KERNEL doForEachAllocatedVoxel(
    ITMVoxelBlock* localVBA,
    uint nextFreeSequenceId);

#define doForEachAllocatedVoxelBlock_process() static GPU_ONLY void process(ITMVoxelBlock* voxelBlock)
// see doForEachAllocatedVoxel for T
template<typename T>
KERNEL doForEachAllocatedVoxelBlock(
    ITMVoxelBlock* localVBA, uint nextFreeSequenceId
    ) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index <= 0 /* valid sequence nubmers start at 1 - TODO this knowledge should not be repeated here */
        || index >= nextFreeSequenceId) return;

    ITMVoxelBlock* vb = &localVBA[index];
    T::process(vb);
}


/// Must be heap-allocated
class Scene : public Managed {
public:
    /// Pos is in voxelCoordinates
    /// \returns NULL when the voxel was not found
    GPU_ONLY ITMVoxel* getVoxel(Vector3i pos);

    /// \returns a voxel block from the localVBA
    CPU_AND_GPU ITMVoxelBlock* getVoxelBlockForSequenceNumber(unsigned int sequenceNumber);

    // Two-phase allocation:

    /// Returns NULL if the voxel block is not allocated
    GPU_ONLY void requestVoxelBlockAllocation(VoxelBlockPos pos);
    static void Scene::performCurrentSceneAllocations();


#define CURRENT_SCENE_SCOPE(s) Scene::CurrentSceneScope currentSceneScope(s);

    /// Immediately allocate a voxel block at the given location.
    /// Perfer requestVoxelBlockAllocation & performCurrentSceneAllocations over this
    /// TODO how much performance is gained by not immediately allocating?
    unsigned int performVoxelBlockAllocation(VoxelBlockPos pos) {
        CURRENT_SCENE_SCOPE(this); // current scene has to be set for AllocateVB::allocate
        const unsigned int sequenceNumber = voxelBlockHash->performSingleAllocation(pos);
        assert(sequenceNumber > 0); // valid sequence numbers are > 0 -- TODO don't repeat this here
        return sequenceNumber;
    }

    Scene(const float newVoxelSize = 0.005f);
    virtual ~Scene();

    /// T must have an operator(ITMVoxelBlock*, ITMVoxel*, Vector3i localPos)
    /// where localPos will run from 0,0,0 to (SDF_BLOCK_SIZE-1)^3
    /// runs threadblock per voxel block and thread per thread
    template<typename T>
    void doForEachAllocatedVoxel() {
        cudaDeviceSynchronize(); // avoid in-page reading error, might even cause huge startup lag?
        LAUNCH_KERNEL( // fails in Release mode
            ::doForEachAllocatedVoxel<T>,
            voxelBlockHash->getLowestFreeSequenceNumber(),// at most SDF_LOCAL_BLOCK_NUM, // cannot be non power of 2?
            dim3(SDF_BLOCK_SIZE, SDF_BLOCK_SIZE, SDF_BLOCK_SIZE),

            // ITMVoxelBlock* localVBA, uint nextFreeSequenceId
            localVBA.GetData(MEMORYDEVICE_CUDA), voxelBlockHash->getLowestFreeSequenceNumber()
            );
    }

    /// T must have an operator(ITMVoxelBlock*)
    template<typename T>
    void doForEachAllocatedVoxelBlock() {

        dim3 blockSize(256);
        dim3 gridSize((int)ceil((float)SDF_LOCAL_BLOCK_NUM / (float)blockSize.x));
        LAUNCH_KERNEL(
            ::doForEachAllocatedVoxelBlock<T>,
            gridSize,
            blockSize,
            localVBA.GetData(MEMORYDEVICE_CUDA),
            voxelBlockHash->getLowestFreeSequenceNumber()
            );
    }

    static GPU_ONLY ITMVoxel* getCurrentSceneVoxel(Vector3i pos) {
        assert(getCurrentScene());
        return getCurrentScene()->getVoxel(pos);
    }
    static GPU_ONLY void requestCurrentSceneVoxelBlockAllocation(VoxelBlockPos pos) {
        assert(getCurrentScene());
        return getCurrentScene()->requestVoxelBlockAllocation(pos);
    }


    /** !private! But has to be placed in public for HashMap to access it - unless we make that a friend */
    struct Z3Hasher {
        typedef VoxelBlockPos KeyType;
        static const uint BUCKET_NUM = SDF_BUCKET_NUM; // Number of Hash Bucket, must be 2^n (otherwise we have to use % instead of & below)

        static CPU_AND_GPU uint hash(const VoxelBlockPos& blockPos) {
            return (((uint)blockPos.x * 73856093u) ^ ((uint)blockPos.y * 19349669u) ^ ((uint)blockPos.z * 83492791u))
                &
                (uint)(BUCKET_NUM - 1);
        }
    };

    /** !private! But has to be placed in public for HashMap to access it - unless we make that a friend*/
    struct AllocateVB {
        static CPU_AND_GPU void allocate(VoxelBlockPos pos, int sequenceId);
    };

    // Scene is mostly fixed. // TODO prefer using a scoping construct that lives together with the call stack!
    // Having it globally accessible heavily reduces having
    // to pass parameters.
    static CPU_AND_GPU Scene* getCurrentScene();

    /// Change current scene for the current block/scope
    class CurrentSceneScope {
    public:
        CurrentSceneScope(Scene* const newCurrentScene) :
            oldCurrentScene(Scene::getCurrentScene()) {
            Scene::setCurrentScene(newCurrentScene);
        }
        ~CurrentSceneScope() {
            Scene::setCurrentScene(oldCurrentScene);
        }

    private:
        Scene* const oldCurrentScene;
    };

    SERIALIZE_VERSION(2);
    void serialize(ofstream& file) {
        SERIALIZE_WRITE_VERSION(file);

        bin(file, voxelSize_);

        voxelBlockHash->serialize(file);

        assert(localVBA.dataSize == SDF_LOCAL_BLOCK_NUM);
        localVBA.serialize(file);
    }

    /*
    reads from the binary file:
    - the voxel size
    - the full voxelBlockHash
    - the full localVBA
    version and size of these structures in the file must match (full binary dump)
    */
    void deserialize(ifstream& file) {
        SERIALIZE_READ_VERSION(file);

        setVoxelSize(bin<decltype(voxelSize_)>(file));

        voxelBlockHash->deserialize(file);

        localVBA.deserialize(file);
        assert(localVBA.dataSize == SDF_LOCAL_BLOCK_NUM);

        // Assert that the file ends here
        // TODO assuming a file ends with serialized scene -- not necessarily so
        int x;  file >> x;
        assert(file.bad() || file.eof());
    }



    void setVoxelSize(float newVoxelSize) {
        voxelSize_ = newVoxelSize;

        Matrix4f m;
        m.setIdentity(); m.setScale(voxelSize_ * SDF_BLOCK_SIZE/*voxelBlockSize*/);
        voxelBlockCoordinates_ = new CoordinateSystem(m);

        m.setIdentity(); m.setScale(voxelSize_);
        voxelCoordinates_ = new CoordinateSystem(m);
    }
    CPU_AND_GPU float getVoxelSize() const {
        assert(this);
        return voxelSize_;
    }

    CPU_AND_GPU unsigned int countVoxelBlocks() {
        return voxelBlockHash->getLowestFreeSequenceNumber() - 1;
    }

    /// (0,0,0) is the lower corner of the first voxel block, (1,1,1) its upper corner,
    /// a position corresponding to (voxelBlockSize, voxelBlockSize, voxelBlockSize) in world coordinates.
    CoordinateSystem* voxelBlockCoordinates_ = 0;

    /// (0,0,0) is the lower corner of the voxel, (1,1,1) its upper corner,
    /// a position corresponding to (voxelSize, voxelSize, voxelSize) in world coordinates.
    /// aka "voxel-fractional-world-coordinates"
    CoordinateSystem* voxelCoordinates_ = 0;
private:

    static void setCurrentScene(Scene* s);

    GPU_ONLY DEVICEPTR(ITMVoxelBlock*) getVoxelBlock(VoxelBlockPos pos);

    float voxelSize_;

public: // data elements -- these two could be private where it not for testing/debugging

    MemoryBlock<ITMVoxelBlock> localVBA;

    /// Gives indices into localVBA for allocated voxel blocks
    // Cannot use an auto_ptr because this pointer is used on the device.
    HashMap<Z3Hasher, AllocateVB>* voxelBlockHash;

};

template<typename T>
KERNEL doForEachAllocatedVoxel(
    ITMVoxelBlock* localVBA,
    uint nextFreeSequenceId) {
    int index = blockIdx.x;
    if (index <= 0 || index >= nextFreeSequenceId) return;

    ITMVoxelBlock* vb = &localVBA[index];
    Vector3i localPos(threadIdx_xyz);

    // signature specified in doForEachAllocatedVoxel_process

    // TODO  an optimization would remove the following computations whose result is not used
    // in voxel coordinates (as passed to getVoxel of Scene)
    const Vector3i globalPos = vb->pos.toInt() * SDF_BLOCK_SIZE + localPos;

    // world-space coordinate position of current voxel
    auto globalPoint = Point(CoordinateSystem::global(), globalPos.toFloat() * voxelSize);

    T::process(
        vb,
        vb->getVoxel(localPos),
        localPos,
        globalPos,
        globalPoint);

}

//__device__ Scene* currentScene;
//__host__
__managed__ Scene* currentScene = 0; // TODO use __const__ memory, since this value is not changeable from gpu!

CPU_AND_GPU Scene* Scene::getCurrentScene() {
    return currentScene;
}

void Scene::setCurrentScene(Scene* s) {
    cudaDeviceSynchronize(); // want to write managed currentScene 
    currentScene = s;
}


// performAllocations -- private:
CPU_AND_GPU void Scene::AllocateVB::allocate(VoxelBlockPos pos, int sequenceId) {
    assert(Scene::getCurrentScene());
    assert(sequenceId < SDF_LOCAL_BLOCK_NUM, "%d >= %d -- not enough voxel blocks", sequenceId, SDF_LOCAL_BLOCK_NUM);
    Scene::getCurrentScene()->localVBA[sequenceId].reinit(pos);
}

void Scene::performCurrentSceneAllocations() {
    assert(Scene::getCurrentScene());
    Scene::getCurrentScene()->voxelBlockHash->performAllocations(); // will call Scene::AllocateVB::allocate for all outstanding allocations
    cudaDeviceSynchronize();
}
//

Scene::Scene(const float newVoxelSize) : localVBA(SDF_LOCAL_BLOCK_NUM) {
    initCoordinateSystems();
    setVoxelSize(newVoxelSize);
    voxelBlockHash = new HashMap<Z3Hasher, AllocateVB>(SDF_EXCESS_LIST_SIZE);
}

Scene::~Scene() {
    delete voxelBlockHash;
}

static GPU_ONLY inline VoxelBlockPos pointToVoxelBlockPos(
    const Vector3i & point //!< [in] in voxel coordinates
    ) {
    // "The 3D voxel block location is obtained by dividing the voxel coordinates with the block size along each axis."
    VoxelBlockPos blockPos;
    // if SDF_BLOCK_SIZE == 8, then -3 should go to block -1, so we need to adjust negative values 
    // (C's quotient-remainder division gives -3/8 == 0)
    blockPos.x = ((point.x < 0) ? point.x - SDF_BLOCK_SIZE + 1 : point.x) / SDF_BLOCK_SIZE;
    blockPos.y = ((point.y < 0) ? point.y - SDF_BLOCK_SIZE + 1 : point.y) / SDF_BLOCK_SIZE;
    blockPos.z = ((point.z < 0) ? point.z - SDF_BLOCK_SIZE + 1 : point.z) / SDF_BLOCK_SIZE;
    return blockPos;
}

GPU_ONLY ITMVoxel* Scene::getVoxel(Vector3i point) {
    VoxelBlockPos blockPos = pointToVoxelBlockPos(point);

    ITMVoxelBlock* b = getVoxelBlock(blockPos);
    if (b == NULL) return NULL;

    Vector3i localPos = point - blockPos.toInt() * SDF_BLOCK_SIZE; // localized coordinate
    return b->getVoxel(localPos);
}

CPU_AND_GPU ITMVoxelBlock* Scene::getVoxelBlockForSequenceNumber(unsigned int sequenceNumber) {
    assert(sequenceNumber >= 1 && sequenceNumber < SDF_LOCAL_BLOCK_NUM, "illegal sequence number %d (must be >= 1, < %d)", sequenceNumber, SDF_LOCAL_BLOCK_NUM);
    assert(sequenceNumber < voxelBlockHash->getLowestFreeSequenceNumber(), 
        "unallocated sequence number %d (lowest free: %d)"
        , sequenceNumber
        , voxelBlockHash->getLowestFreeSequenceNumber()
        );

    return &localVBA[sequenceNumber];
}

/// Returns NULL if the voxel block is not allocated
GPU_ONLY ITMVoxelBlock* Scene::getVoxelBlock(VoxelBlockPos pos) {
    int sequenceNumber = voxelBlockHash->getSequenceNumber(pos); // returns 0 if pos is not allocated
    if (sequenceNumber == 0) return NULL;
    return &localVBA[sequenceNumber];
}

GPU_ONLY void Scene::requestVoxelBlockAllocation(VoxelBlockPos pos) {
    voxelBlockHash->requestAllocation(pos);
}






















namespace TestScene {
    // [[ procedural scenes
    __managed__ int counter = 0;
    static KERNEL buildBlockRequests(Vector3i offset) {
        Scene::requestCurrentSceneVoxelBlockAllocation(
            VoxelBlockPos(
            offset.x + blockIdx.x,
            offset.y + blockIdx.y,
            offset.z + blockIdx.z));
    }
    static __managed__ float radiusInWorldCoordinates;


    struct BuildSphere {
        doForEachAllocatedVoxel_process() {
            assert(v);
            assert(radiusInWorldCoordinates > 0);

            // world-space coordinate position of current voxel
            Vector3f voxelGlobalPos = globalPoint.location;

            // Compute distance to origin
            const float distanceToOrigin = length(voxelGlobalPos);
            // signed distance to radiusInWorldCoordinates, positive when bigger
            const float dist = distanceToOrigin - radiusInWorldCoordinates;

            // Truncate and convert to -1..1 for band of size mu
            // (Note: voxel blocks with all 1 or all -1 don't usually exist, but they do for this sphere)
            const float eta = dist;
            v->setSDF(MAX(MIN(1.0f, eta / mu), -1.f));

            v->clr = Vector3u(255, 255, 0); // yellow sphere for debugging

            v->w_color = 1;
            v->w_depth = 1;
        }
    };

    static KERNEL countAllocatedBlocks(Vector3i offset) {
        if (Scene::getCurrentSceneVoxel(
            VoxelBlockPos(
            offset.x + blockIdx.x,
            offset.y + blockIdx.y,
            offset.z + blockIdx.z).toInt() * SDF_BLOCK_SIZE
            ))
            atomicAdd(&counter, 1);
    }
    void buildSphereScene(const float radiusInWorldCoordinates_) {
        assert(radiusInWorldCoordinates_ > 0);
        radiusInWorldCoordinates = radiusInWorldCoordinates_;
        const float diameterInWorldCoordinates = radiusInWorldCoordinates * 2;
        int offseti = -ceil(radiusInWorldCoordinates / voxelBlockSize) - 1; // -1 for extra space
        assert(offseti < 0);

        Vector3i offset(offseti, offseti, offseti);
        int counti = 2 * -offseti;
        assert(counti > 0);
        dim3 count(counti, counti, counti);
        assert(offseti + count.x == -offseti);

        // repeat allocation a few times to avoid holes
        do {
            LAUNCH_KERNEL(buildBlockRequests, count, 1, offset);
            cudaDeviceSynchronize();

            Scene::performCurrentSceneAllocations();
            cudaDeviceSynchronize();

            counter = 0;

            LAUNCH_KERNEL(countAllocatedBlocks, count, 1, offset);
            cudaDeviceSynchronize();
        } while (counter != counti*counti*counti);

        // Then set up the voxels to represent a sphere
        Scene::getCurrentScene()->doForEachAllocatedVoxel<BuildSphere>();
        return;
    }

    // assumes buildWallRequests has been executed
    // followed by perform allocations
    // builds a solid wall, i.e.
    // an trunctated sdf reaching 0 at 
    // z == (SDF_BLOCK_SIZE / 2)*voxelSize
    // and negative at bigger z.
    struct BuildWall {
        doForEachAllocatedVoxel_process() {
            assert(v);

            float z = (threadIdx.z) * voxelSize;
            float eta = (SDF_BLOCK_SIZE / 2)*voxelSize - z;
            v->setSDF(MAX(MIN(1.0f, eta / mu), -1.f));

            v->clr = Vector3u(255, 255, 0); // YELLOW WALL
        }
    };
    void buildWallScene() {
        // Build wall scene

        LAUNCH_KERNEL(buildBlockRequests, dim3(10, 10, 1), 1, Vector3i(0, 0, 0));

        cudaDeviceSynchronize();
        Scene::performCurrentSceneAllocations();
        cudaDeviceSynchronize();
        Scene::getCurrentScene()->doForEachAllocatedVoxel<BuildWall>();
    }

    // ]]




    TEST(testSceneSerialize) {
        Scene* scene = new Scene();
        CURRENT_SCENE_SCOPE(scene);
        buildSphereScene(0.5);

        MemoryBlock<ITMVoxelBlock> mb(scene->localVBA);
        MemoryBlock<uchar> cb(scene->voxelBlockHash->needsAllocation);
        // TODO check hash map itself

        assert(cb == scene->voxelBlockHash->needsAllocation);
        assert(mb == scene->localVBA);

        {
            scene->serialize(binopen_write("scene.bin"));
        }

        assert(mb == scene->localVBA);
        {
            scene->deserialize(binopen_read("scene.bin"));
        }

        assert(mb == scene->localVBA);
        {
            scene->serialize(binopen_write("scene2.bin"));
        }
        assert(mb == scene->localVBA);


        {
            scene->deserialize(binopen_read("scene2.bin"));
        }

        assert(mb == scene->localVBA);
        assert(cb == scene->voxelBlockHash->needsAllocation);

        delete scene;
    }



    struct WriteEach {
        doForEachAllocatedVoxel_process() {
            v->setSDF((
                localPos.x +
                localPos.y * SDF_BLOCK_SIZE +
                localPos.z * SDF_BLOCK_SIZE * SDF_BLOCK_SIZE
                ) / 1024.f);
        }
    };

    __managed__ int _counter = 0;
    __managed__ bool visited[SDF_BLOCK_SIZE][SDF_BLOCK_SIZE][SDF_BLOCK_SIZE] = {0};
    struct DoForEach {
        doForEachAllocatedVoxel_process() {
            assert(localPos.x >= 0 && localPos.y >= 0 && localPos.z >= 0);
            assert(localPos.x < SDF_BLOCK_SIZE && localPos.y < SDF_BLOCK_SIZE && localPos.z < SDF_BLOCK_SIZE);

            assert(vb);
            assert(vb->pos == VoxelBlockPos(0, 0, 0) ||
                vb->pos == VoxelBlockPos(1, 2, 3));

            visited[localPos.x][localPos.y][localPos.z] = 1;

            printf("%f .. %f\n", v->getSDF(),
                (
                localPos.x +
                localPos.y * SDF_BLOCK_SIZE +
                localPos.z * SDF_BLOCK_SIZE * SDF_BLOCK_SIZE
                ) / 1024.f);
            assert(abs(
                v->getSDF() -
                (
                localPos.x +
                localPos.y * SDF_BLOCK_SIZE +
                localPos.z * SDF_BLOCK_SIZE * SDF_BLOCK_SIZE
                ) / 1024.f) < 0.001 // not perfectly accurate
                );
            atomicAdd(&_counter, 1);
        }
    };

    struct DoForEachBlock {
        static GPU_ONLY void process(ITMVoxelBlock* vb) {
            assert(vb);
            assert(vb->pos == VoxelBlockPos(0, 0, 0) ||
                vb->pos == VoxelBlockPos(1, 2, 3));
            atomicAdd(&_counter, 1);
        }
    };

    KERNEL modifyS() {
        Scene::getCurrentSceneVoxel(Vector3i(0, 0, 1))->setSDF(1.0);
    }

    KERNEL checkModifyS() {
        assert(Scene::getCurrentSceneVoxel(Vector3i(0, 0, 1))->getSDF() == 1.0);
    }

    KERNEL addSceneVB(Scene* scene) {
        assert(scene);
        scene->requestVoxelBlockAllocation(VoxelBlockPos(0, 0, 0));
        scene->requestVoxelBlockAllocation(VoxelBlockPos(1, 2, 3));
    }
    GPU_ONLY void allExist(Scene* scene, Vector3i base) {
        for (int i = 0; i < SDF_BLOCK_SIZE; i++)
            for (int j = 0; j < SDF_BLOCK_SIZE; j++)
                for (int k = 0; k < SDF_BLOCK_SIZE; k++) {
                    ITMVoxel* v = scene->getVoxel(base + Vector3i(i, j, k));
                    assert(v != NULL);
                }
    }
    KERNEL checkS(Scene* scene) {
        assert(Scene::getCurrentScene() == scene);
    }
    KERNEL findSceneVoxel(Scene* scene) {
        allExist(scene, Vector3i(0, 0, 0));
        allExist(scene, Vector3i(SDF_BLOCK_SIZE, 2 * SDF_BLOCK_SIZE, 3 * SDF_BLOCK_SIZE));

        assert(scene->getVoxel(Vector3i(-1, 0, 0)) == NULL);
    }
    TEST(testScene) {
        assert(Scene::getCurrentScene() == 0);

        Scene* s = new Scene();
        LAUNCH_KERNEL(addSceneVB, 1, 1, s);
        {
            CURRENT_SCENE_SCOPE(s);
            Scene::performCurrentSceneAllocations();
        }
        LAUNCH_KERNEL(findSceneVoxel, 1, 1, s);

        // current scene starts out at 0
        LAUNCH_KERNEL(checkS, 1, 1, 0);

        // change current scene
        {
            LAUNCH_KERNEL(checkS, 1, 1, 0); // still 0 before scope begins

            CURRENT_SCENE_SCOPE(s);
            LAUNCH_KERNEL(checkS, 1, 1, s);
            // Nest
            {
                CURRENT_SCENE_SCOPE(0);
                LAUNCH_KERNEL(checkS, 1, 1, 0);
            }
            LAUNCH_KERNEL(checkS, 1, 1, s);
        }
        LAUNCH_KERNEL(checkS, 1, 1, 0); // 0 again

        // modify current scene
        {
            CURRENT_SCENE_SCOPE(s);
            LAUNCH_KERNEL(modifyS, 1, 1);
            LAUNCH_KERNEL(checkModifyS, 1, 1);
        }

        // do for each

        s->doForEachAllocatedVoxel<WriteEach>(); // hangs in debug build

        _counter = 0;
        for (int x = 0; x < SDF_BLOCK_SIZE; x++)
            for (int y = 0; y < SDF_BLOCK_SIZE; y++)
                for (int z = 0; z < SDF_BLOCK_SIZE; z++)
                    assert(!visited[x][y][z]);
        s->doForEachAllocatedVoxel<DoForEach>();
        cudaDeviceSynchronize();
        assert(_counter == 2 * SDF_BLOCK_SIZE3);
        for (int x = 0; x < SDF_BLOCK_SIZE; x++)
            for (int y = 0; y < SDF_BLOCK_SIZE; y++)
                for (int z = 0; z < SDF_BLOCK_SIZE; z++)
                    assert(visited[x][y][z]);

        _counter = 0;
        s->doForEachAllocatedVoxelBlock<DoForEachBlock>();
        cudaDeviceSynchronize();
        assert(_counter == 2);

        delete s;
    }
}























































/// === ITMBlockhash methods (readVoxel) ===

// isFound is assumed true initially and set to false when a requested voxel is not found
// a new voxel is returned in that case
GPU_ONLY inline ITMVoxel readVoxel(
    const Vector3i & point,
    bool &isFound, Scene* scene = Scene::getCurrentScene())
{
    ITMVoxel* v = scene->getVoxel(point);
    if (!v) {
        isFound = false;
        return ITMVoxel();
    }
    return *v;
}


/// === Generic methods (readSDF) ===

// isFound is set to true or false
GPU_ONLY inline float readFromSDF_float_uninterpolated(
    Vector3f point, //!< in voxel-fractional-world-coordinates (such that one voxel has size 1)
    bool &isFound)
{
    isFound = true;
    ITMVoxel res = readVoxel(TO_INT_ROUND3(point), isFound);
    return res.getSDF();
}

#define COMPUTE_COEFF_POS_FROM_POINT() \
    /* Coeff are the sub-block coordinates, used for interpolation*/\
    Vector3f coeff; Vector3i pos; TO_INT_FLOOR3(pos, coeff, point);

// Given point in voxel-fractional-world-coordinates, this calls
// f(Vector3i globalPos, Vector3i lerpCoeff) on each globalPos (voxel-world-coordinates) bounding the given point
// in no specific order
template<typename T>
GPU_ONLY
void forEachBoundingVoxel(
Vector3f point, //!< in voxel-fractional-world-coordinates (such that one voxel has size 1)
T& f
) {

    COMPUTE_COEFF_POS_FROM_POINT();
    float lerpCoeff;

#define access(dx,dy,dz) \
    lerpCoeff = \
    (dx ? coeff.x : 1.0f - coeff.x) *\
    (dy ? coeff.y : 1.0f - coeff.y) *\
    (dz ? coeff.z : 1.0f - coeff.z);\
    f(pos + Vector3i(dx, dy, dz), lerpCoeff);


    access(0, 0, 0);
    access(0, 0, 1);
    access(0, 1, 0);
    access(0, 1, 1);
    access(1, 0, 0);
    access(1, 0, 1);
    access(1, 1, 0);
    access(1, 1, 1);

#undef access
}

struct InterpolateSDF {
    float result;
    bool& isFound;
    GPU_ONLY InterpolateSDF(bool& isFound) : result(0), isFound(isFound) {}

    GPU_ONLY void operator()(Vector3i globalPos, float lerpCoeff) {
        result += lerpCoeff * readVoxel(globalPos, isFound).getSDF();
    }
};

GPU_ONLY inline float readFromSDF_float_interpolated(
    Vector3f point, //!< in voxel-fractional-world-coordinates (such that one voxel has size 1)
    bool &isFound)
{
    InterpolateSDF interpolator(isFound);
    forEachBoundingVoxel(point, interpolator);
    return interpolator.result;
}

struct InterpolateColor {
    Vector3f result;
    bool& isFound;
    GPU_ONLY InterpolateColor(bool& isFound) : result(0, 0, 0), isFound(isFound) {}

    GPU_ONLY void operator()(Vector3i globalPos, float lerpCoeff) {
        result += lerpCoeff * readVoxel(globalPos, isFound).clr.toFloat();
    }
};

// TODO should this also have a isFound parameter?
/// Assumes voxels store color in some type convertible to Vector3f (e.g. Vector3u)
GPU_ONLY inline Vector3f readFromSDF_color4u_interpolated(
    const Vector3f & point //!< in voxel-fractional world coordinates, comes e.g. from raycastResult
    )
{
    bool isFound = true;
    InterpolateColor interpolator(isFound);
    forEachBoundingVoxel(point, interpolator);
    return interpolator.result;
}


#define lookup(dx,dy,dz) readVoxel(pos + Vector3i(dx,dy,dz), isFound).getSDF()

// TODO test and visualize
// e.g. round to voxel position when rendering and draw this
GPU_ONLY inline UnitVector computeSingleNormalFromSDFByForwardDifference(
    const Vector3i &pos, //!< [in] global voxel position
    bool& isFound //!< [out] whether all values needed existed;
    ) {
    float sdf0 = lookup(0, 0, 0);
    if (!isFound) return Vector3f();

    // TODO handle !isFound
    Vector3f n(
        lookup(1, 0, 0) - sdf0,
        lookup(0, 1, 0) - sdf0,
        lookup(0, 0, 1) - sdf0
        );
    return n.normalised(); // TODO in a distance field, normalization should not be necessary? But this is not a true distance field.
}

/// Compute SDF normal by interpolated symmetric differences
/// Used in processPixelGrey
// Note: this gets the localVBA list, not just a *single* voxel block.
GPU_ONLY inline Vector3f computeSingleNormalFromSDF(
    const Vector3f &point)
{

    Vector3f ret;
    COMPUTE_COEFF_POS_FROM_POINT();
    Vector3f ncoeff = Vector3f(1, 1, 1) - coeff;

    bool isFound; // swallow

    /*
    x direction gradient at point is evaluated by computing interpolated sdf value in next (1 -- 2, v2) and previous (-1 -- 0, v1) cell:

    -1  0   1   2
    *---*---*---*
    |v1 |   | v2|
    *---*---*---*

    0 z is called front, 1 z is called back

    gradient is then
    v2 - v1
    */

    /* using xyzw components of vector4f to store 4 sdf values as follows:

    *---0--1-> x
    |
    0   x--y
    |   |  |
    1   z--w
    \/
    y
    */

    // all 8 values are going to be reused several times
    Vector4f front, back;
    front.x = lookup(0, 0, 0);
    front.y = lookup(1, 0, 0);
    front.z = lookup(0, 1, 0);
    front.w = lookup(1, 1, 0);
    back.x = lookup(0, 0, 1);
    back.y = lookup(1, 0, 1);
    back.z = lookup(0, 1, 1);
    back.w = lookup(1, 1, 1);

    Vector4f tmp;
    float p1, p2, v1;
    // gradient x
    // v1
    // 0-layer
    p1 = front.x * ncoeff.y * ncoeff.z +
        front.z *  coeff.y * ncoeff.z +
        back.x  * ncoeff.y *  coeff.z +
        back.z  *  coeff.y *  coeff.z;
    // (-1)-layer
    tmp.x = lookup(-1, 0, 0);
    tmp.y = lookup(-1, 1, 0);
    tmp.z = lookup(-1, 0, 1);
    tmp.w = lookup(-1, 1, 1);
    p2 = tmp.x * ncoeff.y * ncoeff.z +
        tmp.y *  coeff.y * ncoeff.z +
        tmp.z * ncoeff.y *  coeff.z +
        tmp.w *  coeff.y *  coeff.z;

    v1 = p1 * coeff.x + p2 * ncoeff.x;

    // v2
    // 1-layer
    p1 = front.y * ncoeff.y * ncoeff.z +
        front.w *  coeff.y * ncoeff.z +
        back.y  * ncoeff.y *  coeff.z +
        back.w  *  coeff.y *  coeff.z;
    // 2-layer
    tmp.x = lookup(2, 0, 0);
    tmp.y = lookup(2, 1, 0);
    tmp.z = lookup(2, 0, 1);
    tmp.w = lookup(2, 1, 1);
    p2 = tmp.x * ncoeff.y * ncoeff.z +
        tmp.y *  coeff.y * ncoeff.z +
        tmp.z * ncoeff.y *  coeff.z +
        tmp.w *  coeff.y *  coeff.z;

    ret.x = (
        p1 * ncoeff.x + p2 * coeff.x // v2
        -
        v1);

    // gradient y
    p1 = front.x * ncoeff.x * ncoeff.z +
        front.y *  coeff.x * ncoeff.z +
        back.x  * ncoeff.x *  coeff.z +
        back.y  *  coeff.x *  coeff.z;
    tmp.x = lookup(0, -1, 0);
    tmp.y = lookup(1, -1, 0);
    tmp.z = lookup(0, -1, 1);
    tmp.w = lookup(1, -1, 1);
    p2 = tmp.x * ncoeff.x * ncoeff.z +
        tmp.y *  coeff.x * ncoeff.z +
        tmp.z * ncoeff.x *  coeff.z +
        tmp.w *  coeff.x *  coeff.z;
    v1 = p1 * coeff.y + p2 * ncoeff.y;

    p1 = front.z * ncoeff.x * ncoeff.z +
        front.w *  coeff.x * ncoeff.z +
        back.z  * ncoeff.x *  coeff.z +
        back.w  *  coeff.x *  coeff.z;
    tmp.x = lookup(0, 2, 0);
    tmp.y = lookup(1, 2, 0);
    tmp.z = lookup(0, 2, 1);
    tmp.w = lookup(1, 2, 1);
    p2 = tmp.x * ncoeff.x * ncoeff.z +
        tmp.y *  coeff.x * ncoeff.z +
        tmp.z * ncoeff.x *  coeff.z +
        tmp.w *  coeff.x *  coeff.z;

    ret.y = (p1 * ncoeff.y + p2 * coeff.y - v1);

    // gradient z
    p1 = front.x * ncoeff.x * ncoeff.y +
        front.y *  coeff.x * ncoeff.y +
        front.z * ncoeff.x *  coeff.y +
        front.w *  coeff.x *  coeff.y;
    tmp.x = lookup(0, 0, -1);
    tmp.y = lookup(1, 0, -1);
    tmp.z = lookup(0, 1, -1);
    tmp.w = lookup(1, 1, -1);
    p2 = tmp.x * ncoeff.x * ncoeff.y +
        tmp.y *  coeff.x * ncoeff.y +
        tmp.z * ncoeff.x *  coeff.y +
        tmp.w *  coeff.x *  coeff.y;
    v1 = p1 * coeff.z + p2 * ncoeff.z;

    p1 = back.x * ncoeff.x * ncoeff.y +
        back.y *  coeff.x * ncoeff.y +
        back.z * ncoeff.x *  coeff.y +
        back.w *  coeff.x *  coeff.y;
    tmp.x = lookup(0, 0, 2);
    tmp.y = lookup(1, 0, 2);
    tmp.z = lookup(0, 1, 2);
    tmp.w = lookup(1, 1, 2);
    p2 = tmp.x * ncoeff.x * ncoeff.y +
        tmp.y *  coeff.x * ncoeff.y +
        tmp.z * ncoeff.x *  coeff.y +
        tmp.w *  coeff.x *  coeff.y;

    ret.z = (p1 * ncoeff.z + p2 * coeff.z - v1);
#undef lookup
    return ret;
}

#undef COMPUTE_COEFF_POS_FROM_POINT
#undef lookup

































namespace rendering {



    /**
    the 3D intersection locations generated by the latest raycast
    in voxelCoordinates
    */
    __managed__ PointImage* raycastResult;

    // for ICP
    //!< [out] receives output points in world coordinates
    //!< [out] receives world space normals computed from points (image space)
    // __managed__ DEVICEPTR(RayImage) * lastFrameICPMap = 0; // -- defined earlier

    // for RenderImage. Transparent where nothing is hit, otherwise computed by any of the DRAWFUNCTIONs
    __managed__ CameraImage<Vector4u>* outRendering = 0;
    __managed__ Vector3f towardsCamera;

    // written by rendering, world-space, 0 for invalid depths
    __managed__ ITMFloatImage* outDepth;

    // === raycasting, rendering ===
    /// \param x,y [in] camera space pixel determining ray direction
    //!< [out] raycastResult[locId]: the intersection point. 
    // w is 1 for a valid point, 0 for no intersection; in voxel-fractional-world-coordinates
    struct castRay {
        forEachPixelNoImage_process()
        {
            // Find 3d position of depth pixel xy, in eye coordinates
            auto pt_camera_f = raycastResult->getRayThroughPixel(Vector2i(x, y), viewFrustum_min);
            assert(pt_camera_f.origin.coordinateSystem == raycastResult->eyeCoordinates);
            auto l = pt_camera_f.endpoint().location;
            assert(l.z == viewFrustum_min);

            // Length given in voxel-fractional-coordinates (such that one voxel has size 1)
            auto pt_camera_f_vc = voxelCoordinates->convert(pt_camera_f);
            float totalLength = length(pt_camera_f_vc.direction.direction);
            assert(voxelSize < 1);
            assert(totalLength > length(pt_camera_f.direction.direction));
            assert(abs(
                totalLength - length(pt_camera_f.direction.direction) / voxelSize) < 0.001f);

            // in voxel-fractional-world-coordinates (such that one voxel has size 1)
            assert(pt_camera_f.endpoint().coordinateSystem == raycastResult->eyeCoordinates);
            assert(!(pt_camera_f_vc.endpoint().coordinateSystem == raycastResult->eyeCoordinates));
            const auto pt_block_s = pt_camera_f_vc.endpoint();

            // End point
            auto pt_camera_e = raycastResult->getRayThroughPixel(Vector2i(x, y), viewFrustum_max);
            auto pt_camera_e_vc = voxelCoordinates->convert(pt_camera_e);
            const float totalLengthMax = length(pt_camera_e_vc.direction.direction);
            const auto pt_block_e = pt_camera_e_vc.endpoint();

            assert(totalLength < totalLengthMax);
            assert(pt_block_s.coordinateSystem == voxelCoordinates);
            assert(pt_block_e.coordinateSystem == voxelCoordinates);

            // Raymarching
            const auto rayDirection = Vector(voxelCoordinates, normalize(pt_block_e.location - pt_block_s.location));
            auto pt_result = pt_block_s; // Current position in voxel-fractional-world-coordinates
            const float stepScale = mu * oneOverVoxelSize; // sdf values are distances in world-coordinates, normalized by division through mu. This is the factor to convert to voxelCoordinates.

            // TODO use caching, we will access the same voxel block multiple times
            float sdfValue = 1.0f;
            bool hash_found;

            // in voxel-fractional-world-coordinates (1.0f means step one voxel)
            float stepLength;

            while (totalLength < totalLengthMax) {
                // D(X)
                sdfValue = readFromSDF_float_uninterpolated(pt_result.location, hash_found);

                if (!hash_found) {
                    //  First we try to find an allocated voxel block, and the length of the steps we take is determined by the block size
                    stepLength = SDF_BLOCK_SIZE;
                }
                else {
                    // If we found an allocated block, 
                    // [Once we are inside the truncation band], the values from the SDF give us conservative step lengths.

                    // using trilinear interpolation only if we have read values in the range −0.5 ≤ D(X) ≤ 0.1
                    if ((sdfValue <= 0.1f) && (sdfValue >= -0.5f)) {
                        sdfValue = readFromSDF_float_interpolated(pt_result.location, hash_found);
                    }
                    // once we read a negative value from the SDF, we found the intersection with the surface.
                    if (sdfValue <= 0.0f) break;

                    stepLength = MAX(
                        sdfValue * stepScale,
                        1.0f // if we are outside the truncation band µ, our step size is determined by the truncation band 
                        // (note that the distance is normalized to lie in [-1,1] within the truncation band)
                        );
                }

                pt_result = pt_result + rayDirection * stepLength;
                totalLength += stepLength;
            }

            bool pt_found;
            //  If the T - SDF value is negative after such a trilinear interpolation, the surface
            //  has indeed been found and we terminate the ray, performing one last
            //  trilinear interpolation step for a smoother appearance.
            if (sdfValue <= 0.0f)
            {
                // Refine position
                stepLength = sdfValue * stepScale;
                pt_result = pt_result + rayDirection * stepLength;

                // Read again
                sdfValue = readFromSDF_float_interpolated(pt_result.location, hash_found);
                // Refine position
                stepLength = sdfValue * stepScale;
                pt_result = pt_result + rayDirection * stepLength;

                pt_found = true;
            }
            else pt_found = false;

            raycastResult->image->GetData()[locId] = Vector4f(pt_result.location, (pt_found) ? 1.0f : 0.0f);
            assert(raycastResult->pointCoordinates == voxelCoordinates);
            assert(pt_result.coordinateSystem == voxelCoordinates);
        }
    };

    /// Compute normal in the distance field via the gradient.
    /// c.f. computeSingleNormalFromSDF
    GPU_ONLY inline void computeNormalAndAngle(
        bool & foundPoint, //!< [in,out]
        const Vector3f & point, //!< [in]
        Vector3f& outNormal,//!< [out] 
        float& angle //!< [out] outNormal . towardsCamera
        )
    {
        if (!foundPoint) return;

        outNormal = normalize(computeSingleNormalFromSDF(point));

        angle = dot(outNormal, towardsCamera);
        // dont consider points not facing the camera (raycast will hit these, do backface culling now)
        if (!(angle > 0.0)) foundPoint = false;
    }


    // PIXEL SHADERS
    // " Finally a coloured or shaded rendering of the surface is trivially computed, as desired for the visualisation."

#define DRAWFUNCTION \
    GPU_ONLY static void draw(\
    /*out*/ DEVICEPTR(Vector4u) & dest,\
        const Vector3f & point, /* point is in voxel-fractional world coordinates, comes from raycastResult*/\
        const Vector3f & normal_obj, \
        const float & angle)

    struct renderGrey {
        DRAWFUNCTION{
            const float outRes = (0.8f * angle + 0.2f) * 255.0f;
            dest = Vector4u((uchar)outRes);
            dest.a = 255;
        }
    };

    struct renderColourFromNormal {
        DRAWFUNCTION{
            dest.r = (uchar)((0.3f + (normal_obj.r + 1.0f)*0.35f)*255.0f);
            dest.g = (uchar)((0.3f + (normal_obj.g + 1.0f)*0.35f)*255.0f);
            dest.b = (uchar)((0.3f + (normal_obj.b + 1.0f)*0.35f)*255.0f);

            dest.a = 255;
        }
    };

    struct renderColour {
        DRAWFUNCTION {
            const Vector3f clr = readFromSDF_color4u_interpolated(point);
            dest = Vector4u(TO_UCHAR3(clr), 255);
        }
    };

    template<typename T_DRAWFUNCTION>
    struct PROCESSFUNCTION {
        forEachPixelNoImage_process() {
            DEVICEPTR(Vector4u) &outRender = outRendering->image->GetData()[locId];
            Point voxelCoordinatePoint = raycastResult->getPointForPixel(Vector2i(x, y));
            assert(voxelCoordinatePoint.coordinateSystem == voxelCoordinates);

            const Vector3f point = voxelCoordinatePoint.location;

            float& outZ = outDepth->GetData()[locId];

            auto a = outRendering->eyeCoordinates->convert(voxelCoordinatePoint);
            outZ = a.location.z; /* in world / eye coordinates (distance) */

            bool foundPoint = raycastResult->image->GetData()[locId].w > 0;

            Vector3f outNormal;
            float angle;
            computeNormalAndAngle(foundPoint, point, outNormal, angle);
            if (foundPoint) {/*assert(outZ >= viewFrustum_min && outZ <= viewFrustum_max); -- approx*/
                T_DRAWFUNCTION::draw(outRender, point, outNormal, angle);
            }
            else {
                outRender = Vector4u((uchar)0); 
                outZ = 0;
            }
        }
    };


    /// Initializes raycastResult
    static void Common(
        const ITMPose pose,
        const ITMIntrinsics intrinsics
        ) {
        Vector2i imgSize = intrinsics.imageSize();
        assert(imgSize.area() > 1);
        auto raycastImage = new ITMFloat4Image(imgSize);
        auto invPose_M = pose.GetInvM();
        auto cameraCs = new CoordinateSystem(invPose_M);
        raycastResult = new PointImage(
            raycastImage,
            voxelCoordinates,
            cameraCs,
            intrinsics
            );

        // (negative camera z axis)
        towardsCamera = -Vector3f(invPose_M.getColumn(2));

        forEachPixelNoImage<castRay>(imgSize);
    }

    struct Camera {
    public:
        ITMPose pose;
        ITMIntrinsics intrinsics;
    };

    /** Render an image using raycasting. */
    ITMView* RenderImage(const ITMPose pose, const ITMIntrinsics intrinsics,
        const string shader // any of the DRAWFUNCTION
        )
    {
        const Vector2i imgSize = intrinsics.imageSize();
        assert(imgSize.area() > 1);

        ITMRGBDCalib* outCalib = new ITMRGBDCalib();
        outCalib->intrinsics_d = outCalib->intrinsics_rgb = intrinsics;
        auto outView = new ITMView(outCalib);
        outView->ChangePose(pose.GetM());
        rendering::outDepth = outView->depthImage->image;
        assert(rendering::outDepth);
        assert(rendering::outDepth->noDims == imgSize);

        auto outImage = new ITMUChar4Image(imgSize);
        auto outCs = new CoordinateSystem(pose.GetInvM());
        outRendering = outView->colorImage;

        assert(outRendering->imgSize() == intrinsics.imageSize());
        Common(pose, intrinsics);
        cudaDeviceSynchronize(); // want to read imgSize

#define isShader(s) if (shader == #s) {forEachPixelNoImage<PROCESSFUNCTION<s>>(outRendering->imgSize());cudaDeviceSynchronize(); return outView;}
        isShader(renderColour);
        isShader(renderColourFromNormal);
        isShader(renderGrey);
        fatalError("unkown shader %s", shader.c_str());
        return nullptr;
    }

    /// Computing the surface normal in image space given raycasted image (raycastResult).
    ///
    /// In image space, since the normals are computed on a regular grid,
    /// there are only 4 uninterpolated read operations followed by a cross-product.
    /// (here we might do more when useSmoothing is true, and we step 2 pixels wide to find // //further-away neighbors)
    ///
    /// \returns normal_out[idx].w = sigmaZ_out[idx] = -1 on error where idx = x + y * imgDims.x
    template <bool useSmoothing>
    GPU_ONLY inline void computeNormalImageSpace(
        bool& foundPoint, //!< [in,out] Set to false when the normal cannot be computed
        const int &x, const int&y,
        Vector3f & outNormal
        )
    {
        if (!foundPoint) return;
        const Vector2i imgSize = raycastResult->imgSize();

        // Lookup world coordinates of points surrounding (x,y)
        // and compute forward difference vectors
        Vector4f xp1_y, xm1_y, x_yp1, x_ym1;
        Vector4f diff_x(0.0f, 0.0f, 0.0f, 0.0f), diff_y(0.0f, 0.0f, 0.0f, 0.0f);

        // If useSmoothing, use positions 2 away
        int extraDelta = useSmoothing ? 1 : 0;

#define d(x) (x + extraDelta)

        if (y <= d(1) || y >= imgSize.y - d(2) || x <= d(1) || x >= imgSize.x - d(2)) { foundPoint = false; return; }

#define lookupNeighbors() \
    xp1_y = sampleNearest(raycastResult->image->GetData(), x + d(1), y, imgSize);\
    x_yp1 = sampleNearest(raycastResult->image->GetData(), x, y + d(1), imgSize);\
    xm1_y = sampleNearest(raycastResult->image->GetData(), x - d(1), y, imgSize);\
    x_ym1 = sampleNearest(raycastResult->image->GetData(), x, y - d(1), imgSize);\
    diff_x = xp1_y - xm1_y;\
    diff_y = x_yp1 - x_ym1;

        lookupNeighbors();

#define isAnyPointIllegal() (xp1_y.w <= 0 || x_yp1.w <= 0 || xm1_y.w <= 0 || x_ym1.w <= 0)

        float length_diff = MAX(length2(diff_x.toVector3()), length2(diff_y.toVector3()));
        bool lengthDiffTooLarge = (length_diff * voxelSize * voxelSize > (0.15f * 0.15f));

        if (isAnyPointIllegal() || (lengthDiffTooLarge && useSmoothing)) {
            if (!useSmoothing) { foundPoint = false; return; }

            // In case we used smoothing, try again without extra delta
            extraDelta = 0;
            lookupNeighbors();

            if (isAnyPointIllegal()){ foundPoint = false; return; }
        }

#undef d
#undef isAnyPointIllegal
#undef lookupNeighbors

        // TODO why the extra minus? -- it probably does not matter because we compute the distance to a plane which would be the same with the inverse normal
        outNormal = normalize(-cross(diff_x.toVector3(), diff_y.toVector3()));

        float angle = dot(outNormal, towardsCamera);
        // dont consider points not facing the camera (raycast will hit these, do backface culling now)
        if (!(angle > 0.0)) foundPoint = false;
    }

#define useSmoothing true

    static __managed__ RayImage* outIcpMap = 0;
    /// Produces a shaded image (outRendering) and a point cloud for e.g. tracking.
    /// Uses image space normals.
    /// \param useSmoothing whether to compute normals by forward differences two pixels away (true) or just one pixel away (false)
    struct processPixelICP {
        forEachPixelNoImage_process() {
            const Vector4f point = raycastResult->image->GetData()[locId];
            assert(raycastResult->pointCoordinates == voxelCoordinates);

            bool foundPoint = point.w > 0.0f;

            Vector3f outNormal;
            // TODO could we use the world space normals here? not without change
            computeNormalImageSpace<useSmoothing>(
                foundPoint, x, y, outNormal);

#define pointsMap outIcpMap->image->GetData()
#define normalsMap outIcpMap->normalImage->GetData()

            if (!foundPoint)
            {
                pointsMap[locId] = normalsMap[locId] = IllegalColor<Vector4f>::make();
                return;
            }

            // Convert point to world coordinates
            pointsMap[locId] = Vector4f(point.toVector3() * voxelSize, 1);
            // Normals are the same whether in world or voxel coordinates
            normalsMap[locId] = Vector4f(outNormal, 0);
#undef pointsMap
#undef normalsMap
        }
    };

    // 1. raycast scene from current viewpoint 
    // to create point cloud for tracking
    RayImage * CreateICPMapsForCurrentView() {
        assert(currentView);

        auto imgSize_d = currentView->depthImage->imgSize();
        assert(imgSize_d.area() > 1);
        auto pointsMap = new ITMFloat4Image(imgSize_d);
        auto normalsMap = new ITMFloat4Image(imgSize_d);

        assert(!outIcpMap);
        outIcpMap = new RayImage(
            pointsMap,
            normalsMap,
            CoordinateSystem::global(),

            currentView->depthImage->eyeCoordinates,
            currentView->depthImage->cameraIntrinsics
            );

        assert(Scene::getCurrentScene());

        // TODO reduce conversion friction
        ITMPose pose; pose.SetM(currentView->depthImage->eyeCoordinates->fromGlobal);
        ITMIntrinsics intrin = currentView->calib->intrinsics_d;
        assert(intrin.imageSize() == imgSize_d);
        assert(intrin.all == currentView->depthImage->cameraIntrinsics.all);
        assert(intrin.imageSize() == currentView->depthImage->cameraIntrinsics.imageSize());
        Common(
            pose, //trackingState->pose_d,
            intrin
            );
        cudaDeviceSynchronize();

        approxEqual(raycastResult->eyeCoordinates->fromGlobal, currentView->depthImage->eyeCoordinates->fromGlobal);
        assert(raycastResult->pointCoordinates == voxelCoordinates);

        // Create ICP maps
        forEachPixelNoImage<processPixelICP>(imgSize_d);
        cudaDeviceSynchronize();

        // defensive
        assert(outIcpMap->eyeCoordinates == currentView->depthImage->eyeCoordinates);
        assert(outIcpMap->pointCoordinates == CoordinateSystem::global());
        assert(outIcpMap->imgSize() == imgSize_d);
        assert(outIcpMap->normalImage->noDims == imgSize_d);
        auto icpMap = outIcpMap;
        outIcpMap = 0;
        return icpMap;
    }

}
using namespace rendering;





































namespace fusion {


#define weightedCombine(oldX, oldW, newX, newW) \
    newX = (float)oldW * oldX + (float)newW * newX; \
    newW = oldW + newW;\
    newX /= (float)newW;\
    newW = MIN(newW, maxW);

    CPU_AND_GPU inline void updateVoxelColorInformation(
        DEVICEPTR(ITMVoxel) & voxel,
        const Vector3f oldC, const int oldW, Vector3f newC, int newW)
    {
        weightedCombine(oldC, oldW, newC, newW);

        // write back
        /// C(X) <-  
        voxel.clr = TO_UCHAR3(newC);
        voxel.w_color = (uchar)newW;
    }

    CPU_AND_GPU inline void updateVoxelDepthInformation(
        DEVICEPTR(ITMVoxel) & voxel,
        const float oldF, const int oldW, float newF, int newW)
    {
        weightedCombine(oldF, oldW, newF, newW);

        // write back
        /// D(X) <-  (4)
        voxel.setSDF(newF);
        voxel.w_depth = (uchar)newW;
    }
#undef weightedCombine

    /// Fusion Stage - Camera Data Integration
    /// \returns \f$\eta\f$, -1 on failure
    // Note that the stored T-SDF values are normalized to lie
    // in [-1,1] within the truncation band.
    GPU_ONLY inline float computeUpdatedVoxelDepthInfo(
        DEVICEPTR(ITMVoxel) &voxel, //!< X
        const Point & pt_model //!< in world space
        )
    {

        // project point into depth image
        /// X_d, depth camera coordinate system
        const Vector4f pt_camera = Vector4f(
            currentView->depthImage->eyeCoordinates->convert(pt_model).location,
            1);
        /// \pi(K_dX_d), projection into the depth image
        Vector2f pt_image;
        if (!currentView->depthImage->project(pt_model, pt_image))
            return -1;

        // get measured depth from image, no interpolation
        /// I_d(\pi(K_dX_d))
        auto p = currentView->depthImage->getPointForPixel(pt_image.toInt());
        const float depth_measure = p.location.z;
        if (depth_measure <= 0.0) return -1;

        /// I_d(\pi(K_dX_d)) - X_d^(z)          (3)
        float const eta = depth_measure - pt_camera.z;
        // check whether voxel needs updating
        if (eta < -mu) return eta;

        // compute updated SDF value and reliability (number of observations)
        /// D(X), w(X)
        float const oldF = voxel.getSDF();
        int const oldW = voxel.w_depth;

        // newF, normalized for -1 to 1
        float const newF = MIN(1.0f, eta / mu);
        int const newW = 1;

        updateVoxelDepthInformation(
            voxel,
            oldF, oldW, newF, newW);

        return eta;
    }

    /// \returns early on failure
    GPU_ONLY inline void computeUpdatedVoxelColorInfo(
        DEVICEPTR(ITMVoxel) &voxel,
        const Point & pt_model)
    {
        Vector2f pt_image;
        if (!currentView->colorImage->project(pt_model, pt_image))
            return;

        int oldW = (float)voxel.w_color;
        const Vector3f oldC = TO_FLOAT3(voxel.clr);

        /// Like formula (4) for depth
        const Vector3f newC = TO_VECTOR3(interpolateBilinear<Vector4f>(currentView->colorImage->image->GetData(), pt_image, currentView->colorImage->imgSize()));
        int newW = 1;

        updateVoxelColorInformation(
            voxel,
            oldC, oldW, newC, newW);
    }


    GPU_ONLY static void computeUpdatedVoxelInfo(
        DEVICEPTR(ITMVoxel) & voxel, //!< [in, out] updated voxel
        const Point & pt_model) {
        const float eta = computeUpdatedVoxelDepthInfo(voxel, pt_model);

        // Only the voxels within +- 25% mu of the surface get color
        if ((eta > mu) || (fabs(eta / mu) > 0.25f)) return;
        computeUpdatedVoxelColorInfo(voxel, pt_model);
    }

    /// Determine the blocks around a given depth sample that are currently visible
    /// and need to be allocated.
    /// Builds hashVisibility and entriesAllocType.
    /// \param x,y [in] loop over depth image.
    struct buildHashAllocAndVisibleTypePP {
        forEachPixelNoImage_process() {
            // Find 3d position of depth pixel xy, in eye coordinates
            auto pt_camera = currentView->depthImage->getPointForPixel(Vector2i(x, y));

            const float depth = pt_camera.location.z;
            if (depth <= 0 || (depth - mu) < 0 || (depth - mu) < viewFrustum_min || (depth + mu) > viewFrustum_max) return;

            // the found point +- mu
            const Vector pt_camera_v = (pt_camera - currentView->depthImage->location());
            const float norm = length(pt_camera_v.direction);
            const Vector pt_camera_v_minus_mu = pt_camera_v*(1.0f - mu / norm);
            const Vector pt_camera_v_plus_mu = pt_camera_v*(1.0f + mu / norm);

            // Convert to voxel block coordinates  
            // the initial point pt_camera_v_minus_mu
            Point point = voxelBlockCoordinates->convert(currentView->depthImage->location() + pt_camera_v_minus_mu);
            // the direction towards pt_camera_v_plus_mu in voxelBlockCoordinates
            const Vector vector = voxelBlockCoordinates->convert(pt_camera_v_plus_mu - pt_camera_v_minus_mu);

            // We will step along point -> point_e and add all voxel blocks we encounter to the visible list
            // "Create a segment on the line of sight in the range of the T-SDF truncation band"
            const int noSteps = (int)ceil(2.0f* length(vector.direction)); // make steps smaller than 1, maybe even < 1/2 to really land in all blocks at least once
            const Vector direction = vector * (1.f / (float)(noSteps - 1));

            //add neighbouring blocks
            for (int i = 0; i < noSteps; i++)
            {
                // "take the block coordinates of voxels on this line segment"
                const VoxelBlockPos blockPos = TO_SHORT_FLOOR3(point.location);
                Scene::requestCurrentSceneVoxelBlockAllocation(blockPos);

                point = point + direction;
            }
        }
    };

    struct IntegrateVoxel {
        doForEachAllocatedVoxel_process() {
            computeUpdatedVoxelInfo(*v, globalPoint);
        }
    };


    /// Fusion stage of the system, depth integration process
    void Fuse()
    {
        cudaDeviceSynchronize();
        assert(Scene::getCurrentScene());
        assert(currentView);

        // allocation request
        forEachPixelNoImage<buildHashAllocAndVisibleTypePP>(currentView->depthImage->imgSize());
        cudaDeviceSynchronize();

        // allocation
        Scene::performCurrentSceneAllocations();

        // camera data integration
        cudaDeviceSynchronize();
        Scene::getCurrentScene()->doForEachAllocatedVoxel<IntegrateVoxel>();
    }



}
using namespace fusion;
















namespace tracking {



    /** Performing ICP based depth tracking.
    Implements the original KinectFusion tracking algorithm.

    c.f. newcombe_etal_ismar2011.pdf section "Sensor Pose Estimation"

    6-d parameter vector "x" is (beta, gamma, alpha, tx, ty, tz)
    */
    void ImprovePose();
    /** \file c.f. newcombe_etal_ismar2011.pdf
    * T_{g,k} denotes the transformation from frame k's view space to global space
    * T_{k,g} is the inverse
    */
    /// \file Depth Tracker, c.f. newcombe_etal_ismar2011.pdf Sensor Pose Estimation
    // The current implementation ignores the possible optimizations/special iterations with 
    // rotation estimation only ("At the coarser levels we optimise only for the rotation matrix R.")

    struct AccuCell : public Managed {
        int noValidPoints;
        float f;
        // ATb
        float ATb[6];
        // AT_A (note that this is actually a symmetric matrix, so we could save some effort and memory)
        float AT_A[6][6];
        void reset() {
            memset(this, 0, sizeof(AccuCell));
        }
    };

    /// The tracker iteration type used to define the tracking iteration regime
    enum TrackerIterationType
    {
        /// Update only the current rotation estimate. This is preferable for the coarse solution stages.
        TRACKER_ITERATION_ROTATION = 1,
        TRACKER_ITERATION_BOTH = 3,
        TRACKER_ITERATION_NONE = 4
    };
    struct TrackingLevel : public Managed {
        /// FilterSubsampleWithHoles result of one level higher
        /// Half of the intrinsics of one level higher
        /// Coordinate system is defined by the matrix M_d (this is the world-to-eye transform, i.e. 'fromGlobal')
        /// which we are optimizing for.
        DepthImage* depthImage;

        // Tweaking
        const float distanceThreshold;
        const int numberOfIterations;
        const TrackerIterationType iterationType;

        TrackingLevel(int numberOfIterations, TrackerIterationType iterationType, float distanceThreshold) :
            numberOfIterations(numberOfIterations), iterationType(iterationType), distanceThreshold(distanceThreshold),
            depthImage(0) {
        }
    };
    // ViewHierarchy, 0 is highest resolution
    static std::vector<TrackingLevel*> trackingLevels;
    struct ITMDepthTracker_
    {
        ITMDepthTracker_() {
            // Tweaking
            // Tracking strategy:
            const int noHierarchyLevels = 5;
            const float distThreshStep = depthTrackerICPMaxThreshold / noHierarchyLevels;
            // starting with highest resolution (lowest level, last to be executed)
#define iterations
            trackingLevels.push_back(new TrackingLevel(2  iterations, TRACKER_ITERATION_BOTH, depthTrackerICPMaxThreshold - distThreshStep * 4));
            trackingLevels.push_back(new TrackingLevel(4  iterations, TRACKER_ITERATION_BOTH, depthTrackerICPMaxThreshold - distThreshStep * 3));
            trackingLevels.push_back(new TrackingLevel(6  iterations, TRACKER_ITERATION_ROTATION, depthTrackerICPMaxThreshold - distThreshStep * 2));
            trackingLevels.push_back(new TrackingLevel(8  iterations, TRACKER_ITERATION_ROTATION, depthTrackerICPMaxThreshold - distThreshStep));
            trackingLevels.push_back(new TrackingLevel(10 iterations, TRACKER_ITERATION_ROTATION, depthTrackerICPMaxThreshold));
            assert(trackingLevels.size() == noHierarchyLevels);
#undef iterations
        }
    } _;

    static __managed__ /*const*/ TrackingLevel* currentTrackingLevel;

    static TrackerIterationType iterationType() {
        return currentTrackingLevel->iterationType;
    }
    static bool shortIteration() {
        return (iterationType() == TRACKER_ITERATION_ROTATION);
    }
    /// In world-coordinates squared
    //!< \f$\epsilon_d\f$
    GPU_ONLY static float distThresh() {
        return currentTrackingLevel->distanceThreshold;
    }

    static __managed__ /*const*/ AccuCell accu;
    /// In world coordinates, points map, normals map, for frame k-1, \f$V_{k-1}\f$
    static __managed__ DEVICEPTR(RayImage) * lastFrameICPMap = 0;


    /**
    Computes
    \f{eqnarray*}{
    b &:=& n_{k-1}^\top(p_{k-1} - p_k)  \\
    A^T &:=& G(u)^T . n_{k-1}\\
    \f}

    where \f$G(u) = [ [p_k]_\times \;|\; Id ]\f$ a 3 x 6 matrix and \f$A^T\f$ is a 6 x 1 column vector.

    \f$p_{k-1}\f$ is the point observed in the last frame in
    the direction in which \f$p_k\f$ is observed (projective data association).

    \f$n_{k-1}\f$ is the normal that was observed at that location

    \f$b\f$ is the point-plane alignment energy for the point under consideration

    \param x,y \f$\mathbf u\f$
    \return false on failure
    \see newcombe_etal_ismar2011.pdf Sensor Pose Estimation
    */
    GPU_ONLY static inline bool computePerPointGH_Depth_Ab(
        float AT[6], //!< [out]
        float &b,//!< [out]
        const int x, const int y
        )
    {
        // p_k := T_{g,k}V_k(u) = V_k^g(u)
        Point V_ku = currentTrackingLevel->depthImage->getPointForPixel(Vector2i(x, y));
        if (V_ku.location.z <= 1e-8f) return false;
        assert(V_ku.coordinateSystem == currentTrackingLevel->depthImage->eyeCoordinates);
        Point p_k = CoordinateSystem::global()->convert(V_ku);

        // hat_u = \pi(K T_{k-1,g} T_{g,k}V_k(u) )
        Vector2f hat_u;
        if (!lastFrameICPMap->project(
            p_k,
            hat_u,
            EXTRA_BOUNDS))
            return false;

        bool isIllegal = false;
        Ray ray = lastFrameICPMap->getRayForPixelInterpolated(hat_u, isIllegal);
        if (isIllegal) return false;

        // p_km1 := V_{k-1}(\hat u)
        const Point p_km1 = ray.origin;

        // n_km1 := N_{k-1}(\hat u)
        const Vector n_km1 = ray.direction;

        // d := p_km1 - p_k
        const Vector d = p_km1 - p_k;

        // [
        // Projective data assocation rejection test, "\Omega_k(u) != 0"
        // TODO check whether normal matches normal from image, done in the original paper, but does not seem to be required
        if (length2(d.direction) > distThresh()) return false;
        // ]

        // (2) Point-plane ICP computations

        // b = n_km1 . (p_km1 - p_k)
        b = n_km1.dot(d);

        // Compute A^T = G(u)^T . n_{k-1}
        // Where G(u) = [ [p_k]_x Id ] a 3 x 6 matrix
        // [v]_x denotes the skew symmetric matrix such that for all w, [v]_x w = v \cross w
        int counter = 0;
        {
            const Vector3f pk = p_k.location;
            const Vector3f nkm1 = n_km1.direction;
            // rotationPart
            AT[counter++] = +pk.z * nkm1.y - pk.y * nkm1.z;
            AT[counter++] = -pk.z * nkm1.x + pk.x * nkm1.z;
            AT[counter++] = +pk.y * nkm1.x - pk.x * nkm1.y;
            // translationPart
            AT[counter++] = nkm1.x;
            AT[counter++] = nkm1.y;
            AT[counter++] = nkm1.z;
        }

        return true;
    }


#define REDUCE_BLOCK_SIZE 256 // must be power of 2. Used for reduction of a sum.
    static KERNEL depthTrackerOneLevel_g_rt_device_main()
    {
        int x = threadIdx.x + blockIdx.x * blockDim.x, y = threadIdx.y + blockIdx.y * blockDim.y;

        int locId_local = threadIdx.x + threadIdx.y * blockDim.x;

        __shared__ bool should_prefix; // set to true if any point is valid

        should_prefix = false;
        __syncthreads();

        float A[6];
        float b;
        bool isValidPoint = false;

        auto viewImageSize = currentTrackingLevel->depthImage->imgSize();
        if (x < viewImageSize.width && y < viewImageSize.height
            )
        {
            isValidPoint = computePerPointGH_Depth_Ab(
                A, b, x, y);
            if (isValidPoint) should_prefix = true;
        }

        if (!isValidPoint) {
            for (int i = 0; i < 6; i++) A[i] = 0.0f;
            b = 0.0f;
        }

        __syncthreads();

        if (!should_prefix) return;

        __shared__ float dim_shared1[REDUCE_BLOCK_SIZE];

        { //reduction for noValidPoints
            warpReduce256<int>(
                isValidPoint,
                dim_shared1,
                locId_local,
                &(accu.noValidPoints));
        }
#define reduce(what, into) warpReduce256<float>((what),dim_shared1,locId_local,&(into));
    { //reduction for energy function value
        reduce(b*b, accu.f);
    }

    //reduction for nabla
    for (unsigned char paraId = 0; paraId < 6; paraId++)
    {
        reduce(b*A[paraId], accu.ATb[paraId]);
    }

    float AT_A[6][6];
    int counter = 0;
    for (int r = 0; r < 6; r++)
    {
        for (int c = 0; c < 6; c++) {
            AT_A[r][c] = A[r] * A[c];

            //reduction for hessian
            reduce(AT_A[r][c], accu.AT_A[r][c]);
        }
    }
    }

    // host methods

    AccuCell ComputeGandH(Matrix4f T_g_k_estimate) {
        cudaDeviceSynchronize(); // prepare writing to __managed__

        assert(lastFrameICPMap->pointCoordinates == CoordinateSystem::global());
        assert(!(lastFrameICPMap->eyeCoordinates == CoordinateSystem::global()));
        assert(lastFrameICPMap->eyeCoordinates == currentView->depthImage->eyeCoordinates);

        //::depth = currentTrackingLevel->depth->GetData(MEMORYDEVICE_CUDA);
        //::viewIntrinsics = currentTrackingLevel->intrinsics;
        auto viewImageSize = currentTrackingLevel->depthImage->imgSize();

        //::T_g_k = T_g_k_estimate;
        std::auto_ptr<CoordinateSystem> depthCoordinateSystemEstimate(new CoordinateSystem(T_g_k_estimate)); // TODO should this be deleted when going out of scope?
        // do we really need to recreate it every time? Should it be the same instance ('new depth eye coordinate system') for all resolutions?
        currentTrackingLevel->depthImage->eyeCoordinates = depthCoordinateSystemEstimate.get();

        dim3 blockSize(16, 16); // must equal REDUCE_BLOCK_SIZE
        assert(16 * 16 == REDUCE_BLOCK_SIZE);

        dim3 gridSize(
            (int)ceil((float)viewImageSize.x / (float)blockSize.x),
            (int)ceil((float)viewImageSize.y / (float)blockSize.y));

        assert(!(currentTrackingLevel->depthImage->eyeCoordinates == CoordinateSystem::global()));

        accu.reset();
        LAUNCH_KERNEL(depthTrackerOneLevel_g_rt_device_main, gridSize, blockSize);

        cudaDeviceSynchronize(); // for later access of accu
        return accu;
    }

    /// evaluate error function at the supplied T_g_k_estimate, 
    /// compute sum_ATb and sum_AT_A, the system we need to solve to compute the
    /// next update step (note: this system is not yet solved and we don't know the new energy yet!)
    /// \returns noValidPoints
    int ComputeGandH(
        float &f,
        float sum_ATb[6],
        float sum_AT_A[6][6],
        Matrix4f T_g_k_estimate) {
        AccuCell accu = ComputeGandH(T_g_k_estimate);

        memcpy(sum_ATb, accu.ATb, sizeof(float) * 6);
        assert(sum_ATb[4] == accu.ATb[4]);
        memcpy(sum_AT_A, accu.AT_A, sizeof(float) * 6 * 6);
        assert(sum_AT_A[3][4] == accu.AT_A[3][4]);

        // Output energy -- if we have very few points, output some high energy
        f = (accu.noValidPoints > 100) ? sqrt(accu.f) / accu.noValidPoints : 1e5f;

        return accu.noValidPoints;
    }

    /// Solves hessian.step = nabla
    /// \param delta output array of 6 floats 
    /// \param hessian 6x6
    /// \param delta 3 or 6
    /// \param nabla 3 or 6
    /// \param shortIteration whether there are only 3 parameters
    void ComputeDelta(float step[6], float nabla[6], float hessian[6][6])
    {
        for (int i = 0; i < 6; i++) step[i] = 0;

        if (shortIteration())
        {
            // Keep only upper 3x3 part of hessian
            float smallHessian[3][3];
            for (int r = 0; r < 3; r++) for (int c = 0; c < 3; c++) smallHessian[r][c] = hessian[r][c];

            Cholesky::solve((float*)smallHessian, 3, nabla, step);

            // check
            /*float result[3];
            matmul((float*)smallHessian, step, result, 3, 3);
            for (int r = 0; r < 3; r++)
            assert(abs(result[r] - nabla[r]) / abs(result[r]) < 0.0001);
            */
        }
        else
        {
            Cholesky::solve((float*)hessian, 6, nabla, step);
        }
    }

    bool HasConverged(float *step)
    {
        // Compute ||step||_2^2
        float stepLength = 0.0f;
        for (int i = 0; i < 6; i++) stepLength += step[i] * step[i];

        // heuristic? Why /6?
        if (sqrt(stepLength) / 6 < depthTrackerTerminationThreshold) return true; //converged

        return false;
    }

    Matrix4f ComputeTinc(const float delta[6])
    {
        // step is T_inc, expressed as a parameter vector 
        // (beta, gamma, alpha, tx,ty, tz)
        // beta, gamma, alpha parametrize the rotation axis and angle
        float step[6];

        // Depending on the iteration type, fill in 0 for values that where not computed.
        switch (currentTrackingLevel->iterationType)
        {
        case TRACKER_ITERATION_ROTATION:
            step[0] = (float)(delta[0]); step[1] = (float)(delta[1]); step[2] = (float)(delta[2]);
            step[3] = 0.0f; step[4] = 0.0f; step[5] = 0.0f;
            break;
        default:
        case TRACKER_ITERATION_BOTH:
            step[0] = (float)(delta[0]); step[1] = (float)(delta[1]); step[2] = (float)(delta[2]);
            step[3] = (float)(delta[3]); step[4] = (float)(delta[4]); step[5] = (float)(delta[5]);
            break;
        }

        // Incremental pose update assuming small angles.
        // c.f. (18) in newcombe_etal_ismar2011.pdf
        // step = (beta, gamma, alpha, tx, ty, tz)
        // Tinc = 
        /*
        1       alpha   -gamma tx
        -alpha      1     beta ty
        gamma   -beta        1 tz
        i.e.

        1         step[2]   -step[1] step[3]
        -step[2]        1    step[0] step[4]
        step[1]  -step[0]          1 step[5]
        */
        Matrix4f Tinc;

        Tinc.m00 = 1.0f;		Tinc.m10 = step[2];		Tinc.m20 = -step[1];	Tinc.m30 = step[3];
        Tinc.m01 = -step[2];	Tinc.m11 = 1.0f;		Tinc.m21 = step[0];		Tinc.m31 = step[4];
        Tinc.m02 = step[1];		Tinc.m12 = -step[0];	Tinc.m22 = 1.0f;		Tinc.m32 = step[5];
        Tinc.m03 = 0.0f;		Tinc.m13 = 0.0f;		Tinc.m23 = 0.0f;		Tinc.m33 = 1.0f;
        return Tinc;
    }

    /** Performing ICP based depth tracking.
    Implements the original KinectFusion tracking algorithm.

    c.f. newcombe_etal_ismar2011.pdf section "Sensor Pose Estimation"

    6-d parameter vector "x" is (beta, gamma, alpha, tx, ty, tz)
    */
    /// \file c.f. newcombe_etal_ismar2011.pdf, Sensor Pose Estimation section
    void ImprovePose() {
        assert(currentView);
        //assert(!lastFrameICPMap);
        lastFrameICPMap = rendering::CreateICPMapsForCurrentView();

        /// Initialize one tracking event base data. Init hierarchy level 0 (finest).
        cudaDeviceSynchronize(); // prepare writing to __managed__

        /// Init image hierarchy levels
        assert(currentView->depthImage->imgSize().area() > 1);
        trackingLevels[0]->depthImage = //currentView->depthImage;
            new DepthImage(
            currentView->depthImage->image,
            new CoordinateSystem(*currentView->depthImage->eyeCoordinates),
            currentView->depthImage->cameraIntrinsics
            );

        for (int i = 1; i < trackingLevels.size(); i++)
        {
            TrackingLevel* currentLevel = trackingLevels[i];
            TrackingLevel* previousLevel = trackingLevels[i - 1];

            auto subsampledDepthImage = new ITMFloatImage();
            FilterSubsampleWithHoles(subsampledDepthImage, previousLevel->depthImage->image);
            cudaDeviceSynchronize();

            ITMIntrinsics subsampledIntrinsics;
            subsampledIntrinsics.imageSize(subsampledDepthImage->noDims);
            subsampledIntrinsics.all = previousLevel->depthImage->projParams() * 0.5;

            currentLevel->depthImage = new DepthImage(
                subsampledDepthImage,
                CoordinateSystem::global(), // will be set correctly later
                subsampledIntrinsics
                );

            assert(currentLevel->depthImage->imgSize() == previousLevel->depthImage->imgSize() / 2);
            assert(currentLevel->depthImage->imgSize().area() < currentView->depthImage->imgSize().area());
        }

        ITMPose T_k_g_estimate;
        T_k_g_estimate.SetM(currentView->depthImage->eyeCoordinates->fromGlobal);
        {
            Matrix4f M_d = T_k_g_estimate.GetM();
            assert(M_d == currentView->depthImage->eyeCoordinates->fromGlobal);
        }
        // Coarse to fine
        for (int levelId = trackingLevels.size() - 1; levelId >= 0; levelId--)
        {
            currentTrackingLevel = trackingLevels[levelId];
            if (iterationType() == TRACKER_ITERATION_NONE) continue;

            // T_{k,g} transforms global (g) coordinates to eye or view coordinates of the k-th frame
            // T_g_k_estimate caches T_k_g_estimate->GetInvM()
            Matrix4f T_g_k_estimate = T_k_g_estimate.GetInvM();

#define set_T_k_g_estimate(x)\
T_k_g_estimate.SetFrom(&x);
            T_g_k_estimate = T_k_g_estimate.GetInvM();

#define set_T_k_g_estimate_from_T_g_k_estimate(x) \
T_k_g_estimate.SetInvM(x);\
T_k_g_estimate.Coerce(); /* and make sure we've got an SE3*/\
T_g_k_estimate = T_k_g_estimate.GetInvM();

            // We will 'accept' updates into trackingState->pose_d and T_g_k_estimate
            // before we know whether they actually decrease the energy.
            // When they did not in fact, we will revert to this value that was known to have less energy 
            // than all previous estimates.
            ITMPose least_energy_T_k_g_estimate(T_k_g_estimate);

            // Track least energy we measured so far to see whether we improved
            float f_old = 1e20f;

            // current levenberg-marquart style damping parameter, often called mu.
            float lambda = 1.0;

            // Iterate as required
            for (int iterNo = 0; iterNo < currentTrackingLevel->numberOfIterations; iterNo++)
            {
                // [ this takes most time. 
                // Computes f(x) as well as A^TA and A^Tb for next computation of delta_x as
                // (A^TA + lambda * diag(A^TA)) delta_x = A^T b
                // if f decreases, the delta is applied definitely, otherwise x is reset.
                // So we do:
                /*
                x = x_best;
                lambda = 1;
                f_best = infinity

                repeat:
                compute f_new, A^TA_new, A^T b_new

                if (f_new > f_best) {x = x_best; lambda *= 10;}
                else {
                x_best = x;
                A^TA = A^TA_new
                A^Tb = A^Tb_new
                }

                solve (A^TA + lambda * diag(A^TA)) delta_x = A^T b
                x += delta_x;

                */


                // evaluate error function at currently accepted
                // T_g_k_estimate
                // and compute information for next update
                float f_new;
                int noValidPoints;
                float new_sum_ATb[6];
                float new_sum_AT_A[6][6];
                noValidPoints = ComputeGandH(f_new, new_sum_ATb, new_sum_AT_A, T_g_k_estimate);
                // ]]

                float least_energy_sum_AT_A[6][6],
                    damped_least_energy_sum_AT_A[6][6];
                float least_energy_sum_ATb[6];

                // check if energy actually *increased* with the last update
                // Note: This happens rarely, namely when the blind 
                // gauss-newton step actually leads to an *increase in energy
                // because the damping was too small
                if ((noValidPoints <= 0) || (f_new > f_old)) {
                    // If so, revert pose and discard/ignore new_sum_AT_A, new_sum_ATb
                    // TODO would it be worthwhile to not compute these when they are not going to be used?
                    set_T_k_g_estimate(least_energy_T_k_g_estimate);
                    // Increase damping, then solve normal equations again with old matrix (see below)
                    lambda *= 10.0f;
                }
                else {
                    f_old = f_new;
                    least_energy_T_k_g_estimate.SetFrom(&T_k_g_estimate);

                    // Prepare to solve a new system

                    // Preconditioning: Normalize by noValidPoints
                    for (int i = 0; i < 6; ++i) for (int j = 0; j < 6; ++j) least_energy_sum_AT_A[i][j] = new_sum_AT_A[i][j] / noValidPoints;
                    for (int i = 0; i < 6; ++i) least_energy_sum_ATb[i] = new_sum_ATb[i] / noValidPoints;

                    // Accept and decrease damping
                    lambda /= 10.0f;
                }
                // Solve normal equations

                // Apply levenberg-marquart style damping (multiply diagonal of ATA by 1.0f + lambda)
                for (int i = 0; i < 6; ++i) for (int j = 0; j < 6; ++j) damped_least_energy_sum_AT_A[i][j] = least_energy_sum_AT_A[i][j];
                for (int i = 0; i < 6; ++i) damped_least_energy_sum_AT_A[i][i] *= 1.0f + lambda;

                // compute the update step parameter vector x
                float x[6];
                ComputeDelta(x,
                    least_energy_sum_ATb,
                    damped_least_energy_sum_AT_A);

                // Apply the corresponding Tinc
                set_T_k_g_estimate_from_T_g_k_estimate(
                    /* T_g_k_estimate = */
                    ComputeTinc(x) * T_g_k_estimate
                    );

                // if step is small, assume it's going to decrease the error and finish
                if (HasConverged(x)) break;
            }
        }

        //delete lastFrameICPMap;
        //lastFrameICPMap = 0;

        // Apply new guess
        Matrix4f M_d = T_k_g_estimate.GetM();

        // DEBUG sanity check
        Matrix4f id; id.setIdentity();
        assert(M_d != id);

        cudaDeviceSynchronize(); // necessary here?
        assert(currentView->depthImage->eyeCoordinates);
        assert(M_d != currentView->depthImage->eyeCoordinates->fromGlobal);
        assert(&M_d);
        currentView->ChangePose(M_d); // TODO crashes in Release mode -- maybe relying on some uninitialized variable, or accessing while not cudaDeviceSynchronized
    }


}
using namespace tracking;
































void DepthToUchar4(ITMUChar4Image *dst, const ITMFloatImage *src)
{
    assert(src);
    assert(dst);
    assert(dst->noDims == src->noDims);
    Vector4u *dest = dst->GetData(MEMORYDEVICE_CPU);
    const float *source = src->GetData(MEMORYDEVICE_CPU);
    int dataSize = static_cast<int>(dst->dataSize);
    assert(dataSize > 1);
    memset(dst->GetData(MEMORYDEVICE_CPU), 0, dataSize * 4);

    Vector4u *destUC4;
    float lims[2], scale;

    destUC4 = (Vector4u*)dest;
    lims[0] = 100000.0f; lims[1] = -100000.0f;

    for (int idx = 0; idx < dataSize; idx++)
    {
        float sourceVal = source[idx]; // only depths greater than 0 are considered
        if (sourceVal > 0.0f) { lims[0] = MIN(lims[0], sourceVal); lims[1] = MAX(lims[1], sourceVal); }
    }

    scale = ((lims[1] - lims[0]) != 0) ? 1.0f / (lims[1] - lims[0]) : 1.0f / lims[1];

    if (lims[0] == lims[1])
        return;// assert(false);

    for (int idx = 0; idx < dataSize; idx++)
    {
        float sourceVal = source[idx];

        if (sourceVal > 0.0f)
        {
            sourceVal = (sourceVal - lims[0]) * scale;


            auto interpolate = [&](float val, float y0, float x0, float y1, float x1) {
                return (val - x0)*(y1 - y0) / (x1 - x0) + y0;
            };

            auto base = [&](float val) {
                if (val <= -0.75f) return 0.0f;
                else if (val <= -0.25f) return interpolate(val, 0.0f, -0.75f, 1.0f, -0.25f);
                else if (val <= 0.25f) return 1.0f;
                else if (val <= 0.75f) return interpolate(val, 1.0f, 0.25f, 0.0f, 0.75f);
                else return 0.0f;
            };

            destUC4[idx].r = (uchar)(base(sourceVal - 0.5f) * 255.0f);
            destUC4[idx].g = (uchar)(base(sourceVal) * 255.0f);
            destUC4[idx].b = (uchar)(base(sourceVal + 0.5f) * 255.0f);
            destUC4[idx].a = 255;
        }
    }
}









































/// c.f. chapter "Lighting Estimation with Signed Distance Fields"
namespace Lighting {

    struct LightingModel {
        static const int b2 = 9;

        /// \f[a \sum_{m = 1}^{b^2} l_m H_m(n)\f]
        /// \f$v\f$ is some voxel (inside the truncation band)
        // TODO wouldn't the non-refined voxels interfere with the updated, refined voxels, 
        // if we just cut them off hard from the computation?
        float getReflectedIrradiance(float albedo, //!< \f$a(v)\f$
            Vector3f normal //!< \f$n(v)\f$
            ) const {
            assert(albedo >= 0);
            float o = 0;
            for (int m = 0; m < b2; m++) {
                o += l[m] * sphericalHarmonicHi(m, normal);
            }
            return albedo * o;
        }

        // original paper uses svd to compute the solution to the linear system, but how this is done should not matter
        LightingModel(std::array<float, b2>& l) : l(l){
            assert(l[0] > 0); // constant term should be positive - otherwise the lighting will be negative in some places (?)
        }
        LightingModel(const LightingModel& m) : l(m.l){}

        static CPU_AND_GPU float sphericalHarmonicHi(int i, Vector3f n) {
            assert(i >= 0 && i < b2);
            switch (i) {
            case 0: return 1.f;
            case 1: return n.y;
            case 2: return n.z;
            case 3: return n.x;
            case 4: return n.x * n.y;
            case 5: return n.y * n.z;
            case 6: return -n.x * n.x - n.y * n.y + 2 * n.z * n.z;
            case 7: return n.z * n.x;
            case 8: return n.x - n.y * n.y;




            default: fatalError("sphericalHarmonicHi not defined for i = %d", i);
            }
            return 0;
        }


        const std::array<float, b2> l;

        OSTREAM(LightingModel) {
            for (auto & x : o.l) os << x << ", ";
            return os;
        }
    };

    /// for constructAndSolve
    struct ConstructLightingModelEquationRow {
        // Amount of columns, should be small
        static const unsigned int m = LightingModel::b2;

        /*not really needed */
        struct ExtraData {
            // User specified payload to be summed up alongside:
            uint count;

            // Empty constructor must generate neutral element
            CPU_AND_GPU ExtraData() : count(0) {}

            static GPU_ONLY ExtraData add(const ExtraData& l, const ExtraData& r) {
                ExtraData o;
                o.count = l.count + r.count;
                return o;
            }
            static GPU_ONLY void atomicAdd(DEVICEPTR(ExtraData&) result, const ExtraData& integrand) {
                ::atomicAdd(&result.count, integrand.count);
            }
        };

        /// should be executed with (blockIdx.x/2) == valid localVBA index (0 ignored) 
        /// annd blockIdx.y,z from 0 to 1 (parts of one block)
        /// and threadIdx <==> voxel localPos / 2..
        static GPU_ONLY bool generate(const uint i, VectorX<float, m>& out_ai, float& out_bi/*[1]*/, ExtraData& extra_count /*not really needed */) {
            const uint blockSequenceId = blockIdx.x / 2;
            if (blockSequenceId == 0) return false; // unused
            assert(blockSequenceId < SDF_LOCAL_BLOCK_NUM);

            assert(blockSequenceId < Scene::getCurrentScene()->voxelBlockHash->getLowestFreeSequenceNumber());

            assert(threadIdx.x < SDF_BLOCK_SIZE / 2 &&
                threadIdx.y < SDF_BLOCK_SIZE / 2 &&
                threadIdx.z < SDF_BLOCK_SIZE / 2);

            assert(blockIdx.y <= 1);
            assert(blockIdx.z <= 1);
            // voxel position
            const Vector3i localPos = Vector3i(threadIdx_xyz) + Vector3i(blockIdx.x % 2, blockIdx.y % 2, blockIdx.z % 2) * 4;

            assert(localPos.x >= 0 &&
                localPos.y >= 0 &&
                localPos.z >= 0);
            assert(localPos.x < SDF_BLOCK_SIZE  &&
                localPos.y < SDF_BLOCK_SIZE &&
                localPos.z < SDF_BLOCK_SIZE);

            ITMVoxelBlock* voxelBlock = Scene::getCurrentScene()->getVoxelBlockForSequenceNumber(blockSequenceId);

            const ITMVoxel* voxel = voxelBlock->getVoxel(localPos);
            const Vector3i globalPos = (voxelBlock->pos.toInt() * SDF_BLOCK_SIZE + localPos);
            /*
            const Vector3i globalPos = vb->pos.toInt() * SDF_BLOCK_SIZE;

            const THREADPTR(Point) & voxel_pt_world =  Point(
            CoordinateSystem::global(),
            (globalPos.toFloat() + localPos.toFloat()) * voxelSize
            ));

            .toFloat();
            Vector3f worldPos = CoordinateSystems::global()->convert(globalPos);
            */
            const float worldSpaceDistanceToSurface = abs(voxel->getSDF() * mu);
            assert(worldSpaceDistanceToSurface <= mu);

            // Is this voxel within the truncation band? Otherwise discard this term (as unreliable for lighting calculation)
            if (worldSpaceDistanceToSurface > t_shell) return false;

            // return if we cannot compute the normal
            bool found = true;
            const Vector3f normal = computeSingleNormalFromSDFByForwardDifference(globalPos, found);
            if (!found) return false;
            assert(abs(length(normal) - 1) < 0.01, "|n| = %f", length(normal));

            // i-th (voxel-th) row of A shall contain H_{0..b^2-1}(n(v))
            for (int i = 0; i < LightingModel::b2; i++) {
                out_ai[i] = LightingModel::sphericalHarmonicHi(i, normal);
            }

            // corresponding entry of b is I(v) / a(v)
            out_bi = voxel->intensity() / voxel->luminanceAlbedo;
            assert(out_bi >= 0 && out_bi <= 1);

            // TODO not really needed
            extra_count.count = 1;
            return true;
        }

    };

    // todo should we really discard the existing lighting model the next time? maybe we could use it as an initialization
    // when solving
    LightingModel estimateLightingModel() {
        assert(Scene::getCurrentScene());
        // Maximum number of entries

        const int validBlockNum = Scene::getCurrentScene()->voxelBlockHash->getLowestFreeSequenceNumber();

        auto gridDim = dim3(validBlockNum * 2, 2, 2);
        auto blockDim = dim3(SDF_BLOCK_SIZE / 2, SDF_BLOCK_SIZE / 2, SDF_BLOCK_SIZE / 2); // cannot use full SDF_BLOCK_SIZE: too much shared data (in reduction) -- TODO could just use the naive reduction algorithm. Could halve the memory use even now with being smart.

        const int n = validBlockNum * SDF_BLOCK_SIZE3; // maximum number of entries: total amount of currently allocated voxels (unlikely)
        assert(n == volume(gridDim) * volume(blockDim));

        ConstructLightingModelEquationRow::ExtraData extra_count;
        auto l_harmonicCoefficients = LeastSquares::constructAndSolve<ConstructLightingModelEquationRow>(n, gridDim, blockDim, extra_count);
        assert(extra_count.count > 0 && extra_count.count <= n); // sanity check
        assert(l_harmonicCoefficients.size() == LightingModel::b2);

        std::array<float, LightingModel::b2> l_harmonicCoefficients_a;
        for (int i = 0; i < LightingModel::b2; i++)
            l_harmonicCoefficients_a[i] = assertFinite(l_harmonicCoefficients[i]);

        LightingModel lightingModel(l_harmonicCoefficients_a);
        return lightingModel;
    }





    template<typename F>
    struct ComputeLighting {
        doForEachAllocatedVoxel_process() {
            // skip voxels without computable normal
            bool found = true;
            const UnitVector normal = computeSingleNormalFromSDFByForwardDifference(globalPos, found);
            if (!found) return;

            v->clr = F::operate(normal);

            v->w_color = 1;
        }
    };

    // Direction towards directional light source
    static __managed__ Vector3f lightNormal;
    struct DirectionalArtificialLighting {
        static GPU_ONLY Vector3u operate(UnitVector normal) {
            const float cos = MAX(0.f, dot(normal, lightNormal));
            return Vector3u(cos * 255, cos * 255, cos * 255);
        }
    };

    // compute voxel color according to given functor f from normal
    // c(v) := F::operate(n(v))
    // 'lighting shader baking' (lightmapping)
    template<typename F>
    void computeArtificialLighting() {
        cudaDeviceSynchronize();
        assert(Scene::getCurrentScene());

        Scene::getCurrentScene()->doForEachAllocatedVoxel<ComputeLighting<F>>();

        cudaDeviceSynchronize();
    }
}






























































namespace meshing {

    static const CPU_AND_GPU_CONSTANT int edgeTable[256] = {0x0, 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c, 0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
        0x190, 0x99, 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c, 0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90, 0x230, 0x339, 0x33, 0x13a,
        0x636, 0x73f, 0x435, 0x53c, 0xa3c, 0xb35, 0x83f, 0x936, 0xe3a, 0xf33, 0xc39, 0xd30, 0x3a0, 0x2a9, 0x1a3, 0xaa, 0x7a6, 0x6af, 0x5a5, 0x4ac,
        0xbac, 0xaa5, 0x9af, 0x8a6, 0xfaa, 0xea3, 0xda9, 0xca0, 0x460, 0x569, 0x663, 0x76a, 0x66, 0x16f, 0x265, 0x36c, 0xc6c, 0xd65, 0xe6f, 0xf66,
        0x86a, 0x963, 0xa69, 0xb60, 0x5f0, 0x4f9, 0x7f3, 0x6fa, 0x1f6, 0xff, 0x3f5, 0x2fc, 0xdfc, 0xcf5, 0xfff, 0xef6, 0x9fa, 0x8f3, 0xbf9, 0xaf0,
        0x650, 0x759, 0x453, 0x55a, 0x256, 0x35f, 0x55, 0x15c, 0xe5c, 0xf55, 0xc5f, 0xd56, 0xa5a, 0xb53, 0x859, 0x950, 0x7c0, 0x6c9, 0x5c3, 0x4ca,
        0x3c6, 0x2cf, 0x1c5, 0xcc, 0xfcc, 0xec5, 0xdcf, 0xcc6, 0xbca, 0xac3, 0x9c9, 0x8c0, 0x8c0, 0x9c9, 0xac3, 0xbca, 0xcc6, 0xdcf, 0xec5, 0xfcc,
        0xcc, 0x1c5, 0x2cf, 0x3c6, 0x4ca, 0x5c3, 0x6c9, 0x7c0, 0x950, 0x859, 0xb53, 0xa5a, 0xd56, 0xc5f, 0xf55, 0xe5c, 0x15c, 0x55, 0x35f, 0x256,
        0x55a, 0x453, 0x759, 0x650, 0xaf0, 0xbf9, 0x8f3, 0x9fa, 0xef6, 0xfff, 0xcf5, 0xdfc, 0x2fc, 0x3f5, 0xff, 0x1f6, 0x6fa, 0x7f3, 0x4f9, 0x5f0,
        0xb60, 0xa69, 0x963, 0x86a, 0xf66, 0xe6f, 0xd65, 0xc6c, 0x36c, 0x265, 0x16f, 0x66, 0x76a, 0x663, 0x569, 0x460, 0xca0, 0xda9, 0xea3, 0xfaa,
        0x8a6, 0x9af, 0xaa5, 0xbac, 0x4ac, 0x5a5, 0x6af, 0x7a6, 0xaa, 0x1a3, 0x2a9, 0x3a0, 0xd30, 0xc39, 0xf33, 0xe3a, 0x936, 0x83f, 0xb35, 0xa3c,
        0x53c, 0x435, 0x73f, 0x636, 0x13a, 0x33, 0x339, 0x230, 0xe90, 0xf99, 0xc93, 0xd9a, 0xa96, 0xb9f, 0x895, 0x99c, 0x69c, 0x795, 0x49f, 0x596,
        0x29a, 0x393, 0x99, 0x190, 0xf00, 0xe09, 0xd03, 0xc0a, 0xb06, 0xa0f, 0x905, 0x80c, 0x70c, 0x605, 0x50f, 0x406, 0x30a, 0x203, 0x109, 0x0};

    // edge number 0 to 11, or -1 for unused
    static const CPU_AND_GPU_CONSTANT int triangleTable[256][16] = {{-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {0, 1, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {1, 8, 3, 9, 8, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 3, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {9, 2, 10, 0, 2, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {2, 8, 3, 2, 10, 8, 10, 9, 8, -1, -1, -1, -1, -1, -1, -1}, {3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 11, 2, 8, 11, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {1, 9, 0, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {1, 11, 2, 1, 9, 11, 9, 8, 11, -1, -1, -1, -1, -1, -1, -1}, {3, 10, 1, 11, 10, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 10, 1, 0, 8, 10, 8, 11, 10, -1, -1, -1, -1, -1, -1, -1}, {3, 9, 0, 3, 11, 9, 11, 10, 9, -1, -1, -1, -1, -1, -1, -1},
    {9, 8, 10, 10, 8, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {4, 3, 0, 7, 3, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {0, 1, 9, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {4, 1, 9, 4, 7, 1, 7, 3, 1, -1, -1, -1, -1, -1, -1, -1}, {1, 2, 10, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {3, 4, 7, 3, 0, 4, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1}, {9, 2, 10, 9, 0, 2, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1},
    {2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, -1, -1, -1, -1}, {8, 4, 7, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {11, 4, 7, 11, 2, 4, 2, 0, 4, -1, -1, -1, -1, -1, -1, -1}, {9, 0, 1, 8, 4, 7, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1},
    {4, 7, 11, 9, 4, 11, 9, 11, 2, 9, 2, 1, -1, -1, -1, -1}, {3, 10, 1, 3, 11, 10, 7, 8, 4, -1, -1, -1, -1, -1, -1, -1},
    {1, 11, 10, 1, 4, 11, 1, 0, 4, 7, 11, 4, -1, -1, -1, -1}, {4, 7, 8, 9, 0, 11, 9, 11, 10, 11, 0, 3, -1, -1, -1, -1},
    {4, 7, 11, 4, 11, 9, 9, 11, 10, -1, -1, -1, -1, -1, -1, -1}, {9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {9, 5, 4, 0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {0, 5, 4, 1, 5, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {8, 5, 4, 8, 3, 5, 3, 1, 5, -1, -1, -1, -1, -1, -1, -1}, {1, 2, 10, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {3, 0, 8, 1, 2, 10, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1}, {5, 2, 10, 5, 4, 2, 4, 0, 2, -1, -1, -1, -1, -1, -1, -1},
    {2, 10, 5, 3, 2, 5, 3, 5, 4, 3, 4, 8, -1, -1, -1, -1}, {9, 5, 4, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 11, 2, 0, 8, 11, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1}, {0, 5, 4, 0, 1, 5, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1},
    {2, 1, 5, 2, 5, 8, 2, 8, 11, 4, 8, 5, -1, -1, -1, -1}, {10, 3, 11, 10, 1, 3, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1},
    {4, 9, 5, 0, 8, 1, 8, 10, 1, 8, 11, 10, -1, -1, -1, -1}, {5, 4, 0, 5, 0, 11, 5, 11, 10, 11, 0, 3, -1, -1, -1, -1},
    {5, 4, 8, 5, 8, 10, 10, 8, 11, -1, -1, -1, -1, -1, -1, -1}, {9, 7, 8, 5, 7, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {9, 3, 0, 9, 5, 3, 5, 7, 3, -1, -1, -1, -1, -1, -1, -1}, {0, 7, 8, 0, 1, 7, 1, 5, 7, -1, -1, -1, -1, -1, -1, -1},
    {1, 5, 3, 3, 5, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {9, 7, 8, 9, 5, 7, 10, 1, 2, -1, -1, -1, -1, -1, -1, -1},
    {10, 1, 2, 9, 5, 0, 5, 3, 0, 5, 7, 3, -1, -1, -1, -1}, {8, 0, 2, 8, 2, 5, 8, 5, 7, 10, 5, 2, -1, -1, -1, -1},
    {2, 10, 5, 2, 5, 3, 3, 5, 7, -1, -1, -1, -1, -1, -1, -1}, {7, 9, 5, 7, 8, 9, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1},
    {9, 5, 7, 9, 7, 2, 9, 2, 0, 2, 7, 11, -1, -1, -1, -1}, {2, 3, 11, 0, 1, 8, 1, 7, 8, 1, 5, 7, -1, -1, -1, -1},
    {11, 2, 1, 11, 1, 7, 7, 1, 5, -1, -1, -1, -1, -1, -1, -1}, {9, 5, 8, 8, 5, 7, 10, 1, 3, 10, 3, 11, -1, -1, -1, -1},
    {5, 7, 0, 5, 0, 9, 7, 11, 0, 1, 0, 10, 11, 10, 0, -1}, {11, 10, 0, 11, 0, 3, 10, 5, 0, 8, 0, 7, 5, 7, 0, -1},
    {11, 10, 5, 7, 11, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {10, 6, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 3, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {9, 0, 1, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {1, 8, 3, 1, 9, 8, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1}, {1, 6, 5, 2, 6, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {1, 6, 5, 1, 2, 6, 3, 0, 8, -1, -1, -1, -1, -1, -1, -1}, {9, 6, 5, 9, 0, 6, 0, 2, 6, -1, -1, -1, -1, -1, -1, -1},
    {5, 9, 8, 5, 8, 2, 5, 2, 6, 3, 2, 8, -1, -1, -1, -1}, {2, 3, 11, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {11, 0, 8, 11, 2, 0, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1}, {0, 1, 9, 2, 3, 11, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1},
    {5, 10, 6, 1, 9, 2, 9, 11, 2, 9, 8, 11, -1, -1, -1, -1}, {6, 3, 11, 6, 5, 3, 5, 1, 3, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 11, 0, 11, 5, 0, 5, 1, 5, 11, 6, -1, -1, -1, -1}, {3, 11, 6, 0, 3, 6, 0, 6, 5, 0, 5, 9, -1, -1, -1, -1},
    {6, 5, 9, 6, 9, 11, 11, 9, 8, -1, -1, -1, -1, -1, -1, -1}, {5, 10, 6, 4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {4, 3, 0, 4, 7, 3, 6, 5, 10, -1, -1, -1, -1, -1, -1, -1}, {1, 9, 0, 5, 10, 6, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1},
    {10, 6, 5, 1, 9, 7, 1, 7, 3, 7, 9, 4, -1, -1, -1, -1}, {6, 1, 2, 6, 5, 1, 4, 7, 8, -1, -1, -1, -1, -1, -1, -1},
    {1, 2, 5, 5, 2, 6, 3, 0, 4, 3, 4, 7, -1, -1, -1, -1}, {8, 4, 7, 9, 0, 5, 0, 6, 5, 0, 2, 6, -1, -1, -1, -1},
    {7, 3, 9, 7, 9, 4, 3, 2, 9, 5, 9, 6, 2, 6, 9, -1}, {3, 11, 2, 7, 8, 4, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1},
    {5, 10, 6, 4, 7, 2, 4, 2, 0, 2, 7, 11, -1, -1, -1, -1}, {0, 1, 9, 4, 7, 8, 2, 3, 11, 5, 10, 6, -1, -1, -1, -1},
    {9, 2, 1, 9, 11, 2, 9, 4, 11, 7, 11, 4, 5, 10, 6, -1}, {8, 4, 7, 3, 11, 5, 3, 5, 1, 5, 11, 6, -1, -1, -1, -1},
    {5, 1, 11, 5, 11, 6, 1, 0, 11, 7, 11, 4, 0, 4, 11, -1}, {0, 5, 9, 0, 6, 5, 0, 3, 6, 11, 6, 3, 8, 4, 7, -1},
    {6, 5, 9, 6, 9, 11, 4, 7, 9, 7, 11, 9, -1, -1, -1, -1}, {10, 4, 9, 6, 4, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {4, 10, 6, 4, 9, 10, 0, 8, 3, -1, -1, -1, -1, -1, -1, -1}, {10, 0, 1, 10, 6, 0, 6, 4, 0, -1, -1, -1, -1, -1, -1, -1},
    {8, 3, 1, 8, 1, 6, 8, 6, 4, 6, 1, 10, -1, -1, -1, -1}, {1, 4, 9, 1, 2, 4, 2, 6, 4, -1, -1, -1, -1, -1, -1, -1},
    {3, 0, 8, 1, 2, 9, 2, 4, 9, 2, 6, 4, -1, -1, -1, -1}, {0, 2, 4, 4, 2, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {8, 3, 2, 8, 2, 4, 4, 2, 6, -1, -1, -1, -1, -1, -1, -1}, {10, 4, 9, 10, 6, 4, 11, 2, 3, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 2, 2, 8, 11, 4, 9, 10, 4, 10, 6, -1, -1, -1, -1}, {3, 11, 2, 0, 1, 6, 0, 6, 4, 6, 1, 10, -1, -1, -1, -1},
    {6, 4, 1, 6, 1, 10, 4, 8, 1, 2, 1, 11, 8, 11, 1, -1}, {9, 6, 4, 9, 3, 6, 9, 1, 3, 11, 6, 3, -1, -1, -1, -1},
    {8, 11, 1, 8, 1, 0, 11, 6, 1, 9, 1, 4, 6, 4, 1, -1}, {3, 11, 6, 3, 6, 0, 0, 6, 4, -1, -1, -1, -1, -1, -1, -1},
    {6, 4, 8, 11, 6, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {7, 10, 6, 7, 8, 10, 8, 9, 10, -1, -1, -1, -1, -1, -1, -1},
    {0, 7, 3, 0, 10, 7, 0, 9, 10, 6, 7, 10, -1, -1, -1, -1}, {10, 6, 7, 1, 10, 7, 1, 7, 8, 1, 8, 0, -1, -1, -1, -1},
    {10, 6, 7, 10, 7, 1, 1, 7, 3, -1, -1, -1, -1, -1, -1, -1}, {1, 2, 6, 1, 6, 8, 1, 8, 9, 8, 6, 7, -1, -1, -1, -1},
    {2, 6, 9, 2, 9, 1, 6, 7, 9, 0, 9, 3, 7, 3, 9, -1}, {7, 8, 0, 7, 0, 6, 6, 0, 2, -1, -1, -1, -1, -1, -1, -1},
    {7, 3, 2, 6, 7, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {2, 3, 11, 10, 6, 8, 10, 8, 9, 8, 6, 7, -1, -1, -1, -1},
    {2, 0, 7, 2, 7, 11, 0, 9, 7, 6, 7, 10, 9, 10, 7, -1}, {1, 8, 0, 1, 7, 8, 1, 10, 7, 6, 7, 10, 2, 3, 11, -1},
    {11, 2, 1, 11, 1, 7, 10, 6, 1, 6, 7, 1, -1, -1, -1, -1}, {8, 9, 6, 8, 6, 7, 9, 1, 6, 11, 6, 3, 1, 3, 6, -1},
    {0, 9, 1, 11, 6, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {7, 8, 0, 7, 0, 6, 3, 11, 0, 11, 6, 0, -1, -1, -1, -1},
    {7, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {7, 6, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {3, 0, 8, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {0, 1, 9, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {8, 1, 9, 8, 3, 1, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1}, {10, 1, 2, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {1, 2, 10, 3, 0, 8, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1}, {2, 9, 0, 2, 10, 9, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1},
    {6, 11, 7, 2, 10, 3, 10, 8, 3, 10, 9, 8, -1, -1, -1, -1}, {7, 2, 3, 6, 2, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {7, 0, 8, 7, 6, 0, 6, 2, 0, -1, -1, -1, -1, -1, -1, -1}, {2, 7, 6, 2, 3, 7, 0, 1, 9, -1, -1, -1, -1, -1, -1, -1},
    {1, 6, 2, 1, 8, 6, 1, 9, 8, 8, 7, 6, -1, -1, -1, -1}, {10, 7, 6, 10, 1, 7, 1, 3, 7, -1, -1, -1, -1, -1, -1, -1},
    {10, 7, 6, 1, 7, 10, 1, 8, 7, 1, 0, 8, -1, -1, -1, -1}, {0, 3, 7, 0, 7, 10, 0, 10, 9, 6, 10, 7, -1, -1, -1, -1},
    {7, 6, 10, 7, 10, 8, 8, 10, 9, -1, -1, -1, -1, -1, -1, -1}, {6, 8, 4, 11, 8, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {3, 6, 11, 3, 0, 6, 0, 4, 6, -1, -1, -1, -1, -1, -1, -1}, {8, 6, 11, 8, 4, 6, 9, 0, 1, -1, -1, -1, -1, -1, -1, -1},
    {9, 4, 6, 9, 6, 3, 9, 3, 1, 11, 3, 6, -1, -1, -1, -1}, {6, 8, 4, 6, 11, 8, 2, 10, 1, -1, -1, -1, -1, -1, -1, -1},
    {1, 2, 10, 3, 0, 11, 0, 6, 11, 0, 4, 6, -1, -1, -1, -1}, {4, 11, 8, 4, 6, 11, 0, 2, 9, 2, 10, 9, -1, -1, -1, -1},
    {10, 9, 3, 10, 3, 2, 9, 4, 3, 11, 3, 6, 4, 6, 3, -1}, {8, 2, 3, 8, 4, 2, 4, 6, 2, -1, -1, -1, -1, -1, -1, -1},
    {0, 4, 2, 4, 6, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {1, 9, 0, 2, 3, 4, 2, 4, 6, 4, 3, 8, -1, -1, -1, -1},
    {1, 9, 4, 1, 4, 2, 2, 4, 6, -1, -1, -1, -1, -1, -1, -1}, {8, 1, 3, 8, 6, 1, 8, 4, 6, 6, 10, 1, -1, -1, -1, -1},
    {10, 1, 0, 10, 0, 6, 6, 0, 4, -1, -1, -1, -1, -1, -1, -1}, {4, 6, 3, 4, 3, 8, 6, 10, 3, 0, 3, 9, 10, 9, 3, -1},
    {10, 9, 4, 6, 10, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {4, 9, 5, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 3, 4, 9, 5, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1}, {5, 0, 1, 5, 4, 0, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1},
    {11, 7, 6, 8, 3, 4, 3, 5, 4, 3, 1, 5, -1, -1, -1, -1}, {9, 5, 4, 10, 1, 2, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1},
    {6, 11, 7, 1, 2, 10, 0, 8, 3, 4, 9, 5, -1, -1, -1, -1}, {7, 6, 11, 5, 4, 10, 4, 2, 10, 4, 0, 2, -1, -1, -1, -1},
    {3, 4, 8, 3, 5, 4, 3, 2, 5, 10, 5, 2, 11, 7, 6, -1}, {7, 2, 3, 7, 6, 2, 5, 4, 9, -1, -1, -1, -1, -1, -1, -1},
    {9, 5, 4, 0, 8, 6, 0, 6, 2, 6, 8, 7, -1, -1, -1, -1}, {3, 6, 2, 3, 7, 6, 1, 5, 0, 5, 4, 0, -1, -1, -1, -1},
    {6, 2, 8, 6, 8, 7, 2, 1, 8, 4, 8, 5, 1, 5, 8, -1}, {9, 5, 4, 10, 1, 6, 1, 7, 6, 1, 3, 7, -1, -1, -1, -1},
    {1, 6, 10, 1, 7, 6, 1, 0, 7, 8, 7, 0, 9, 5, 4, -1}, {4, 0, 10, 4, 10, 5, 0, 3, 10, 6, 10, 7, 3, 7, 10, -1},
    {7, 6, 10, 7, 10, 8, 5, 4, 10, 4, 8, 10, -1, -1, -1, -1}, {6, 9, 5, 6, 11, 9, 11, 8, 9, -1, -1, -1, -1, -1, -1, -1},
    {3, 6, 11, 0, 6, 3, 0, 5, 6, 0, 9, 5, -1, -1, -1, -1}, {0, 11, 8, 0, 5, 11, 0, 1, 5, 5, 6, 11, -1, -1, -1, -1},
    {6, 11, 3, 6, 3, 5, 5, 3, 1, -1, -1, -1, -1, -1, -1, -1}, {1, 2, 10, 9, 5, 11, 9, 11, 8, 11, 5, 6, -1, -1, -1, -1},
    {0, 11, 3, 0, 6, 11, 0, 9, 6, 5, 6, 9, 1, 2, 10, -1}, {11, 8, 5, 11, 5, 6, 8, 0, 5, 10, 5, 2, 0, 2, 5, -1},
    {6, 11, 3, 6, 3, 5, 2, 10, 3, 10, 5, 3, -1, -1, -1, -1}, {5, 8, 9, 5, 2, 8, 5, 6, 2, 3, 8, 2, -1, -1, -1, -1},
    {9, 5, 6, 9, 6, 0, 0, 6, 2, -1, -1, -1, -1, -1, -1, -1}, {1, 5, 8, 1, 8, 0, 5, 6, 8, 3, 8, 2, 6, 2, 8, -1},
    {1, 5, 6, 2, 1, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {1, 3, 6, 1, 6, 10, 3, 8, 6, 5, 6, 9, 8, 9, 6, -1},
    {10, 1, 0, 10, 0, 6, 9, 5, 0, 5, 6, 0, -1, -1, -1, -1}, {0, 3, 8, 5, 6, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {10, 5, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {11, 5, 10, 7, 5, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {11, 5, 10, 11, 7, 5, 8, 3, 0, -1, -1, -1, -1, -1, -1, -1}, {5, 11, 7, 5, 10, 11, 1, 9, 0, -1, -1, -1, -1, -1, -1, -1},
    {10, 7, 5, 10, 11, 7, 9, 8, 1, 8, 3, 1, -1, -1, -1, -1}, {11, 1, 2, 11, 7, 1, 7, 5, 1, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 3, 1, 2, 7, 1, 7, 5, 7, 2, 11, -1, -1, -1, -1}, {9, 7, 5, 9, 2, 7, 9, 0, 2, 2, 11, 7, -1, -1, -1, -1},
    {7, 5, 2, 7, 2, 11, 5, 9, 2, 3, 2, 8, 9, 8, 2, -1}, {2, 5, 10, 2, 3, 5, 3, 7, 5, -1, -1, -1, -1, -1, -1, -1},
    {8, 2, 0, 8, 5, 2, 8, 7, 5, 10, 2, 5, -1, -1, -1, -1}, {9, 0, 1, 5, 10, 3, 5, 3, 7, 3, 10, 2, -1, -1, -1, -1},
    {9, 8, 2, 9, 2, 1, 8, 7, 2, 10, 2, 5, 7, 5, 2, -1}, {1, 3, 5, 3, 7, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 7, 0, 7, 1, 1, 7, 5, -1, -1, -1, -1, -1, -1, -1}, {9, 0, 3, 9, 3, 5, 5, 3, 7, -1, -1, -1, -1, -1, -1, -1},
    {9, 8, 7, 5, 9, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {5, 8, 4, 5, 10, 8, 10, 11, 8, -1, -1, -1, -1, -1, -1, -1},
    {5, 0, 4, 5, 11, 0, 5, 10, 11, 11, 3, 0, -1, -1, -1, -1}, {0, 1, 9, 8, 4, 10, 8, 10, 11, 10, 4, 5, -1, -1, -1, -1},
    {10, 11, 4, 10, 4, 5, 11, 3, 4, 9, 4, 1, 3, 1, 4, -1}, {2, 5, 1, 2, 8, 5, 2, 11, 8, 4, 5, 8, -1, -1, -1, -1},
    {0, 4, 11, 0, 11, 3, 4, 5, 11, 2, 11, 1, 5, 1, 11, -1}, {0, 2, 5, 0, 5, 9, 2, 11, 5, 4, 5, 8, 11, 8, 5, -1},
    {9, 4, 5, 2, 11, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {2, 5, 10, 3, 5, 2, 3, 4, 5, 3, 8, 4, -1, -1, -1, -1},
    {5, 10, 2, 5, 2, 4, 4, 2, 0, -1, -1, -1, -1, -1, -1, -1}, {3, 10, 2, 3, 5, 10, 3, 8, 5, 4, 5, 8, 0, 1, 9, -1},
    {5, 10, 2, 5, 2, 4, 1, 9, 2, 9, 4, 2, -1, -1, -1, -1}, {8, 4, 5, 8, 5, 3, 3, 5, 1, -1, -1, -1, -1, -1, -1, -1},
    {0, 4, 5, 1, 0, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {8, 4, 5, 8, 5, 3, 9, 0, 5, 0, 3, 5, -1, -1, -1, -1},
    {9, 4, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {4, 11, 7, 4, 9, 11, 9, 10, 11, -1, -1, -1, -1, -1, -1, -1},
    {0, 8, 3, 4, 9, 7, 9, 11, 7, 9, 10, 11, -1, -1, -1, -1}, {1, 10, 11, 1, 11, 4, 1, 4, 0, 7, 4, 11, -1, -1, -1, -1},
    {3, 1, 4, 3, 4, 8, 1, 10, 4, 7, 4, 11, 10, 11, 4, -1}, {4, 11, 7, 9, 11, 4, 9, 2, 11, 9, 1, 2, -1, -1, -1, -1},
    {9, 7, 4, 9, 11, 7, 9, 1, 11, 2, 11, 1, 0, 8, 3, -1}, {11, 7, 4, 11, 4, 2, 2, 4, 0, -1, -1, -1, -1, -1, -1, -1},
    {11, 7, 4, 11, 4, 2, 8, 3, 4, 3, 2, 4, -1, -1, -1, -1}, {2, 9, 10, 2, 7, 9, 2, 3, 7, 7, 4, 9, -1, -1, -1, -1},
    {9, 10, 7, 9, 7, 4, 10, 2, 7, 8, 7, 0, 2, 0, 7, -1}, {3, 7, 10, 3, 10, 2, 7, 4, 10, 1, 10, 0, 4, 0, 10, -1},
    {1, 10, 2, 8, 7, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {4, 9, 1, 4, 1, 7, 7, 1, 3, -1, -1, -1, -1, -1, -1, -1},
    {4, 9, 1, 4, 1, 7, 0, 8, 1, 8, 7, 1, -1, -1, -1, -1}, {4, 0, 3, 7, 4, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {4, 8, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {9, 10, 8, 10, 11, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {3, 0, 9, 3, 9, 11, 11, 9, 10, -1, -1, -1, -1, -1, -1, -1}, {0, 1, 10, 0, 10, 8, 8, 10, 11, -1, -1, -1, -1, -1, -1, -1},
    {3, 1, 10, 11, 3, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {1, 2, 11, 1, 11, 9, 9, 11, 8, -1, -1, -1, -1, -1, -1, -1},
    {3, 0, 9, 3, 9, 11, 1, 2, 9, 2, 11, 9, -1, -1, -1, -1}, {0, 2, 11, 8, 0, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {3, 2, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {2, 3, 8, 2, 8, 10, 10, 8, 9, -1, -1, -1, -1, -1, -1, -1},
    {9, 10, 2, 0, 9, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {2, 3, 8, 2, 8, 10, 0, 1, 8, 1, 10, 8, -1, -1, -1, -1},
    {1, 10, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {1, 3, 8, 9, 1, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {0, 9, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}, {0, 3, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}};


    struct Vertex {
        Vector3f p, c;
    };
    struct Triangle { Vertex v[3]; };

    GPU_ONLY void get(
        const Vector3i voxelLocation,
        bool& isFound,
        float& sdf,
        Vertex& vert) {

        assert(isFound);
        auto v = Scene::getCurrentSceneVoxel(voxelLocation);
        if (!v) {
            isFound = false;
            return;
        }
        vert.p = voxelLocation.toFloat();
        vert.c = v->clr.toFloat();
        sdf = v->getSDF();
    }

    GPU_ONLY inline bool findPointNeighbors(
        /*out*/Vertex v[8], /*out*/ float *sdf,
        const Vector3i globalPos)
    {
        bool isFound;

#define access(dx, dy, dz, id) \
        isFound = true; get(globalPos + Vector3i(dx, dy, dz), isFound, sdf[id], v[id]);\
        if (!isFound || sdf[id] == 1.0f) return false;

        access(0, 0, 0, 0);
        access(1, 0, 0, 1);
        access(1, 1, 0, 2);
        access(0, 1, 0, 3);
        access(0, 0, 1, 4);
        access(1, 0, 1, 5);
        access(1, 1, 1, 6);
        access(0, 1, 1, 7);
#undef access
        return true;
    }

    GPU_ONLY inline Vector3f sdfInterp(const Vector3f &p1, const Vector3f &p2, float valp1, float valp2)
    {
        if (fabs(0.0f - valp1) < 0.00001f) return p1;
        if (fabs(0.0f - valp2) < 0.00001f) return p2;
        if (fabs(valp1 - valp2) < 0.00001f) return p1;

        return p1 + ((0.0f - valp1) / (valp2 - valp1)) * (p2 - p1);
    }

    GPU_ONLY inline void sdfInterp(Vertex &out, const Vertex &p1, const Vertex &p2, float valp1, float valp2)
    {
        out.p = sdfInterp(p1.p, p2.p, valp1, valp2);
        out.c = sdfInterp(p1.c, p2.c, valp1, valp2);
    }

    GPU_ONLY inline int buildVertList(Vertex finalVertexList[12], Vector3i globalPos)
    {
        Vertex vertices[8];  float sdfVals[8];

        if (!findPointNeighbors(vertices, sdfVals, globalPos)) return -1;

        int cubeIndex = 0;
        if (sdfVals[0] < 0) cubeIndex |= 1; if (sdfVals[1] < 0) cubeIndex |= 2;
        if (sdfVals[2] < 0) cubeIndex |= 4; if (sdfVals[3] < 0) cubeIndex |= 8;
        if (sdfVals[4] < 0) cubeIndex |= 16; if (sdfVals[5] < 0) cubeIndex |= 32;
        if (sdfVals[6] < 0) cubeIndex |= 64; if (sdfVals[7] < 0) cubeIndex |= 128;

        if (edgeTable[cubeIndex] == 0) return -1;


#define access(id, mask, a, b) \
        if (edgeTable[cubeIndex] & mask) sdfInterp(finalVertexList[id], vertices[a], vertices[b], sdfVals[a], sdfVals[b]);

        access(0, 1, 0, 1);
        access(1, 2, 1, 2);
        access(2, 4, 2, 3);
        access(3, 8, 3, 0);
        access(4, 16, 4, 5);
        access(5, 32, 5, 6);
        access(6, 64, 6, 7);
        access(7, 128, 7, 4);
        access(8, 256, 0, 4);
        access(9, 512, 1, 5);
        access(10, 1024, 2, 6);
        access(11, 2048, 3, 7);

#undef access

        return cubeIndex;
    }

    const uint noMaxTriangles = 10 * 1000 * 1000;//SDF_LOCAL_BLOCK_NUM * 32; // heuristic ?! // if anything, consider allocated blocks
    // and max triangles per marching cube and assume moderate occupation of blocks (like, half)

    __managed__ Triangle *triangles;
    __managed__ unsigned int noTriangles;

    struct MeshVoxel {
        doForEachAllocatedVoxel_process() {
            Vertex finalVertexList[12];
            int cubeIndex = buildVertList(finalVertexList, globalPos);

            if (cubeIndex < 0) return;

            for (int i = 0; triangleTable[cubeIndex][i] != -1; i += 3)
            {
                int triangleId = atomicAdd(&noTriangles, 1);

                if (triangleId < noMaxTriangles - 1)
                {
                    for (int k = 0; k < 3; k++) {
                        triangles[triangleId].v[k] = finalVertexList[triangleTable[cubeIndex][i + k]];
                        //assert(triangles[triangleId].c[k].x >= 0.f && triangles[triangleId].c[k].x <= 255.001);
                    }
                }
            }
        }
    };

    void MeshScene(string baseFileName, Scene* scene = Scene::getCurrentScene())
    {
        CURRENT_SCENE_SCOPE(scene);

        auto_ptr<MemoryBlock<Triangle>> triangles(new MemoryBlock<Triangle>(noMaxTriangles));

        meshing::noTriangles = 0;
        meshing::triangles = triangles->GetData(MEMORYDEVICE_CUDA);

        Scene::getCurrentScene()->doForEachAllocatedVoxel<MeshVoxel>();
        cudaDeviceSynchronize();
        assert(noTriangles);
        assert(noMaxTriangles);
        assert(noTriangles < noMaxTriangles);


        // Write
        cout << "writing file " << baseFileName << endl;
        Triangle *triangleArray = triangles->GetData();

        FILE *f = fopen((baseFileName + ".obj").c_str(), "wb");
        assert(f);

        int j = 1;
        for (uint i = 0; i < noTriangles; i++)
        {
            // Walk through vertex list in reverse for correct orientation (is the table flipped?)
            for (int k = 2; k >= 0; k--) {
                Vector3f p = triangleArray[i].v[k].p * voxelSize; // coordinates where voxel coordinates
                Vector3f c = triangleArray[i].v[k].c / 255.0f; // colors in obj are 0 to 1

                fprintf(f, "v %f %f %f %f %f %f\n", xyz(p), xyz(c));

                assert(c.x >= 0.f && c.x <= 1.001);
            }

            fprintf(f, "f %d %d %d\n", j, j + 1, j + 2);
            j += 3;
        }

        fclose(f);
    }

} // meshing namespace
using namespace meshing;




namespace resample {
    __managed__ Scene* coarse, *fine;


    struct InterpolateCoarseToFine {
        float resultSDF;
        Vector3f resultColor;
        bool& isFound;
        GPU_ONLY InterpolateCoarseToFine(bool& isFound) : resultSDF(0), resultColor(0, 0, 0), isFound(isFound) {}

        GPU_ONLY void operator()(Vector3i globalPos, float lerpCoeff) {
            assert(lerpCoeff >= 0 && lerpCoeff <= 1, "%f", lerpCoeff);

            auto v = readVoxel(globalPos, isFound, coarse); // IMPORTANT must use coarse scene here
            assert(v.getSDF() >= -1 && v.getSDF() <= 1, "%f", v.getSDF());
            resultSDF += lerpCoeff * v.getSDF();
            resultColor += lerpCoeff * v.clr.toFloat();
        }
    };

    // call with current scene == fine
    struct CoarseToFine {
        doForEachAllocatedVoxel_process() {
            assert(Scene::getCurrentScene() == fine);
            assert(coarse != Scene::getCurrentScene());

            // how much bigger is the coarse voxel Size?
            const float factor = coarse->getVoxelSize() / fine->getVoxelSize();

            // read and interpolate coarse
            assert(globalPoint.coordinateSystem == CoordinateSystem::global());
            auto coarseVoxelCoord = coarse->voxelCoordinates_->convert(globalPoint);

            Vector3f coarsePoint = coarseVoxelCoord.location;
            bool isFound = true;
            InterpolateCoarseToFine interpolator(isFound);
            forEachBoundingVoxel(coarsePoint, interpolator);

            if (!isFound) interpolator.resultSDF = 1;
            assert(interpolator.resultSDF >= -1.0001 && interpolator.resultSDF <= 1.001, "%f", interpolator.resultSDF);

            // rescale SDF
            // to world
            const float coarseMu = voxelSize_to_mu(coarse->getVoxelSize());
            float sdf = interpolator.resultSDF * coarseMu;
            // to fine
            sdf /= mu; // voxelSize_to_mu(Scene::getCurrentScene()->getVoxelSize);

            assert(abs(sdf) <= factor*1.0001);

            sdf = CLAMP(sdf, -1.f, 1.f);

            // set fine
            v->setSDF(sdf);
            v->w_depth = 1;
            v->clr = (interpolator.resultColor).toUChar();//isFound ? Vector3u(0,255,0) : Vector3u(255,0,0);// 
            v->w_color = 1;
        }
    };
    /*
    UPSAMPLE

    Initialize allocated voxels of *fine* by interpolating
    the values defined for the corresponding coarse voxels.

    Since voxels store a normalized SDF value, it has to be rescaled to the fine voxelSize beforehand.
    */
    void initFineFromCoarse(Scene* fine_, Scene* coarse_) {
        assert(fine); assert(coarse);
        assert(coarse->getVoxelSize() > fine->getVoxelSize());
        assert(fine_ != coarse_);
        coarse = coarse_;
        fine = fine_;
        CURRENT_SCENE_SCOPE(fine);

        fine->doForEachAllocatedVoxel<CoarseToFine>();
    }

}











vector<Scene*> scenes;
int addScene(Scene* s) {
    assert(s);
    scenes.push_back(s);
    return scenes.size() - 1;
}
Scene* getScene(int id) {
    assert(id >= 0 && id < scenes.size());
    auto s = scenes[id];
    assert(s);
    return s;
}

KERNEL gpuFalse() {
    assert(false);
}


namespace WSTP {
#define getTensor(TYPE, WLTYPE, expectDepth) int* dims; TYPE* a; int depth; char** heads; WSGet ## WLTYPE ## Array(stdlink, &a, &dims, &heads, &depth); assert(depth == expectDepth); 

#define releaseTensor(TYPE) WSRelease ## TYPE ## Array(stdlink, a, dims, heads, depth);


    void putImageRGBA8(ITMUChar4Image* i) {
        int dims[] = {i->noDims.height, i->noDims.width, 4};
        const char* heads[] = {"List", "List", "List"};
        WSPutInteger8Array(stdlink,
            (unsigned char*)i->GetData(),
            dims, heads, 3);
    }

    void putImageFloat(ITMFloatImage* i) {
        int dims[] = {i->noDims.height, i->noDims.width};
        const char* heads[] = {"List", "List"};
        WSPutReal32Array(stdlink,
            (float*)i->GetData(),
            dims, heads, 2);
    }

    void putImageFloat4(ITMFloat4Image* i) {
        int dims[] = {i->noDims.height, i->noDims.width, 4};
        const char* heads[] = {"List", "List", "List"};
        WSPutReal32Array(stdlink,
            (float*)i->GetData(),
            dims, heads, 3);
    }

    // putFloatList rather
    void putFloatArray(const float* a, const int n) {
        int dims[] = {n};
        const char* heads[] = {"List"};
        WSPutReal32Array(stdlink, a, dims, heads, 1); // use List function
    }

    void putUnorm(unsigned char c) {
        WSPutReal(stdlink, 1. * c / UCHAR_MAX);
    }

    unsigned char getUnormUC() {
        double d;  WSGetDouble(stdlink, &d);
        return d * UCHAR_MAX;
    }

    void putColor(Vector3u c) {
        WSPutFunction(stdlink, "List", 3);
        putUnorm(c.r);
        putUnorm(c.g);
        putUnorm(c.b);
    }

    Vector3u getColor() {
        long args; WSCheckFunction(stdlink, "List", &args);
        assert(args == 3);

        unsigned char r = getUnormUC(), g = getUnormUC(), b = getUnormUC();
        return Vector3u(r, g, b);
    }

    // {normalizedSDF_?SNormQ, sdfSampleCount_Integer?NonNegative, color : {r_?UNormQ, g_?UNormQ, b_?UNormQ}, colorSampleCount_Integer?NonNegative}
    void putVoxel(const ITMVoxel& v) {
        WSPutFunction(stdlink, "List", 4);

        WSPutReal(stdlink, v.getSDF());
        WSPutInteger(stdlink, v.w_depth);
        putColor(v.clr);
        WSPutInteger(stdlink, v.w_color);
    }
    
#include <sal.h>
    void getVoxel(_Out_ ITMVoxel& v) {
        long args;
        WSCheckFunction(stdlink, "List", &args);
        assert(args == 4);

        float f; WSGetFloat(stdlink, &f); v.setSDF(f);
        WSGetInteger8(stdlink, &v.w_depth);
        v.clr = getColor();
        WSGetInteger8(stdlink, &v.w_color);
    }


    // {{x_Integer,y_Integer,z_Integer}, {__Voxel}}
    void putVoxelBlock(ITMVoxelBlock& v) {
        WSPutFunction(stdlink, "List", 2);
        
        WSPutInteger16List(stdlink, (short*)&v.pos_, 3); // TODO are these packed correctly?

        WSPutFunction(stdlink, "List", SDF_BLOCK_SIZE3);
        /*for (int i = 0; i < SDF_BLOCK_SIZE3; i++)
            putVoxel(v.blockVoxels[i]);*/
        // change ordering such that {x,y,z} indices in mathematica correspond to xyz here:
        // make z vary fastest
        for (int x = 0; x < SDF_BLOCK_SIZE; x++)
            for (int y = 0; y < SDF_BLOCK_SIZE; y++)
                for (int z = 0; z < SDF_BLOCK_SIZE; z++)
                    putVoxel(*v.getVoxel(Vector3i(x,y,z)));

    }

    // receives {{x_Integer,y_Integer,z_Integer}, {__Voxel}}
    void getVoxelBlock(_Out_ ITMVoxelBlock& v) {
        long args;
        WSCheckFunction(stdlink, "List", &args);
        assert(args == 2);

        int count; short* ppos; WSGetInteger16List(stdlink, &ppos, &count);
        assert(count == 3);
        v.reinit(VoxelBlockPos(ppos));
        assert(v.getPos() != INVALID_VOXEL_BLOCK_POS);
        WSReleaseInteger16List(stdlink, ppos, count);

        WSCheckFunction(stdlink, "List", &args);
        assert(args == SDF_BLOCK_SIZE3);

        /*
        for (int i = 0; i < SDF_BLOCK_SIZE3; i++)
            getVoxel(v.blockVoxels[i]);
            */
        // change ordering such that {x,y,z} indices in mathematica correspond to xyz here:
        // make z vary fastest
        for (int x = 0; x < SDF_BLOCK_SIZE; x++)
            for (int y = 0; y < SDF_BLOCK_SIZE; y++)
                for (int z = 0; z < SDF_BLOCK_SIZE; z++)
                    getVoxel(*v.getVoxel(Vector3i(x,y,z)));
    }

    Matrix4f getMatrix4f()
    {
        getTensor(double, Real64, 2);
        assert(dims[0] == 4); assert(dims[1] == 4);

        // read row-major matrix
        Matrix4f m;
        for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) m(x, y) = a[y * 4 + x];

        releaseTensor(Real64);
        return m;
    }

    Vector4f getVector4f()
    {
        getTensor(float, Real32, 1);
        assert(dims[0] == 4);
        Vector4f m(a);
        releaseTensor(Real32);
        return m;
    }

    template<int X>
    VectorX<float, X> getVectorXf()
    {
        getTensor(float, Real32, 1);
        assert(dims[0] == X);
        VectorX<float, X> m(a);
        releaseTensor(Real32);
        return m;
    }



    void putMatrix4f(Matrix4f m) {
        int dims[] = {4, 4};
        const char* heads[] = {"List", "List"};

        // write row-major matrix
        float a[4*4];
        for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) a[y * 4 + x] = m(x, y);

        WSPutReal32Array(stdlink, a, dims, heads, 2);
    }
}
using namespace WSTP;





extern "C" {

    void assertFalse() {
        assert(false);
        WL_RETURN_VOID();
    }
    void assertGPUFalse() {
        LAUNCH_KERNEL(gpuFalse, 1, 1);
        WL_RETURN_VOID();
    }

    int createScene(double voxelSize_) {
        return addScene(new Scene(voxelSize_));
    }

    double getSceneVoxelSize(int id) {
        return getScene(id)->getVoxelSize();
    }

    int countVoxelBlocks(int id) {
        return getScene(id)->countVoxelBlocks();
    }

    // Manually insert a *new* voxel block
    // TODO what should happen when it already exists?
    // format: c.f. getVoxelBlock
    void putVoxelBlock(int id) {
        auto s = getScene(id);

        int vbCountBefore = s->countVoxelBlocks();

        ITMVoxelBlock receivedVb;
        getVoxelBlock(receivedVb);
        assert(receivedVb.getPos() != INVALID_VOXEL_BLOCK_POS);

        auto& sceneVb = *s->getVoxelBlockForSequenceNumber(s->performVoxelBlockAllocation(receivedVb.getPos()));
        assert(sceneVb.getPos() == receivedVb.getPos());
        sceneVb = receivedVb; // copy

        // synchronize (otherwise, gpu code hangs) - TODO why exactly?
        s->voxelBlockHash->naKey.Synchronize();
        s->voxelBlockHash->needsAllocation.Synchronize();
        s->voxelBlockHash->hashMap_then_excessList.Synchronize();
        s->localVBA.Synchronize();

        assert(vbCountBefore + 1 == s->countVoxelBlocks());
        cudaDeviceSynchronize();
        WL_RETURN_VOID();
    }

    // {__VoxelBlock} at most max many. 0 or negative numbers mean all
    void getVoxelBlock(int id, int i) {
        auto s = getScene(id);
        const int n = s->voxelBlockHash->getLowestFreeSequenceNumber();
        assert(i >= 1 /* valid sequence nubmers start at 1 - TODO this knowledge should not be repeated here */ && i < n, "there is no voxelBlock with index %d, valid indices are 1 to %d", i, n-1);
        putVoxelBlock(s->localVBA[i]);
    }

    void serializeScene(int id, char* fn) {
        getScene(id)->serialize(binopen_write(fn));
        WL_RETURN_VOID();
    }

    void deserializeScene(int id, char* fn) {
        auto s = getScene(id);
        s->deserialize(binopen_read(fn));
        WL_RETURN_VOID();
    }

    void meshScene(int id, char* fn) {
        cudaDeviceSynchronize();
        MeshScene(fn, getScene(id));
        WL_RETURN_VOID();
    }

    // TODO fix
    void initFineFromCoarse(int idFine, int idCoarse) {
        cudaDeviceSynchronize();
        resample::initFineFromCoarse(getScene(idFine), getScene(idCoarse));
        WL_RETURN_VOID();
    }

    void computeArtificialLighting(int id, double* dir, long n) {
        assert(n == 3);

        using namespace Lighting;
        lightNormal = Vector3f(comp012(dir)).normalised();
        assert(abs(length(lightNormal) - 1) < 0.1);
        CURRENT_SCENE_SCOPE(getScene(id));
        computeArtificialLighting<DirectionalArtificialLighting>();
        WL_RETURN_VOID();
    }

    void estimateLighting(int id) {

        using namespace Lighting;
        CURRENT_SCENE_SCOPE(getScene(id));
        LightingModel l = estimateLightingModel();

        putFloatArray(l.l.data(), l.l.size());
        WL_RETURN_VOID();
    }

    void buildSphereScene(int id, double rad) {
        CURRENT_SCENE_SCOPE(getScene(id));
        TestScene::buildSphereScene(rad);
        WL_RETURN_VOID();
    }
    

    ITMView* render(ITMPose pose, string shader, const ITMIntrinsics intrin) {
        assert(intrin.imageSize().area(), "calibration must be loaded");
        assert(Scene::getCurrentScene());
        Vector2i sz = intrin.imageSize();
        auto outputImage = new ITMUChar4Image(sz);
        auto outputDepthImage = new ITMFloatImage(sz);

        return RenderImage(pose, intrin, shader);
    }

    ITMIntrinsics getIntrinsics() {

        ITMIntrinsics intrin;
        auto i = getVectorXf<6>();
        intrin.fx = i[0];
        intrin.fy = i[1];
        intrin.px = i[2];
        intrin.py = i[3];
        intrin.sizeX = i[4];
        intrin.sizeY = i[5];
        return intrin;
    }

    void renderScene(int id, char* shader) {
        CURRENT_SCENE_SCOPE(getScene(id));

        ITMPose p(getMatrix4f());

        auto intrin = getIntrinsics();
        
        auto v = render(p, shader, intrin);

        // Output: {rgbImage, depthImageData}
        WSPutFunction(stdlink, "List", 2);
        // rgb(a)
        {
            putImageRGBA8(v->colorImage->image);
        }

        // depth
        {
            putImageFloat(v->depthImage->image);
        }
    }

    void processFrame(int doTracking, int id) {
        // rgbaByteImage
        Vector2i rgbSz;
        ITMUChar4Image* rgbaImage;
        {
            // rgbaByteImage_ /;TensorQ[rgbaByteImage, IntegerQ] &&Last@Dimensions@rgbaByteImage == 4
            getTensor(unsigned char, Integer8, 3);
            assert(dims[0] > 1); assert(dims[1] > 1); assert(dims[2] == 4);

            rgbSz = Vector2i(dims[1], dims[0]);
            assert(rgbSz.width > rgbSz.height);

            rgbaImage = new ITMUChar4Image(rgbSz);
            rgbaImage->SetFrom((char*)a, rgbSz.area());
            
            releaseTensor(Integer8);
        }

        //depthImage_
        Vector2i depthSz;
        ITMFloatImage* depthImage;
        {
            // depthData_?NumericMatrixQ
            getTensor(float, Real32, 2);
            assert(dims[0] > 1); assert(dims[1] > 1); 
            depthSz = Vector2i(dims[1], dims[0]);
            assert(depthSz.width > depthSz.height);

            depthImage = new ITMFloatImage(depthSz);
            depthImage->SetFrom((char*)a, depthSz.area());

            releaseTensor(Real32);
        }
        assert(depthSz.area() <= rgbSz.area());

        // poseWorldToView_?poseMatrixQ
        auto poseWorldToView = getMatrix4f();

        ITMRGBDCalib calib;
        // intrinsicsRgb : NamelessIntrinsicsPattern[]
        calib.intrinsics_rgb = getIntrinsics();
        assert(calib.intrinsics_rgb.imageSize() == rgbSz);
        // intrinsicsD : NamelessIntrinsicsPattern[]
        calib.intrinsics_d = getIntrinsics();
        assert(calib.intrinsics_d.imageSize() == depthSz);

        // rgbToDepth_?poseMatrixQ
        calib.trafo_rgb_to_depth.SetFrom(getMatrix4f());

        CURRENT_SCENE_SCOPE(getScene(id));

        // Finally
        assert(rgbaImage->noDims.area() > 1);
        assert(depthImage->noDims.area() > 1);

        cudaDeviceSynchronize();
        if (currentView) delete currentView;
        currentView = new ITMView(calib);

        currentView->ChangeImages(rgbaImage, depthImage);
        currentView->ChangePose(poseWorldToView);

        if (doTracking) {
            Matrix4f old_M_d = currentView->depthImage->eyeCoordinates->fromGlobal;
            assert(old_M_d == currentView->depthImage->eyeCoordinates->fromGlobal);
            ImprovePose();
            assert(old_M_d != currentView->depthImage->eyeCoordinates->fromGlobal);

            cudaDeviceSynchronize();
            // [
            WSPutFunction(stdlink, "List", 3);
            putImageFloat4(rendering::raycastResult->image);
            putImageFloat4(tracking::lastFrameICPMap->image);
            putImageFloat4(tracking::lastFrameICPMap->normalImage);
            // ]
        }
        cudaDeviceSynchronize();

        Fuse();

        //if (doTracking)
        // ;// putMatrix4f(currentView->depthImage->eyeCoordinates->fromGlobal);
        //else 
        WL_RETURN_VOID(); // only changes state, no immediate result
    }

}









