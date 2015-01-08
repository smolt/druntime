// A temporary place to drop in some hacks and other magic while porting iOS
module ldc.xyzzy;

shared uint skippedTests;

void skipTest()()
{
    pragma(msg, "Note: skipping tests with compile error");
    ++skippedTests;
}


import core.sys.posix.pthread;

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
