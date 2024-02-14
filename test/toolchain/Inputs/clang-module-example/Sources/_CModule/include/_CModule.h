#include <stddef.h> // Clang header should be found
#if __wasi__
# include <wasi/api.h> // wasi-libc header
#endif
