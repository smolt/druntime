/**
 * Import to use older OS X 32-bit inode functions and structs.
 *
 * Copyright: Copyright Digital Mars 2015.
 * License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
module core.sys.osx.sys.stat_ino32;

version (OSX):

public import core.sys.posix.sys.stat;

alias stat = core.sys.posix.sys.stat.stat32;
alias stat_t = core.sys.posix.sys.stat.stat32_t;
alias ino_t = core.sys.posix.sys.types.ino32_t;
