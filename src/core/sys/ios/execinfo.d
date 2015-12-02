/**
 * D header file for iOS.
 *
 * Copyright: Copyright Martin Nowak 2012.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Martin Nowak
 */
module core.sys.ios.execinfo;

version (iOS):
extern (C):
nothrow:

int backtrace(void** buffer, int size);
char** backtrace_symbols(const(void*)* buffer, int size);
void backtrace_symbols_fd(const(void*)* buffer, int size, int fd);
