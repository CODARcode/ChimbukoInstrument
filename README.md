# Introduction

This repo provides a convenience wrapper for instrumenting source code using SALT-FM and Perfstubs. SALT-FM inserts Perfstubs timer hooks into every function, which can be detected by	TAU at runtime.

# Installation

First, install SALT-FM on top of the salt-dev Docker environment. (Unfortunately this is a large image. ):
``
./build-docker-dev-with-salt.sh
``

# Usage
To instrument the code,	use
``
./salt-instrument.sh <source directory>
``
This will create a recursive copy of the source directory with name `${source_directory}_inst` and replace code files with instrumented versions.

To build the instrumented code, install [perfstubs](https://github.com/UO-OACISS/perfstubs.git) either manually or via [spack](https://github.com/spack/spack.git). 

To your include paths, add `-I/path/to/installof/perfstubs/include -I/path/to/this/repo` (the latter is needed for the `timer_wrap_gpu.h` header which works around compilation issues with GPU kernels and enables the perfstubs timers).

To your link line, add `-L/path/to/installof/perfstubs/lib -lperfstubs`

The resulting compiled executables should now be instrumented and ready for **tau_exec**.

## Options
`salt-instrument.sh` also supports the following command line arguments:

- `--overwrite`    Delete and recreate the `${source_directory}_inst` directory if it already exists instead of exiting with an error.

- `--tau_select_file=<filename>`  Pass a TAU select file to control the instrumentation at function and/or file-level granularity. Refer to [TAU's documentation](https://www.cs.uoregon.edu/research/tau/docs/html-docs/latest/taucompiler/taucompiler.html) for guidance. Note that at present, function strings beginning with a wildcard (#) must be placed in quotation marks (e.g. `"#excluded_funcs"` rather than `#excluded_funcs`)
