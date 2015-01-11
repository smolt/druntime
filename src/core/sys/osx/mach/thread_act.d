/**
 * D header file for OSX.
 *
 * Copyright: Copyright Sean Kelly 2008 - 2009.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   Sean Kelly
 */

/*          Copyright Sean Kelly 2008 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.sys.osx.mach.thread_act;

version (OSX):
extern (C):
nothrow:

public import core.sys.osx.mach.kern_return;
public import core.sys.osx.mach.port;

version( X86 )
    version = i386;
version( X86_64 )
    version = i386;
version( i386 )
{
    alias mach_port_t thread_act_t;
    alias void        thread_state_t;
    alias int         thread_state_flavor_t;
    alias natural_t   mach_msg_type_number_t;

    enum
    {
        x86_THREAD_STATE32      = 1,
        x86_FLOAT_STATE32       = 2,
        x86_EXCEPTION_STATE32   = 3,
        x86_THREAD_STATE64      = 4,
        x86_FLOAT_STATE64       = 5,
        x86_EXCEPTION_STATE64   = 6,
        x86_THREAD_STATE        = 7,
        x86_FLOAT_STATE         = 8,
        x86_EXCEPTION_STATE     = 9,
        x86_DEBUG_STATE32       = 10,
        x86_DEBUG_STATE64       = 11,
        x86_DEBUG_STATE         = 12,
        THREAD_STATE_NONE       = 13,
    }

    struct x86_thread_state32_t
    {
        uint    eax;
        uint    ebx;
        uint    ecx;
        uint    edx;
        uint    edi;
        uint    esi;
        uint    ebp;
        uint    esp;
        uint    ss;
        uint    eflags;
        uint    eip;
        uint    cs;
        uint    ds;
        uint    es;
        uint    fs;
        uint    gs;
    }

    struct x86_thread_state64_t
    {
        ulong   rax;
        ulong   rbx;
        ulong   rcx;
        ulong   rdx;
        ulong   rdi;
        ulong   rsi;
        ulong   rbp;
        ulong   rsp;
        ulong   r8;
        ulong   r9;
        ulong   r10;
        ulong   r11;
        ulong   r12;
        ulong   r13;
        ulong   r14;
        ulong   r15;
        ulong   rip;
        ulong   rflags;
        ulong   cs;
        ulong   fs;
        ulong   gs;
    }

    struct x86_state_hdr_t
    {
        int     flavor;
        int     count;
    }

    struct x86_thread_state_t
    {
        x86_state_hdr_t             tsh;
        union _uts
        {
            x86_thread_state32_t    ts32;
            x86_thread_state64_t    ts64;
        }
        _uts                        uts;
    }

    enum : mach_msg_type_number_t
    {
        x86_THREAD_STATE32_COUNT = cast(mach_msg_type_number_t)( x86_thread_state32_t.sizeof / int.sizeof ),
        x86_THREAD_STATE64_COUNT = cast(mach_msg_type_number_t)( x86_thread_state64_t.sizeof / int.sizeof ),
        x86_THREAD_STATE_COUNT   = cast(mach_msg_type_number_t)( x86_thread_state_t.sizeof / int.sizeof ),
    }

    alias x86_THREAD_STATE          MACHINE_THREAD_STATE;
    alias x86_THREAD_STATE_COUNT    MACHINE_THREAD_STATE_COUNT;

    mach_port_t   mach_thread_self();
    kern_return_t thread_suspend(thread_act_t);
    kern_return_t thread_resume(thread_act_t);
    kern_return_t thread_get_state(thread_act_t, thread_state_flavor_t, thread_state_t*, mach_msg_type_number_t*);
}
else version ( ARM )
{
    alias mach_port_t thread_act_t;
    alias void        thread_state_t;
    alias int         thread_state_flavor_t;
    alias natural_t   mach_msg_type_number_t;

    enum
    {
        ARM_THREAD_STATE = 1,
        ARM_VFP_STATE = 2,
        ARM_EXCEPTION_STATE = 3,
        ARM_DEBUG_STATE = 4,   // pre-armv8
        THREAD_STATE_NONE = 5,
        ARM_THREAD_STATE64 = 6,
        ARM_EXCEPTION_STATE64 = 7,
        // ARM_THREAD_STATE_LAST (legacy) 8
        ARM_THREAD_STATE32 = 9,
        ARM_DEBUG_STATE32 = 14,
        ARM_DEBUG_STATE64 = 15,
        ARM_NEON_STATE = 16,
        ARM_NEON_STATE64 = 17
    }

    struct arm_thread_state32_t
    {
	uint r[13];                      // r0-r12
	uint sp;                         // r13 (stack ptr)
	uint lr;                         // r14 (link register)
	uint pc;                         // r15 (program counter)
	uint cpsr;                       // current program status register
    }

    struct arm_thread_state64_t
    {
	ulong x[29];                      // x0-x28
	ulong fp;                         // x29 (frame ptr)
	ulong lr;                         // x30 (link register)
	ulong sp;                         // x31 (stack ptr)
	ulong pc;                         // program counter
	uint cpsr;                        // current program status register
    }

    struct arm_state_hdr_t
    {
        uint flavor;
        uint count;
    }

    struct arm_unified_thread_state_t
    {
        arm_state_hdr_t             ash;
        union _uts
        {
            arm_thread_state32_t    ts_32;
            arm_thread_state64_t    ts_64;
        }
        _uts                        uts;
    }

    enum : mach_msg_type_number_t
    {
        ARM_THREAD_STATE32_COUNT = cast(mach_msg_type_number_t)( arm_thread_state32_t.sizeof / int.sizeof ),
        ARM_THREAD_STATE64_COUNT = cast(mach_msg_type_number_t)( arm_thread_state64_t.sizeof / int.sizeof ),
        ARM_UNIFIED_THREAD_STATE_COUNT   = cast(mach_msg_type_number_t)( arm_unified_thread_state_t.sizeof / int.sizeof ),
    }

    alias ARM_THREAD_STATE               MACHINE_THREAD_STATE;
    alias ARM_UNIFIED_THREAD_STATE_COUNT MACHINE_THREAD_STATE_COUNT;

    mach_port_t   mach_thread_self();
    kern_return_t thread_suspend(thread_act_t);
    kern_return_t thread_resume(thread_act_t);
    kern_return_t thread_get_state(thread_act_t, thread_state_flavor_t, thread_state_t*, mach_msg_type_number_t*);
}
else
{
    static assert(false, "Architecture not supported.");
}
