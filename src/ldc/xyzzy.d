// A temporary place to drop in some hacks and other magic while porting iOS
module ldc.xyzzy;

import core.atomic;
import core.stdc.stdio;
import core.sys.posix.pthread;

shared uint skippedTests;
shared uint failedTests;

void skipTest()()
{
    pragma(msg, "Note: some tests for this target are being skipped");
    atomicOp!"+="(skippedTests, 1);
}

void failedTest()
{
    atomicOp!"+="(failedTests, 1);
}

void breakpt()()
{
    // set an ARM breakpoint.  In debugger, set pc to next instruction to continue
    version (ARM)
    {
        import ldc.llvmasm;
        __asm("bkpt", "");
    }
    else
        static assert(0, "breakpt only for ARM");
}

mixin template testhelp()
{
    bool showExpr(string expr)()
    {
        // cheat and use write to make printing of any type easier.
        // Eventually make so not depending on phobos here.
        import std.stdio: writefln;
        writefln("%s = %f", expr, mixin(expr));
        return true;
    }

    bool testTrue(string expr, string msg = null,
                  string file = __FILE__, size_t line = __LINE__)()
    {
        import core.stdc.stdio : printf;
        import ldc.xyzzy;
        
        immutable r = mixin(expr);
        if (r)
        {
            printf("%s(%lu): OK '%s' (Hey, this works now)\n",
                   file.ptr, line, expr.ptr);
        }
        else
        {
            failedTest();
            printf("%s(%lu): FAIL '%s'\n", file.ptr, line, expr.ptr);
            if (msg)
            {
                printf("%s\n", msg.ptr);
            }
        }
        return r;
    }
}

// struct rep of string array for passing into printf style funcs with len,ptr
struct cvstr
{
    const int len;                           // "%.*s" expects int, not size_t
    const char *ptr;

    this(string s)
    {
        len = cast(int)s.length;
        ptr = s.ptr;
    }
}

struct ThreadLocal(T)
{
    @disable this(this);

    alias value this;

    void init()
    {
        if (!key)
        {
            auto rc = pthread_key_create(&key, null);
            assert(rc == 0, "pthread_key_create returned error");
        }
        assert(key);
    }

    @property T value() const
    {
        assert(key, "key should be created already");
        void* p = pthread_getspecific(key);
        return cast(T)p;
    }

    T opAssign(T x)
    {
        assert(key, "key should be created already");
        auto rc = pthread_setspecific(key, cast(void*)x);
        assert(rc == 0, "pthread_setspecific returned error");
        return x;
    }

    void cleanup()
    {
        if (key)
        {
            auto rc = pthread_key_delete(key);
            assert(rc == 0, "pthread_key_delete returned error");
            key = 0;
        }
    }

private:
    pthread_key_t key;
    static assert(T.sizeof <= key.sizeof);
}

unittest
{
    import core.exception;

    ThreadLocal!int x;
    bool pigsfly = false;

    try
    {
        // not init()'ed yet, should die
        int z = x.value;
        pigsfly = true;
    }
    catch (AssertError ex) 
    {
    }

    assert(!pigsfly, "pigs should not fly");

    x.init();
    assert(x == 0);
    assert(x.value == 0);

    x = 42;
    int y = x;
    assert(x == 42);
    assert(y == 42);
    assert(x.value == 42);

    x = 13;
    y = x;
    assert(y == 13);
    assert(x == 13);
    x.cleanup();
}
