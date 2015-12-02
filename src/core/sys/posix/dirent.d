/**
 * D header file for POSIX.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Sean Kelly,
              Alex Rønne Petersn
 * Standards: The Open Group Base Specifications Issue 6, IEEE Std 1003.1, 2004 Edition
 */

/*          Copyright Sean Kelly 2005 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.sys.posix.dirent;

private import core.sys.posix.config;
public import core.sys.posix.sys.types; // for ino_t

version( OSX ) version = Darwin;
version( iOS ) version = Darwin;

version (Posix):
extern (C):
nothrow:
@nogc:

//
// Required
//
/*
DIR

struct dirent
{
    char[] d_name;
}

int     closedir(DIR*);
DIR*    opendir(in char*);
dirent* readdir(DIR*);
void    rewinddir(DIR*);
*/

version( CRuntime_Glibc )
{
    // NOTE: The following constants are non-standard Linux definitions
    //       for dirent.d_type.
    enum
    {
        DT_UNKNOWN  = 0,
        DT_FIFO     = 1,
        DT_CHR      = 2,
        DT_DIR      = 4,
        DT_BLK      = 6,
        DT_REG      = 8,
        DT_LNK      = 10,
        DT_SOCK     = 12,
        DT_WHT      = 14
    }

    struct dirent
    {
        ino_t       d_ino;
        off_t       d_off;
        ushort      d_reclen;
        ubyte       d_type;
        char[256]   d_name;
    }

    struct DIR
    {
        // Managed by OS
    }

    static if( __USE_FILE_OFFSET64 )
    {
        dirent* readdir64(DIR*);
        alias   readdir64 readdir;
    }
    else
    {
        dirent* readdir(DIR*);
    }
}
else version( Darwin )
{
    enum
    {
        DT_UNKNOWN  = 0,
        DT_FIFO     = 1,
        DT_CHR      = 2,
        DT_DIR      = 4,
        DT_BLK      = 6,
        DT_REG      = 8,
        DT_LNK      = 10,
        DT_SOCK     = 12,
        DT_WHT      = 14
    }

    // _DARWIN_FEATURE_64_BIT_INODE dirent is default for Mac OSX >10.5 and is
    // only meaningful type for other OS X/Darwin variants (e.g. iOS).
    // man dir(5) has some info, man stat(2) gives details.
    struct dirent64
    {
        ino64_t     d_ino;
        ulong       d_seekoff;
        ushort      d_reclen;
        ushort      d_namlen;
        ubyte       d_type;
        char[1024]  d_name;
    }

    align(4)
    struct dirent32
    {
        ino32_t     d_ino;
        ushort      d_reclen;
        ubyte       d_type;
        ubyte       d_namlen;
        char[256]   d_name;
    }

    alias dirent = dirent64;

    struct DIR
    {
        // Managed by OS
    }

    // OS X maintains backwards compatibility with older binaries using 32-bit
    // inode functions by appending $INODE64 to newer 64-bit inode functions.
    version( OSX )
    {
        pragma(mangle, "readdir$INODE64") dirent64* readdir64(DIR*);
        pragma(mangle, "readdir")         dirent32* readdir32(DIR*);
        alias readdir = readdir64;
    }
    else
    {
        dirent* readdir(DIR*);
    }
}
else version( FreeBSD )
{
    enum
    {
        DT_UNKNOWN  = 0,
        DT_FIFO     = 1,
        DT_CHR      = 2,
        DT_DIR      = 4,
        DT_BLK      = 6,
        DT_REG      = 8,
        DT_LNK      = 10,
        DT_SOCK     = 12,
        DT_WHT      = 14
    }

    align(4)
    struct dirent
    {
        uint      d_fileno;
        ushort    d_reclen;
        ubyte     d_type;
        ubyte     d_namlen;
        char[256] d_name;
    }

    alias void* DIR;

    dirent* readdir(DIR*);
}
else version (Solaris)
{
    struct dirent
    {
        ino_t d_ino;
        off_t d_off;
        ushort d_reclen;
        char[1] d_name;
    }

    struct DIR
    {
        int dd_fd;
        int dd_loc;
        int dd_size;
        char* dd_buf;
    }

    static if (__USE_LARGEFILE64)
    {
        dirent* readdir64(DIR*);
        alias readdir64 readdir;
    }
    else
    {
        dirent* readdir(DIR*);
    }
}
else version( CRuntime_Bionic )
{
    enum
    {
        DT_UNKNOWN  = 0,
        DT_FIFO     = 1,
        DT_CHR      = 2,
        DT_DIR      = 4,
        DT_BLK      = 6,
        DT_REG      = 8,
        DT_LNK      = 10,
        DT_SOCK     = 12,
        DT_WHT      = 14
    }

    struct dirent
    {
        ulong       d_ino;
        long        d_off;
        ushort      d_reclen;
        ubyte       d_type;
        char[256]   d_name;
    }

    struct DIR
    {
    }

    dirent* readdir(DIR*);
}
else
{
    static assert(false, "Unsupported platform");
}

// Only OS X out of the Darwin family needs special treatment.  Other Darwins
// are fine with normal symbol names for these functions
version( OSX )
{
    version( D_LP64 )
    {
        int     closedir(DIR*);
        pragma(mangle, "opendir$INODE64") DIR* opendir64(in char*);
        pragma(mangle, "opendir")         DIR* opendir32(in char*);
        alias opendir = opendir64;

        pragma(mangle, "rewinddir$INODE64") void rewinddir64(DIR*);
        pragma(mangle, "rewinddir")         void rewinddir32(DIR*);
        alias rewinddir = rewinddir64;
    }
    else
    {
        // 32-bit mangles __DARWIN_UNIX03 specific functions with $UNIX2003 to
        // maintain backward compatibility with binaries build pre 10.5
        pragma(mangle, "closedir$UNIX2003")          int closedir(DIR*);
        pragma(mangle, "opendir$INODE64$UNIX2003")   DIR* opendir64(in char*);
        pragma(mangle, "opendir$UNIX2003")           DIR* opendir32(in char*);
        alias opendir = opendir64;

        pragma(mangle, "rewinddir$INODE64$UNIX2003") void rewinddir64(DIR*);
        pragma(mangle, "rewinddir$UNIX2003")         void rewinddir32(DIR*);
        alias rewinddir = rewinddir64;
    }
}
else
{
    int     closedir(DIR*);
    DIR*    opendir(in char*);
    //dirent* readdir(DIR*);
    void    rewinddir(DIR*);
}

//
// Thread-Safe Functions (TSF)
//
/*
int readdir_r(DIR*, dirent*, dirent**);
*/

version( CRuntime_Glibc )
{
  static if( __USE_LARGEFILE64 )
  {
    int   readdir64_r(DIR*, dirent*, dirent**);
    alias readdir64_r readdir_r;
  }
  else
  {
    int readdir_r(DIR*, dirent*, dirent**);
  }
}
else version( OSX )
{
    pragma(mangle, "readdir_r$INODE64")
        int readdir64_r(DIR*, dirent64*, dirent64**);
    pragma(mangle, "readdir_r")
        int readdir32_r(DIR*, dirent32*, dirent32**);
    alias readdir_r = readdir64_r;
}
else version( iOS )
{
    int readdir_r(DIR*, dirent*, dirent**);
}
else version( FreeBSD )
{
    int readdir_r(DIR*, dirent*, dirent**);
}
else version (Solaris)
{
    static if (__USE_LARGEFILE64)
    {
        int readdir64_r(DIR*, dirent*, dirent**);
        alias readdir64_r readdir_r;
    }
    else
    {
        int readdir_r(DIR*, dirent*, dirent**);
    }
}
else version( CRuntime_Bionic )
{
    int readdir_r(DIR*, dirent*, dirent**);
}
else
{
    static assert(false, "Unsupported platform");
}

//
// XOpen (XSI)
//
/*
void   seekdir(DIR*, c_long);
c_long telldir(DIR*);
*/

version( CRuntime_Glibc )
{
    void   seekdir(DIR*, c_long);
    c_long telldir(DIR*);
}
else version( FreeBSD )
{
    void   seekdir(DIR*, c_long);
    c_long telldir(DIR*);
}
else version( OSX )
{
    version( D_LP64 )
    {
        pragma(mangle, "seekdir$INODE64") void seekdir64(DIR*, c_long);
        pragma(mangle, "seekdir")         void seekdir32(DIR*, c_long);
        alias seekdir = seekdir64;

        pragma(mangle, "telldir$INODE64") c_long telldir64(DIR*);
        pragma(mangle, "telldir")         c_long telldir32(DIR*);
        alias telldir = telldir64;
    }
    else
    {
        // 32-bit mangles __DARWIN_UNIX03 specific functions with $UNIX2003 to
        // maintain backward compatibility with binaries build pre 10.5
        pragma(mangle, "seekdir$INODE64$UNIX2003") void seekdir64(DIR*, c_long);
        pragma(mangle, "seekdir$UNIX2003") void seekdir32(DIR*, c_long);
        alias seekdir = seekdir64;

        pragma(mangle, "telldir$INODE64$UNIX2003") c_long telldir64(DIR*);
        pragma(mangle, "telldir$UNIX2003") c_long telldir32(DIR*);
        alias telldir = telldir64;
    }
}
else version( iOS )
{
    void   seekdir(DIR*, c_long);
    c_long telldir(DIR*);
}
else version (Solaris)
{
    c_long telldir(DIR*);
    void seekdir(DIR*, c_long);
}
else version (CRuntime_Bionic)
{
}
else
{
    static assert(false, "Unsupported platform");
}
