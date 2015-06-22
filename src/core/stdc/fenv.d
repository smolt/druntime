/**
 * D header file for C99.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly
 * Source:    $(DRUNTIMESRC core/stdc/_fenv.d)
 * Standards: ISO/IEC 9899:1999 (E)
 */

module core.stdc.fenv;

extern (C):
@system:
nothrow:
@nogc:

version (PPC)   version = PPC_Any;
version (PPC64) version = PPC_Any;

version (X86) version = X86_Any;
version (X86_64) version = X86_Any;

version( Windows )
{
    struct fenv_t
    {
        ushort    status;
        ushort    control;
        ushort    round;
        ushort[2] reserved;
    }

    alias int fexcept_t;
}
else version( linux )
{
    // https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/x86/fpu/bits/fenv.h
    version (X86)
    {
        struct fenv_t
        {
            ushort __control_word;
            ushort __unused1;
            ushort __status_word;
            ushort __unused2;
            ushort __tags;
            ushort __unused3;
            uint   __eip;
            ushort __cs_selector;
            ushort __opcode;
            uint   __data_offset;
            ushort __data_selector;
            ushort __unused5;
        }

        alias fexcept_t = ushort;
    }
    // https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/x86/fpu/bits/fenv.h
    else version (X86_64)
    {
        struct fenv_t
        {
            ushort __control_word;
            ushort __unused1;
            ushort __status_word;
            ushort __unused2;
            ushort __tags;
            ushort __unused3;
            uint   __eip;
            ushort __cs_selector;
            ushort __opcode;
            uint   __data_offset;
            ushort __data_selector;
            ushort __unused5;
            uint   __mxcsr;
        }

        alias fexcept_t = ushort;
    }
    // https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/mips/bits/fenv.h
    else version (MIPS32)
    {
        struct fenv_t
        {
            uint   __fp_control_register;
        }

        alias fexcept_t = ushort;
    }
    // https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/mips/bits/fenv.h
    else version (MIPS64)
    {
        struct fenv_t
        {
            uint   __fp_control_register;
        }

        alias fexcept_t = ushort;
    }
    // https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/arm/bits/fenv.h
    else version (ARM)
    {
        struct fenv_t
        {
            uint __cw;
        }

        alias fexcept_t = uint;
    }
    // https://sourceware.org/git/?p=glibc.git;a=blob;f=sysdeps/powerpc/bits/fenv.h
    else version (PPC_Any)
    {
        alias fenv_t = double;
        alias fexcept_t = uint;
    }
    else
    {
        static assert(0, "Unimplemented architecture");
    }
}
else version ( OSX )
{
    version ( ARM_Soft )
    {
        alias fenv_t = int;
        alias fexcept_t = ushort;
    }
    else version ( ARM )
    {
        struct fenv_t
        {
            uint __fpscr;
            uint __reserved0;
            uint __reserved1;
            uint __reserved2;
        }

        alias ushort fexcept_t;
    }
    else version ( AArch64 )
    {
        struct fenv_t {
            ulong __fpsr;
            ulong __fpcr;
        }

        alias ushort fexcept_t;
    }
    else version ( PPC )
    {
        alias uint fenv_t;
        alias uint fexcept_t;
    }
    else version ( X86_Any )
    {
        struct fenv_t
        {
            ushort  __control;
            ushort  __status;
            uint    __mxcsr;
            byte[8] __reserved;
        }

        alias ushort fexcept_t;
    }
}
else version ( FreeBSD )
{
    struct fenv_t
    {
        ushort __control;
        ushort __mxcsr_hi;
        ushort __status;
        ushort __mxcsr_lo;
        uint __tag;
        byte[16] __other;
    }

    alias ushort fexcept_t;
}
else version( Android )
{
    version(X86)
    {
        struct fenv_t
        {
            ushort   __control;
            ushort   __mxcsr_hi;
            ushort   __status;
            ushort   __mxcsr_lo;
            uint     __tag;
            byte[16] __other;
        }

        alias ushort fexcept_t;
    }
    else
    {
        static assert(false, "Architecture not supported.");
    }
}
else version( Solaris )
{
    import core.stdc.config : c_ulong;

    enum FEX_NUM_EXC = 12;

    struct fex_handler_t
    {
        int             __mode;
        void function() __handler;
    }

    struct fenv_t
    {
        fex_handler_t[FEX_NUM_EXC]  __handler;
        c_ulong                     __fsr;
    }

    alias int fexcept_t;
}
else
{
    static assert( false, "Unsupported platform" );
}

version ( OSX )
{
    version ( ARM_Soft )
    {
        enum
        {
            FE_ALL_EXCEPT = 0,
            FE_TONEAREST = 0
        }
    }
    else version ( ARM )
    {
        enum
        {
            FE_INEXACT     = 0x0010,
            FE_UNDERFLOW   = 0x0008,
            FE_OVERFLOW    = 0x0004,
            FE_DIVBYZERO   = 0x0002,
            FE_INVALID     = 0x0001,
            FE_FLUSHTOZERO = 0x0080, /// ARM-specific input denormal exception
            FE_ALL_EXCEPT  = 0x009f,
            FE_TONEAREST   = 0x00000000,
            FE_UPWARD      = 0x00400000,
            FE_DOWNWARD    = 0x00800000,
            FE_TOWARDZERO  = 0x00C00000
        }
    }
    else version ( AArch64 )
    {
        // same as ARM - maybe should combine
        enum
        {
            FE_INEXACT     = 0x0010,
            FE_UNDERFLOW   = 0x0008,
            FE_OVERFLOW    = 0x0004,
            FE_DIVBYZERO   = 0x0002,
            FE_INVALID     = 0x0001,
            FE_FLUSHTOZERO = 0x0080, /// ARM-specific input denormal exception
            FE_ALL_EXCEPT  = 0x009f,
            FE_TONEAREST   = 0x00000000,
            FE_UPWARD      = 0x00400000,
            FE_DOWNWARD    = 0x00800000,
            FE_TOWARDZERO  = 0x00C00000
        }
    }
    else version ( X86_Any )
    {
        enum
        {
            FE_INEXACT         = 0x0020,
            FE_UNDERFLOW       = 0x0010,
            FE_OVERFLOW        = 0x0008,
            FE_DIVBYZERO       = 0x0004,
            FE_INVALID         = 0x0001,
            FE_DENORMALOPERAND = 0x0002,   /// Intel-specific denormal operand
            FE_ALL_EXCEPT      = 0x003f,
            FE_TONEAREST       = 0x0000,
            FE_DOWNWARD        = 0x0400,
            FE_UPWARD          = 0x0800,
            FE_TOWARDZERO      = 0x0c00
        }
    }
    else version ( PPC )
    {
        enum
        {
            FE_INEXACT    = 0x02000000,
            FE_DIVBYZERO  = 0x04000000,
            FE_UNDERFLOW  = 0x08000000,
            FE_OVERFLOW   = 0x10000000,
            FE_INVALID    = 0x20000000,
            FE_ALL_EXCEPT = 0x3E000000,
            FE_TONEAREST  = 0x00000000,
            FE_TOWARDZERO = 0x00000001,
            FE_UPWARD     = 0x00000002,
            FE_DOWNWARD   = 0x00000003
        }
    }
    else
    {
        static assert( false, "Unsupported OSX architecture" );
    }
}
else
enum
{
    FE_INVALID      = 1,
    FE_DENORMAL     = 2, // non-standard
    FE_DIVBYZERO    = 4,
    FE_OVERFLOW     = 8,
    FE_UNDERFLOW    = 0x10,
    FE_INEXACT      = 0x20,
    FE_ALL_EXCEPT   = 0x3F,
    FE_TONEAREST    = 0,
    FE_UPWARD       = 0x800,
    FE_DOWNWARD     = 0x400,
    FE_TOWARDZERO   = 0xC00,
}

version( Windows )
{
  version( Win64 ) // requires MSVCRT >= 2013
  {
    private extern __gshared fenv_t _Fenv0;
    fenv_t* FE_DFL_ENV = &_Fenv0;
  }
  else
  {
    private extern __gshared fenv_t _FE_DFL_ENV;
    fenv_t* FE_DFL_ENV = &_FE_DFL_ENV;
  }
}
else version( linux )
{
    fenv_t* FE_DFL_ENV = cast(fenv_t*)(-1);
}
else version( OSX )
{
    private extern __gshared const fenv_t _FE_DFL_ENV;
    enum FE_DFL_ENV = &_FE_DFL_ENV;
}
else version( FreeBSD )
{
    private extern const fenv_t __fe_dfl_env;
    const fenv_t* FE_DFL_ENV = &__fe_dfl_env;
}
else version( Android )
{
    private extern const fenv_t __fe_dfl_env;
    const fenv_t* FE_DFL_ENV = &__fe_dfl_env;
}
else version( Solaris )
{
    private extern const fenv_t __fenv_def_env;
    const fenv_t* FE_DFL_ENV = &__fenv_def_env;
}
else
{
    static assert( false, "Unsupported platform" );
}

void feraiseexcept(int excepts);
void feclearexcept(int excepts);

int fetestexcept(int excepts);
int feholdexcept(fenv_t* envp);

void fegetexceptflag(fexcept_t* flagp, int excepts);
void fesetexceptflag(in fexcept_t* flagp, int excepts);

int fegetround();
int fesetround(int round);

void fegetenv(fenv_t* envp);
void fesetenv(in fenv_t* envp);
void feupdateenv(in fenv_t* envp);

version(LDC)
{
    void FORCE_EVAL(T)(T x) @nogc nothrow
    {
        import std.traits, ldc.llvmasm;
        static if (isFloatingPoint!(T))
        {
            version (ARM)
                __asm("", "w", x);
            else version (AArch64)
                     __asm("", "w", x);
            else version (X86_Any)
                     __asm("", "f", x);
            else
                static assert(false, "Not implemented for this architecture");
        }
        else
            __asm("", "r", x);
    }
}
