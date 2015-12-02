/**
 * D header file for iOS
 *
 * Authors: Martin Nowak
 */
module core.sys.ios.sys.cdefs;

version (iOS):

public import core.sys.posix.config;

// http://www.opensource.apple.com/source/xnu/xnu-2422.115.4/bsd/sys/cdefs.h
enum _DARWIN_C_SOURCE = true;

enum __DARWIN_C_FULL = 900000L;
enum __DARWIN_C_LEVEL = __DARWIN_C_FULL;
