---
name: c-build
description: Standard build and test workflow for C/C++ projects using CMake and Ninja.
---

# C/C++ Build Workflow

Configure, build and test a CMake project.

## Configure

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
```

## Build

```bash
cmake --build build
```

## Test

```bash
ctest --test-dir build --output-on-failure
```

## Clean

```bash
cmake --build build --target clean
```
