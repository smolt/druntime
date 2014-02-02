/**
 * Contains main program entry point and support routines.
 *
 * Copyright: Copyright Digital Mars 2000 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Walter Bright, Sean Kelly
 * Source: $(DRUNTIMESRC src/rt/_dmain2.d)
 */

module rt.dmain2;

private
{
    import rt.memory;
    import rt.sections;
    import rt.util.console;
    import rt.util.string;
    import core.stdc.stddef;
    import core.stdc.stdlib;
    import core.stdc.string;
    import core.stdc.stdio;   // for printf()
}

version (Windows)
{
    private import core.stdc.wchar_;

    extern (Windows)
    {
        alias int function() FARPROC;
        FARPROC    GetProcAddress(void*, in char*);
        void*      LoadLibraryW(in wchar_t*);
        int        FreeLibrary(void*);
        void*      LocalFree(void*);
        wchar_t*   GetCommandLineW();
        wchar_t**  CommandLineToArgvW(in wchar_t*, int*);
        export int WideCharToMultiByte(uint, uint, in wchar_t*, int, char*, int, in char*, int*);
        export int MultiByteToWideChar(uint, uint, in char*, int, wchar_t*, int);
        int        IsDebuggerPresent();
    }
    pragma(lib, "shell32.lib"); // needed for CommandLineToArgvW
}

version (all)
{
    extern (C) Throwable.TraceInfo _d_traceContext(void* ptr = null);

    extern (C) void _d_createTrace(Object *o, void* context)
    {
        auto t = cast(Throwable) o;

        if (t !is null && t.info is null &&
            cast(byte*) t !is t.classinfo.init.ptr)
        {
            t.info = _d_traceContext(context);
        }
    }
}

version (FreeBSD)
{
    import core.stdc.fenv;
}

extern (C) void _STI_monitor_staticctor();
extern (C) void _STD_monitor_staticdtor();
extern (C) void _STI_critical_init();
extern (C) void _STD_critical_term();
extern (C) void gc_init();
extern (C) void gc_term();
extern (C) void rt_moduleCtor();
extern (C) void rt_moduleTlsCtor();
extern (C) void rt_moduleDtor();
extern (C) void rt_moduleTlsDtor();
extern (C) void thread_joinAll();

// NOTE: This is to preserve compatibility with old Windows DLLs.
extern (C) void _moduleCtor()
{
    rt_moduleCtor();
}

extern (C) void _moduleDtor()
{
    rt_moduleDtor();
}

extern (C) void _moduleTlsCtor()
{
    rt_moduleTlsCtor();
}

extern (C) void _moduleTlsDtor()
{
    rt_moduleTlsDtor();
}

version (OSX)
{
    // The bottom of the stack
    extern (C) __gshared void* __osx_stack_end = cast(void*)0xC0000000;
}

/***********************************
 * These are a temporary means of providing a GC hook for DLL use.  They may be
 * replaced with some other similar functionality later.
 */
extern (C)
{
    void* gc_getProxy();
    void  gc_setProxy(void* p);
    void  gc_clrProxy();

    alias void* function()      gcGetFn;
    alias void  function(void*) gcSetFn;
    alias void  function()      gcClrFn;
}

extern (C) void* rt_loadLibrary(in char[] name)
{
    version (Windows)
    {
        if (name.length == 0) return null;
        // Load a DLL at runtime
        enum CP_UTF8 = 65001;
        auto len = MultiByteToWideChar(
            CP_UTF8, 0, name.ptr, cast(int)name.length, null, 0);
        if (len == 0)
            return null;

        auto buf = cast(wchar_t*)malloc((len+1) * wchar_t.sizeof);
        if (buf is null)
            return null;
        scope (exit)
            free(buf);

        len = MultiByteToWideChar(
            CP_UTF8, 0, name.ptr, cast(int)name.length, buf, len);
        if (len == 0)
            return null;

        buf[len] = '\0';

        // BUG: LoadLibraryW() call calls rt_init(), which fails if proxy is not set!
        auto mod = LoadLibraryW(buf);
        if (mod is null)
            return mod;
        gcSetFn gcSet = cast(gcSetFn) GetProcAddress(mod, "gc_setProxy");
        if (gcSet !is null)
        {   // BUG: Set proxy, but too late
            gcSet(gc_getProxy());
        }
        return mod;

    }
    else version (Posix)
    {
        throw new Exception("rt_loadLibrary not yet implemented on Posix.");
    }
}

extern (C) bool rt_unloadLibrary(void* ptr)
{
    version (Windows)
    {
        gcClrFn gcClr  = cast(gcClrFn) GetProcAddress(ptr, "gc_clrProxy");
        if (gcClr !is null)
            gcClr();
        return FreeLibrary(ptr) != 0;
    }
    else version (Posix)
    {
        throw new Exception("rt_unloadLibrary not yet implemented on Posix.");
    }
}

/***********************************
 * These functions must be defined for any D program linked
 * against this library.
 */
extern (C) void onAssertError(string file, size_t line);
extern (C) void onAssertErrorMsg(string file, size_t line, string msg);
extern (C) void onUnittestErrorMsg(string file, size_t line, string msg);
extern (C) void onRangeError(string file, size_t line);
extern (C) void onHiddenFuncError(Object o);
extern (C) void onSwitchError(string file, size_t line);
extern (C) bool runModuleUnitTests();

// this function is called from the utf module
//extern (C) void onUnicodeError(string msg, size_t idx);

/***********************************
 * These are internal callbacks for various language errors.
 */

extern (C)
{
    // Use ModuleInfo to get file name for "m" versions

    void _d_assertm(ModuleInfo* m, uint line)
    {
        onAssertError(m.name, line);
    }

    void _d_assert_msg(string msg, string file, uint line)
    {
        onAssertErrorMsg(file, line, msg);
    }

    void _d_assert(string file, uint line)
    {
        onAssertError(file, line);
    }

    void _d_unittestm(ModuleInfo* m, uint line)
    {
        _d_unittest(m.name, line);
    }

    void _d_unittest_msg(string msg, string file, uint line)
    {
        onUnittestErrorMsg(file, line, msg);
    }

    void _d_unittest(string file, uint line)
    {
        _d_unittest_msg("unittest failure", file, line);
    }

    void _d_array_bounds(ModuleInfo* m, uint line)
    {
        onRangeError(m.name, line);
    }

    void _d_switch_error(ModuleInfo* m, uint line)
    {
        onSwitchError(m.name, line);
    }
}

version (LDC)
{
    // References to this are emitted into the vtbl for hidden functions. As
    // such, we need to match the calling convention for member method calls.
    // The below should be a reasonable guess for virtually all architectures,
    // given how we are lowering the this paramters to just normal (IR-level)
    // parameters.
    extern (C) void _d_hidden_func(Object o)
    {
        onHiddenFuncError(o);
    }
}
else
{
    extern (C) void _d_hidden_func()
    {
        Object o;
        version(D_InlineAsm_X86)
            asm
            {
                mov o, EAX;
            }
        else version(D_InlineAsm_X86_64)
            asm
            {
                mov o, RDI;
            }
        else
            static assert(0, "unknown os");

        onHiddenFuncError(o);
    }
}

__gshared string[] _d_args = null;

extern (C) string[] rt_args()
{
    return _d_args;
}

// This variable is only ever set by a debugger on initialization so it should
// be fine to leave it as __gshared.
extern (C) __gshared bool rt_trapExceptions = true;

void _d_criticalInit()
{
  _STI_monitor_staticctor();
  _STI_critical_init();
}

alias void delegate(Throwable) ExceptionHandler;

extern (C) bool rt_init(ExceptionHandler dg = null)
{
    _d_criticalInit();

    try
    {
        initSections();
        gc_init();
        initStaticDataGC();
        rt_moduleCtor();
        rt_moduleTlsCtor();
        runModuleUnitTests();
        return true;
    }
    catch (Throwable e)
    {
        if (dg)
            dg(e);
        else
            throw e;    // rethrow, don't silently ignore error
    }
    _d_criticalTerm();
    return false;
}

void _d_criticalTerm()
{
  _STD_critical_term();
  _STD_monitor_staticdtor();
}

extern (C) bool rt_term(ExceptionHandler dg = null)
{
    try
    {
        rt_moduleTlsDtor();
        thread_joinAll();
        rt_moduleDtor();
        gc_term();
        finiSections();
        return true;
    }
    catch (Throwable e)
    {
        if (dg)
            dg(e);
    }
    finally
    {
        _d_criticalTerm();
    }
    return false;
}

struct CArgs
{
    int argc;
    char** argv;
}

__gshared CArgs _cArgs;

extern (C) CArgs rt_cArgs()
{
    return _cArgs;
}

/***********************************
 * The D main() function supplied by the user's program
 *
 * It always has `_Dmain` symbol name and uses C calling convention.
 * But DMD frontend returns its type as `extern(D)` because of Issue @@@9028@@@.
 * As we need to deal with actual calling convention we have to mark it
 * as `extern(C)` and use its symbol name.
 */
extern(C) int _Dmain(char[][] args);
alias extern(C) int function(char[][] args) MainFunc;

/***********************************
 * Substitutes for the C main() function.
 * Just calls into d_run_main with the default main function.
 * Applications are free to implement their own
 * main function and call the _d_run_main function
 * themselves with any main function.
 */
version (ARM) {
    // dano - TODO: Not really arm, but as good as anything.
} else
extern (C) int main(int argc, char **argv)
{
    return _d_run_main(argc, argv, &_Dmain);
}

version (Solaris) extern (C) int _main(int argc, char** argv)
{
    // This is apparently needed on Solaris because the
    // C tool chain seems to expect the main function
    // to be called _main. It needs both not just one!
    return main(argc, argv);
}

/***********************************
 * Run the given main function.
 * Its purpose is to wrap the D main()
 * function and catch any unhandled exceptions.
 */
extern (C) int _d_run_main(int argc, char **argv, MainFunc mainFunc)
{
    _cArgs.argc = argc;
    _cArgs.argv = argv;
    int result;

    version (OSX)
    {   /* OSX does not provide a way to get at the top of the
         * stack, except for the magic value 0xC0000000.
         * But as far as the gc is concerned, argv is at the top
         * of the main thread's stack, so save the address of that.
         */
        __osx_stack_end = cast(void*)&argv;
    }

    version (FreeBSD) version (D_InlineAsm_X86)
    {
        /*
         * FreeBSD/i386 sets the FPU precision mode to 53 bit double.
         * Make it 64 bit extended.
         */
        ushort fpucw;
        asm
        {
            fstsw   fpucw;
            or      fpucw, 0b11_00_111111; // 11: use 64 bit extended-precision
                                           // 111111: mask all FP exceptions
            fldcw   fpucw;
        }
    }

    version (Win64)
    {
        auto fp = __iob_func();
        stdin = &fp[0];
        stdout = &fp[1];
        stderr = &fp[2];
    }

    _STI_monitor_staticctor();
    _STI_critical_init();

    char[][] args = (cast(char[]*) alloca(argc * (char[]).sizeof))[0 .. argc];
    version (Windows)
    {
        const wchar_t* wCommandLine = GetCommandLineW();
        immutable size_t wCommandLineLength = wcslen(wCommandLine);
        int wargc;
        wchar_t** wargs = CommandLineToArgvW(wCommandLine, &wargc);
        assert(wargc == argc);

        // This is required because WideCharToMultiByte requires int as input.
        assert(wCommandLineLength <= cast(size_t) int.max, "Wide char command line length must not exceed int.max");

        immutable size_t totalArgsLength = WideCharToMultiByte(65001, 0, wCommandLine, cast(int)wCommandLineLength, null, 0, null, null);
        {
            char* totalArgsBuff = cast(char*) alloca(totalArgsLength);
            int j = 0;
            foreach (i; 0 .. wargc)
            {
                immutable size_t wlen = wcslen(wargs[i]);
                assert(wlen <= cast(size_t) int.max, "wlen cannot exceed int.max");
                immutable int len = WideCharToMultiByte(65001, 0, &wargs[i][0], cast(int) wlen, null, 0, null, null);
                args[i] = totalArgsBuff[j .. j + len];
                if (len == 0)
                    continue;
                j += len;
                assert(j <= totalArgsLength);
                WideCharToMultiByte(65001, 0, &wargs[i][0], cast(int) wlen, &args[i][0], len, null, null);
            }
        }
        LocalFree(wargs);
        wargs = null;
        wargc = 0;
    }
    else version (Posix)
    {
        size_t totalArgsLength = 0;
        foreach(i, ref arg; args)
        {
            arg = argv[i][0 .. strlen(argv[i])];
            totalArgsLength += arg.length;
        }
    }
    else
        static assert(0);

    {
        auto buff = cast(char[]*) alloca(argc * (char[]).sizeof + totalArgsLength);

        char[][] argsCopy = buff[0 .. argc];
        auto argBuff = cast(char*) (buff + argc);
        foreach(i, arg; args)
        {
            argsCopy[i] = (argBuff[0 .. arg.length] = arg[]);
            argBuff += arg.length;
        }
        _d_args = cast(string[]) argsCopy;
    }

    bool trapExceptions = rt_trapExceptions;

    version (Windows)
    {
        if (IsDebuggerPresent())
            trapExceptions = false;
    }

    void tryExec(scope void delegate() dg)
    {
        void printLocLine(Throwable t)
        {
            if (t.file)
            {
               console(t.classinfo.name)("@")(t.file)("(")(t.line)(")");
            }
            else
            {
                console(t.classinfo.name);
            }
            console("\n");
        }

        void printMsgLine(Throwable t)
        {
            if (t.file)
            {
               console(t.classinfo.name)("@")(t.file)("(")(t.line)(")");
            }
            else
            {
                console(t.classinfo.name);
            }
            if (t.msg)
            {
                console(": ")(t.msg);
            }
            console("\n");
        }

        void printInfoBlock(Throwable t)
        {
            if (t.info)
            {
                console("----------------\n");
                foreach (i; t.info)
                    console(i)("\n");
                console("----------------\n");
            }
        }

        void print(Throwable t)
        {
            Throwable firstWithBypass = null;

            for (; t; t = t.next)
            {
                printMsgLine(t);
                printInfoBlock(t);
                auto e = cast(Error) t;
                if (e && e.bypassedException)
                {
                    console("Bypasses ");
                    printLocLine(e.bypassedException);
                    if (firstWithBypass is null)
                        firstWithBypass = t;
                }
            }
            if (firstWithBypass is null)
                return;
            console("=== Bypassed ===\n");
            for (t = firstWithBypass; t; t = t.next)
            {
                auto e = cast(Error) t;
                if (e && e.bypassedException)
                    print(e.bypassedException);
            }
        }

        if (trapExceptions)
        {
            try
            {
                dg();
            }
            catch (Throwable t)
            {
                print(t);
                result = EXIT_FAILURE;
            }
        }
        else
        {
            dg();
        }
    }

    // NOTE: The lifetime of a process is much like the lifetime of an object:
    //       it is initialized, then used, then destroyed.  If initialization
    //       fails, the successive two steps are never reached.  However, if
    //       initialization succeeds, then cleanup will occur even if the use
    //       step fails in some way.  Here, the use phase consists of running
    //       the user's main function.  If main terminates with an exception,
    //       the exception is handled and then cleanup begins.  An exception
    //       thrown during cleanup, however, will abort the cleanup process.

    void runMain()
    {
        result = mainFunc(args);
    }

    void runAll()
    {
        initSections();
        gc_init();
        initStaticDataGC();
        rt_moduleCtor();
        rt_moduleTlsCtor();
        if (runModuleUnitTests())
            tryExec(&runMain);
        else
            result = EXIT_FAILURE;
        rt_moduleTlsDtor();
        thread_joinAll();
        rt_moduleDtor();
        gc_term();
        finiSections();
    }

    tryExec(&runAll);

    _STD_critical_term();
    _STD_monitor_staticdtor();

    return result;
}
