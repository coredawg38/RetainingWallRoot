# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Create build directory and configure
mkdir build && cd build
cmake ..

# Build
make

# Install (required for tests to access auxiliary files)
make install

# Build with custom install prefix
cmake .. -DCMAKE_INSTALL_PREFIX=/opt/mailio

# Build static library instead of shared
cmake .. -DBUILD_SHARED_LIBS=OFF

# Disable examples/tests/docs
cmake .. -DMAILIO_BUILD_EXAMPLES=OFF -DMAILIO_BUILD_TESTS=OFF -DMAILIO_BUILD_DOCUMENTATION=OFF
```

## Running Tests

Tests require installation first to copy auxiliary files (aleph0.png, cv.txt).

```bash
cd build
make install
ctest                           # Run all tests
ctest -R test_message           # Run specific test
./test/test_message             # Run test executable directly
```

Tests use Boost.Test framework. Test source is in `test/test_message.cpp`.

## Architecture Overview

mailio is a C++17 library for MIME format and email protocols (SMTP, POP3, IMAP).

### Core Class Hierarchy

- `codec` - Base class with encoding utilities (hex conversion, escaping, charset handling)
  - `base64`, `quoted_printable`, `bit7`, `bit8`, `binary`, `percent`, `q_codec` - Encoding implementations
- `mime` - MIME part parser/formatter with headers, content types, multipart support
  - `message` - Email message extending mime with recipients, subject, date handling
- `dialog` - Low-level network I/O with Boost.Asio (TCP/TLS connections)
  - `smtp`, `pop3`, `imap` - Protocol implementations using dialog for network

### Key Design Patterns

**Connection Priority**: All protocols (SMTP/POP3/IMAP) follow the same TLS priority order:
1. STARTTLS (default) - upgrades plain connection to TLS
2. SSL - direct TLS connection
3. Plain TCP - unencrypted

Configure via `start_tls(bool)` and `ssl_options(std::optional<...>)`.

**MIME Structure**: Messages are recursive - a `mime` object can contain other `mime` parts for multipart messages. The `message` class adds email-specific headers on top.

### Dependencies

- C++17 standard
- Boost 1.81+ (date_time, regex, asio, unit_test_framework for tests)
- OpenSSL (for TLS support)
- CMake 3.16.3+

### Namespace

All code is in the `mailio` namespace. Public API is exported via `MAILIO_EXPORT` macro.
