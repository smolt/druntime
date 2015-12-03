/**
 * D header file for iOS.
 *
 * Copyright: Copyright Sean Kelly 2008 - 2009.
 * License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Sean Kelly
 */

/*          Copyright Sean Kelly 2008 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.sys.ios.mach.port;

version (iOS):
extern (C):

version( X86 )
    version = i386;
version( X86_64 )
    version = i386;
version( i386 )
{
    alias uint        natural_t;
    alias natural_t   mach_port_t;
}
