//Written in the D programming language

/++
    Module containing core time functionality, such as $(LREF Duration) (which
    represents a duration of time) or $(LREF MonoTime) (which represents a
    timestamp of the system's monotonic clock).

    Various functions take a string (or strings) to represent a unit of time
    (e.g. $(D convert!("days", "hours")(numDays))). The valid strings to use
    with such functions are "years", "months", "weeks", "days", "hours",
    "minutes", "seconds", "msecs" (milliseconds), "usecs" (microseconds),
    "hnsecs" (hecto-nanoseconds - i.e. 100 ns) or some subset thereof. There
    are a few functions that also allow "nsecs", but very little actually
    has precision greater than hnsecs.

    $(BOOKTABLE Cheat Sheet,
    $(TR $(TH Symbol) $(TH Description))
    $(LEADINGROW Types)
    $(TR $(TDNW $(LREF Duration)) $(TD Represents a duration of time of weeks
    or less (kept internally as hnsecs). (e.g. 22 days or 700 seconds).))
    $(TR $(TDNW $(LREF TickDuration)) $(TD Represents a duration of time in
    system clock ticks, using the highest precision that the system provides.))
    $(TR $(TDNW $(LREF MonoTime)) $(TD Represents a monotonic timestamp in
    system clock ticks, using the highest precision that the system provides.))
    $(TR $(TDNW $(LREF FracSec)) $(TD Represents fractional seconds
    (portions of time smaller than a second).))
    $(LEADINGROW Functions)
    $(TR $(TDNW $(LREF convert)) $(TD Generic way of converting between two time
    units.))
    $(TR $(TDNW $(LREF dur)) $(TD Allows constructing a $(LREF Duration) from
    the given time units with the given length.))
    $(TR $(TDNW $(LREF weeks)$(NBSP)$(LREF days)$(NBSP)$(LREF hours)$(BR)
    $(LREF minutes)$(NBSP)$(LREF seconds)$(NBSP)$(LREF msecs)$(BR)
    $(LREF usecs)$(NBSP)$(LREF hnsecs)$(NBSP)$(LREF nsecs))
    $(TD Convenience aliases for $(LREF dur).))
    $(TR $(TDNW $(LREF abs)) $(TD Returns the absolute value of a duration.))
    )

    $(BOOKTABLE Conversions,
    $(TR $(TH )
     $(TH From $(LREF Duration))
     $(TH From $(LREF TickDuration))
     $(TH From $(LREF FracSec))
     $(TH From units)
    )
    $(TR $(TD $(B To $(LREF Duration)))
     $(TD -)
     $(TD $(D tickDuration.)$(SXREF conv, to)$(D !Duration()))
     $(TD -)
     $(TD $(D dur!"msecs"(5)) or $(D 5.msecs()))
    )
    $(TR $(TD $(B To $(LREF TickDuration)))
     $(TD $(D duration.)$(SXREF conv, to)$(D !TickDuration()))
     $(TD -)
     $(TD -)
     $(TD $(D TickDuration.from!"msecs"(msecs)))
    )
    $(TR $(TD $(B To $(LREF FracSec)))
     $(TD $(D duration.fracSec))
     $(TD -)
     $(TD -)
     $(TD $(D FracSec.from!"msecs"(msecs)))
    )
    $(TR $(TD $(B To units))
     $(TD $(D duration.total!"days"))
     $(TD $(D tickDuration.msecs))
     $(TD $(D fracSec.msecs))
     $(TD $(D convert!("days", "msecs")(msecs)))
    ))

    Copyright: Copyright 2010 - 2012
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   Jonathan M Davis and Kato Shoichi
    Source:    $(DRUNTIMESRC core/_time.d)
    Macros:
    NBSP=&nbsp;
    SXREF=<a href="std_$1.html#$2">$(D $2)</a>
 +/
module core.time;

import core.exception;
import core.stdc.time;
import core.stdc.stdio;
import core.internal.traits : _Unqual = Unqual;

version(Windows)
{
import core.sys.windows.windows;
}
else version(Posix)
{
import core.sys.posix.time;
import core.sys.posix.sys.time;
}

//This probably should be moved somewhere else in druntime which
//is OSX-specific.
version(OSX)
{

public import core.sys.osx.mach.kern_return;

extern(C) nothrow @nogc
{

struct mach_timebase_info_data_t
{
    uint numer;
    uint denom;
}

alias mach_timebase_info_data_t* mach_timebase_info_t;

kern_return_t mach_timebase_info(mach_timebase_info_t);

ulong mach_absolute_time();

}

}

//To verify that an lvalue isn't required.
version(unittest) T copy(T)(T t)
{
    return t;
}


/++
    Represents a duration of time of weeks or less (kept internally as hnsecs).
    (e.g. 22 days or 700 seconds).

    It is used when representing a duration of time - such as how long to
    sleep with $(CXREF Thread, sleep).

    In std.datetime, it is also used as the result of various arithmetic
    operations on time points.

    Use the $(LREF dur) function or one of its non-generic aliases to create
    $(D Duration)s.

    It's not possible to create a Duration of months or years, because the
    variable number of days in a month or year makes it impossible to convert
    between months or years and smaller units without a specific date. So,
    nothing uses $(D Duration)s when dealing with months or years. Rather,
    functions specific to months and years are defined. For instance,
    $(XREF datetime, Date) has $(D add!"years") and $(D add!"months") for adding
    years and months rather than creating a Duration of years or months and
    adding that to a $(XREF datetime, Date). But Duration is used when dealing
    with weeks or smaller.

    Examples:
--------------------
assert(dur!"days"(12) == dur!"hnsecs"(10_368_000_000_000L));
assert(dur!"hnsecs"(27) == dur!"hnsecs"(27));
assert(std.datetime.Date(2010, 9, 7) + dur!"days"(5) ==
       std.datetime.Date(2010, 9, 12));

assert(days(-12) == dur!"hnsecs"(-10_368_000_000_000L));
assert(hnsecs(-27) == dur!"hnsecs"(-27));
assert(std.datetime.Date(2010, 9, 7) - std.datetime.Date(2010, 10, 3) ==
       days(-26));
--------------------
 +/
struct Duration
{
@safe pure:

public:

    /++
        A $(D Duration) of $(D 0). It's shorter than doing something like
        $(D dur!"seconds"(0)) and more explicit than $(D Duration.init).
      +/
    static @property nothrow @nogc Duration zero() { return Duration(0); }

    /++
        Largest $(D Duration) possible.
      +/
    static @property nothrow @nogc Duration max() { return Duration(long.max); }

    /++
        Most negative $(D Duration) possible.
      +/
    static @property nothrow @nogc Duration min() { return Duration(long.min); }

    unittest
    {
        assert(zero == dur!"seconds"(0));
        assert(Duration.max == Duration(long.max));
        assert(Duration.min == Duration(long.min));
        assert(Duration.min < Duration.zero);
        assert(Duration.zero < Duration.max);
        assert(Duration.min < Duration.max);
        assert(Duration.min - dur!"hnsecs"(1) == Duration.max);
        assert(Duration.max + dur!"hnsecs"(1) == Duration.min);
    }


    /++
        Compares this $(D Duration) with the given $(D Duration).

        Returns:
            $(TABLE
            $(TR $(TD this &lt; rhs) $(TD &lt; 0))
            $(TR $(TD this == rhs) $(TD 0))
            $(TR $(TD this &gt; rhs) $(TD &gt; 0))
            )
     +/
    int opCmp(Duration rhs) const nothrow @nogc
    {
        if(_hnsecs < rhs._hnsecs)
            return -1;
        if(_hnsecs > rhs._hnsecs)
            return 1;

        return 0;
    }

    unittest
    {
        foreach(T; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            foreach(U; _TypeTuple!(Duration, const Duration, immutable Duration))
            {
                T t = 42;
                U u = t;
                assert(t == u);
                assert(copy(t) == u);
                assert(t == copy(u));
            }
        }

        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            foreach(E; _TypeTuple!(Duration, const Duration, immutable Duration))
            {
                assert((cast(D)Duration(12)).opCmp(cast(E)Duration(12)) == 0);
                assert((cast(D)Duration(-12)).opCmp(cast(E)Duration(-12)) == 0);

                assert((cast(D)Duration(10)).opCmp(cast(E)Duration(12)) < 0);
                assert((cast(D)Duration(-12)).opCmp(cast(E)Duration(12)) < 0);

                assert((cast(D)Duration(12)).opCmp(cast(E)Duration(10)) > 0);
                assert((cast(D)Duration(12)).opCmp(cast(E)Duration(-12)) > 0);

                assert(copy(cast(D)Duration(12)).opCmp(cast(E)Duration(12)) == 0);
                assert(copy(cast(D)Duration(-12)).opCmp(cast(E)Duration(-12)) == 0);

                assert(copy(cast(D)Duration(10)).opCmp(cast(E)Duration(12)) < 0);
                assert(copy(cast(D)Duration(-12)).opCmp(cast(E)Duration(12)) < 0);

                assert(copy(cast(D)Duration(12)).opCmp(cast(E)Duration(10)) > 0);
                assert(copy(cast(D)Duration(12)).opCmp(cast(E)Duration(-12)) > 0);

                assert((cast(D)Duration(12)).opCmp(copy(cast(E)Duration(12))) == 0);
                assert((cast(D)Duration(-12)).opCmp(copy(cast(E)Duration(-12))) == 0);

                assert((cast(D)Duration(10)).opCmp(copy(cast(E)Duration(12))) < 0);
                assert((cast(D)Duration(-12)).opCmp(copy(cast(E)Duration(12))) < 0);

                assert((cast(D)Duration(12)).opCmp(copy(cast(E)Duration(10))) > 0);
                assert((cast(D)Duration(12)).opCmp(copy(cast(E)Duration(-12))) > 0);
            }
        }
    }


    /++
        Adds or subtracts two durations.

        The legal types of arithmetic for $(D Duration) using this operator are

        $(TABLE
        $(TR $(TD Duration) $(TD +) $(TD Duration) $(TD -->) $(TD Duration))
        $(TR $(TD Duration) $(TD -) $(TD Duration) $(TD -->) $(TD Duration))
        $(TR $(TD Duration) $(TD +) $(TD TickDuration) $(TD -->) $(TD Duration))
        $(TR $(TD Duration) $(TD -) $(TD TickDuration) $(TD -->) $(TD Duration))
        )

        Params:
            rhs = The duration to add to or subtract from this $(D Duration).
      +/
    Duration opBinary(string op, D)(D rhs) const nothrow @nogc
        if((op == "+" || op == "-") &&
           (is(_Unqual!D == Duration) ||
            is(_Unqual!D == TickDuration)))
    {
        static if(is(_Unqual!D == Duration))
            return Duration(mixin("_hnsecs " ~ op ~ " rhs._hnsecs"));
        else if(is(_Unqual!D == TickDuration))
            return Duration(mixin("_hnsecs " ~ op ~ " rhs.hnsecs"));
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            foreach(E; _TypeTuple!(Duration, const Duration, immutable Duration))
            {
                assert((cast(D)Duration(5)) + (cast(E)Duration(7)) == Duration(12));
                assert((cast(D)Duration(5)) - (cast(E)Duration(7)) == Duration(-2));
                assert((cast(D)Duration(7)) + (cast(E)Duration(5)) == Duration(12));
                assert((cast(D)Duration(7)) - (cast(E)Duration(5)) == Duration(2));

                assert((cast(D)Duration(5)) + (cast(E)Duration(-7)) == Duration(-2));
                assert((cast(D)Duration(5)) - (cast(E)Duration(-7)) == Duration(12));
                assert((cast(D)Duration(7)) + (cast(E)Duration(-5)) == Duration(2));
                assert((cast(D)Duration(7)) - (cast(E)Duration(-5)) == Duration(12));

                assert((cast(D)Duration(-5)) + (cast(E)Duration(7)) == Duration(2));
                assert((cast(D)Duration(-5)) - (cast(E)Duration(7)) == Duration(-12));
                assert((cast(D)Duration(-7)) + (cast(E)Duration(5)) == Duration(-2));
                assert((cast(D)Duration(-7)) - (cast(E)Duration(5)) == Duration(-12));

                assert((cast(D)Duration(-5)) + (cast(E)Duration(-7)) == Duration(-12));
                assert((cast(D)Duration(-5)) - (cast(E)Duration(-7)) == Duration(2));
                assert((cast(D)Duration(-7)) + (cast(E)Duration(-5)) == Duration(-12));
                assert((cast(D)Duration(-7)) - (cast(E)Duration(-5)) == Duration(-2));
            }

            foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
            {
                assertApprox((cast(D)Duration(5)) + cast(T)TickDuration.from!"usecs"(7), Duration(70), Duration(80));
                assertApprox((cast(D)Duration(5)) - cast(T)TickDuration.from!"usecs"(7), Duration(-70), Duration(-60));
                assertApprox((cast(D)Duration(7)) + cast(T)TickDuration.from!"usecs"(5), Duration(52), Duration(62));
                assertApprox((cast(D)Duration(7)) - cast(T)TickDuration.from!"usecs"(5), Duration(-48), Duration(-38));

                assertApprox((cast(D)Duration(5)) + cast(T)TickDuration.from!"usecs"(-7), Duration(-70), Duration(-60));
                assertApprox((cast(D)Duration(5)) - cast(T)TickDuration.from!"usecs"(-7), Duration(70), Duration(80));
                assertApprox((cast(D)Duration(7)) + cast(T)TickDuration.from!"usecs"(-5), Duration(-48), Duration(-38));
                assertApprox((cast(D)Duration(7)) - cast(T)TickDuration.from!"usecs"(-5), Duration(52), Duration(62));

                assertApprox((cast(D)Duration(-5)) + cast(T)TickDuration.from!"usecs"(7), Duration(60), Duration(70));
                assertApprox((cast(D)Duration(-5)) - cast(T)TickDuration.from!"usecs"(7), Duration(-80), Duration(-70));
                assertApprox((cast(D)Duration(-7)) + cast(T)TickDuration.from!"usecs"(5), Duration(38), Duration(48));
                assertApprox((cast(D)Duration(-7)) - cast(T)TickDuration.from!"usecs"(5), Duration(-62), Duration(-52));

                assertApprox((cast(D)Duration(-5)) + cast(T)TickDuration.from!"usecs"(-7), Duration(-80), Duration(-70));
                assertApprox((cast(D)Duration(-5)) - cast(T)TickDuration.from!"usecs"(-7), Duration(60), Duration(70));
                assertApprox((cast(D)Duration(-7)) + cast(T)TickDuration.from!"usecs"(-5), Duration(-62), Duration(-52));
                assertApprox((cast(D)Duration(-7)) - cast(T)TickDuration.from!"usecs"(-5), Duration(38), Duration(48));
            }
        }
    }


    /++
        Adds or subtracts two durations.

        The legal types of arithmetic for $(D Duration) using this operator are

        $(TABLE
        $(TR $(TD TickDuration) $(TD +) $(TD Duration) $(TD -->) $(TD Duration))
        $(TR $(TD TickDuration) $(TD -) $(TD Duration) $(TD -->) $(TD Duration))
        )

        Params:
            lhs = The $(D TickDuration) to add to this $(D Duration) or to
                  subtract this $(D Duration) from.
      +/
    Duration opBinaryRight(string op, D)(D lhs) const nothrow @nogc
        if((op == "+" || op == "-") &&
            is(_Unqual!D == TickDuration))
    {
        return Duration(mixin("lhs.hnsecs " ~ op ~ " _hnsecs"));
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
            {
                assertApprox((cast(T)TickDuration.from!"usecs"(7)) + cast(D)Duration(5), Duration(70), Duration(80));
                assertApprox((cast(T)TickDuration.from!"usecs"(7)) - cast(D)Duration(5), Duration(60), Duration(70));
                assertApprox((cast(T)TickDuration.from!"usecs"(5)) + cast(D)Duration(7), Duration(52), Duration(62));
                assertApprox((cast(T)TickDuration.from!"usecs"(5)) - cast(D)Duration(7), Duration(38), Duration(48));

                assertApprox((cast(T)TickDuration.from!"usecs"(-7)) + cast(D)Duration(5), Duration(-70), Duration(-60));
                assertApprox((cast(T)TickDuration.from!"usecs"(-7)) - cast(D)Duration(5), Duration(-80), Duration(-70));
                assertApprox((cast(T)TickDuration.from!"usecs"(-5)) + cast(D)Duration(7), Duration(-48), Duration(-38));
                assertApprox((cast(T)TickDuration.from!"usecs"(-5)) - cast(D)Duration(7), Duration(-62), Duration(-52));

                assertApprox((cast(T)TickDuration.from!"usecs"(7)) + (cast(D)Duration(-5)), Duration(60), Duration(70));
                assertApprox((cast(T)TickDuration.from!"usecs"(7)) - (cast(D)Duration(-5)), Duration(70), Duration(80));
                assertApprox((cast(T)TickDuration.from!"usecs"(5)) + (cast(D)Duration(-7)), Duration(38), Duration(48));
                assertApprox((cast(T)TickDuration.from!"usecs"(5)) - (cast(D)Duration(-7)), Duration(52), Duration(62));

                assertApprox((cast(T)TickDuration.from!"usecs"(-7)) + cast(D)Duration(-5), Duration(-80), Duration(-70));
                assertApprox((cast(T)TickDuration.from!"usecs"(-7)) - cast(D)Duration(-5), Duration(-70), Duration(-60));
                assertApprox((cast(T)TickDuration.from!"usecs"(-5)) + cast(D)Duration(-7), Duration(-62), Duration(-52));
                assertApprox((cast(T)TickDuration.from!"usecs"(-5)) - cast(D)Duration(-7), Duration(-48), Duration(-38));
            }
        }
    }


    /++
        Adds or subtracts two durations as well as assigning the result to this
        $(D Duration).

        The legal types of arithmetic for $(D Duration) using this operator are

        $(TABLE
        $(TR $(TD Duration) $(TD +) $(TD Duration) $(TD -->) $(TD Duration))
        $(TR $(TD Duration) $(TD -) $(TD Duration) $(TD -->) $(TD Duration))
        $(TR $(TD Duration) $(TD +) $(TD TickDuration) $(TD -->) $(TD Duration))
        $(TR $(TD Duration) $(TD -) $(TD TickDuration) $(TD -->) $(TD Duration))
        )

        Params:
            rhs = The duration to add to or subtract from this $(D Duration).
      +/
    ref Duration opOpAssign(string op, D)(in D rhs) nothrow @nogc
        if((op == "+" || op == "-") &&
           (is(_Unqual!D == Duration) ||
            is(_Unqual!D == TickDuration)))
    {
        static if(is(_Unqual!D == Duration))
            mixin("_hnsecs " ~ op ~ "= rhs._hnsecs;");
        else if(is(_Unqual!D == TickDuration))
            mixin("_hnsecs " ~ op ~ "= rhs.hnsecs;");

        return this;
    }

    unittest
    {
        static void test1(string op, E)(Duration actual, in E rhs, Duration expected, size_t line = __LINE__)
        {
            if(mixin("actual " ~ op ~ " rhs") != expected)
                throw new AssertError("op failed", __FILE__, line);

            if(actual != expected)
                throw new AssertError("op assign failed", __FILE__, line);
        }

        static void test2(string op, E)
                         (Duration actual, in E rhs, Duration lower, Duration upper, size_t line = __LINE__)
        {
            assertApprox(mixin("actual " ~ op ~ " rhs"), lower, upper, "op failed", line);
            assertApprox(actual, lower, upper, "op assign failed", line);
        }

        foreach(E; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            test1!"+="(Duration(5), (cast(E)Duration(7)), Duration(12));
            test1!"-="(Duration(5), (cast(E)Duration(7)), Duration(-2));
            test1!"+="(Duration(7), (cast(E)Duration(5)), Duration(12));
            test1!"-="(Duration(7), (cast(E)Duration(5)), Duration(2));

            test1!"+="(Duration(5), (cast(E)Duration(-7)), Duration(-2));
            test1!"-="(Duration(5), (cast(E)Duration(-7)), Duration(12));
            test1!"+="(Duration(7), (cast(E)Duration(-5)), Duration(2));
            test1!"-="(Duration(7), (cast(E)Duration(-5)), Duration(12));

            test1!"+="(Duration(-5), (cast(E)Duration(7)), Duration(2));
            test1!"-="(Duration(-5), (cast(E)Duration(7)), Duration(-12));
            test1!"+="(Duration(-7), (cast(E)Duration(5)), Duration(-2));
            test1!"-="(Duration(-7), (cast(E)Duration(5)), Duration(-12));

            test1!"+="(Duration(-5), (cast(E)Duration(-7)), Duration(-12));
            test1!"-="(Duration(-5), (cast(E)Duration(-7)), Duration(2));
            test1!"+="(Duration(-7), (cast(E)Duration(-5)), Duration(-12));
            test1!"-="(Duration(-7), (cast(E)Duration(-5)), Duration(-2));
        }

        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            test2!"+="(Duration(5), cast(T)TickDuration.from!"usecs"(7), Duration(70), Duration(80));
            test2!"-="(Duration(5), cast(T)TickDuration.from!"usecs"(7), Duration(-70), Duration(-60));
            test2!"+="(Duration(7), cast(T)TickDuration.from!"usecs"(5), Duration(52), Duration(62));
            test2!"-="(Duration(7), cast(T)TickDuration.from!"usecs"(5), Duration(-48), Duration(-38));

            test2!"+="(Duration(5), cast(T)TickDuration.from!"usecs"(-7), Duration(-70), Duration(-60));
            test2!"-="(Duration(5), cast(T)TickDuration.from!"usecs"(-7), Duration(70), Duration(80));
            test2!"+="(Duration(7), cast(T)TickDuration.from!"usecs"(-5), Duration(-48), Duration(-38));
            test2!"-="(Duration(7), cast(T)TickDuration.from!"usecs"(-5), Duration(52), Duration(62));

            test2!"+="(Duration(-5), cast(T)TickDuration.from!"usecs"(7), Duration(60), Duration(70));
            test2!"-="(Duration(-5), cast(T)TickDuration.from!"usecs"(7), Duration(-80), Duration(-70));
            test2!"+="(Duration(-7), cast(T)TickDuration.from!"usecs"(5), Duration(38), Duration(48));
            test2!"-="(Duration(-7), cast(T)TickDuration.from!"usecs"(5), Duration(-62), Duration(-52));

            test2!"+="(Duration(-5), cast(T)TickDuration.from!"usecs"(-7), Duration(-80), Duration(-70));
            test2!"-="(Duration(-5), cast(T)TickDuration.from!"usecs"(-7), Duration(60), Duration(70));
            test2!"+="(Duration(-7), cast(T)TickDuration.from!"usecs"(-5), Duration(-62), Duration(-52));
            test2!"-="(Duration(-7), cast(T)TickDuration.from!"usecs"(-5), Duration(38), Duration(48));
        }

        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            foreach(E; _TypeTuple!(Duration, const Duration, immutable Duration,
                                   TickDuration, const TickDuration, immutable TickDuration))
            {
                D lhs = D(120);
                E rhs = E(120);
                static assert(!__traits(compiles, lhs += rhs), D.stringof ~ " " ~ E.stringof);
            }
        }
    }


    /++
        The legal types of arithmetic for $(D Duration) using this operator
        overload are

        $(TABLE
        $(TR $(TD Duration) $(TD *) $(TD long) $(TD -->) $(TD Duration))
        )

        Params:
            value = The value to multiply this $(D Duration) by.
      +/
    Duration opBinary(string op)(long value) const nothrow @nogc
        if(op == "*")
    {
        return Duration(_hnsecs * value);
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            assert((cast(D)Duration(5)) * 7 == Duration(35));
            assert((cast(D)Duration(7)) * 5 == Duration(35));

            assert((cast(D)Duration(5)) * -7 == Duration(-35));
            assert((cast(D)Duration(7)) * -5 == Duration(-35));

            assert((cast(D)Duration(-5)) * 7 == Duration(-35));
            assert((cast(D)Duration(-7)) * 5 == Duration(-35));

            assert((cast(D)Duration(-5)) * -7 == Duration(35));
            assert((cast(D)Duration(-7)) * -5 == Duration(35));

            assert((cast(D)Duration(5)) * 0 == Duration(0));
            assert((cast(D)Duration(-5)) * 0 == Duration(0));
        }
    }


    /++
        The legal types of arithmetic for $(D Duration) using this operator
        overload are

        $(TABLE
        $(TR $(TD Duration) $(TD *) $(TD long) $(TD -->) $(TD Duration))
        )

        Params:
            value = The value to multiply this $(D Duration) by.
      +/
    ref Duration opOpAssign(string op)(long value) nothrow @nogc
        if(op == "*")
    {
        _hnsecs *= value;

       return this;
    }

    unittest
    {
        static void test(D)(D actual, long value, Duration expected, size_t line = __LINE__)
        {
            if((actual *= value) != expected)
                throw new AssertError("op failed", __FILE__, line);

            if(actual != expected)
                throw new AssertError("op assign failed", __FILE__, line);
        }

        test(Duration(5), 7, Duration(35));
        test(Duration(7), 5, Duration(35));

        test(Duration(5), -7, Duration(-35));
        test(Duration(7), -5, Duration(-35));

        test(Duration(-5), 7, Duration(-35));
        test(Duration(-7), 5, Duration(-35));

        test(Duration(-5), -7, Duration(35));
        test(Duration(-7), -5, Duration(35));

        test(Duration(5), 0, Duration(0));
        test(Duration(-5), 0, Duration(0));

        const cdur = Duration(12);
        immutable idur = Duration(12);
        static assert(!__traits(compiles, cdur *= 12));
        static assert(!__traits(compiles, idur *= 12));
    }


    /++
        The legal types of arithmetic for $(D Duration) using this operator
        overload are

        $(TABLE
        $(TR $(TD Duration) $(TD /) $(TD long) $(TD -->) $(TD Duration))
        )

        Params:
            value = The value to divide from this duration.

        Throws:
            $(D TimeException) if an attempt to divide by $(D 0) is made.
      +/
    Duration opBinary(string op)(long value) const
        if(op == "/")
    {
        if(value == 0)
            throw new TimeException("Attempted division by 0.");

        return Duration(_hnsecs / value);
    }

    unittest
    {
        //Unfortunately, putting these inside of the foreach loop results in
        //linker errors regarding multiple definitions and the lambdas.
        _assertThrown!TimeException((){Duration(5) / 0;}());
        _assertThrown!TimeException((){Duration(-5) / 0;}());
        _assertThrown!TimeException((){(cast(const Duration)Duration(5)) / 0;}());
        _assertThrown!TimeException((){(cast(const Duration)Duration(-5)) / 0;}());
        _assertThrown!TimeException((){(cast(immutable Duration)Duration(5)) / 0;}());
        _assertThrown!TimeException((){(cast(immutable Duration)Duration(-5)) / 0;}());

        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            assert((cast(D)Duration(5)) / 7 == Duration(0));
            assert((cast(D)Duration(7)) / 5 == Duration(1));

            assert((cast(D)Duration(5)) / -7 == Duration(0));
            assert((cast(D)Duration(7)) / -5 == Duration(-1));

            assert((cast(D)Duration(-5)) / 7 == Duration(0));
            assert((cast(D)Duration(-7)) / 5 == Duration(-1));

            assert((cast(D)Duration(-5)) / -7 == Duration(0));
            assert((cast(D)Duration(-7)) / -5 == Duration(1));
        }
    }


    /++
        The legal types of arithmetic for $(D Duration) using this operator
        overload are

        $(TABLE
        $(TR $(TD Duration) $(TD /) $(TD long) $(TD -->) $(TD Duration))
        )

        Params:
            value = The value to divide from this $(D Duration).

        Throws:
            $(D TimeException) if an attempt to divide by $(D 0) is made.
      +/
    ref Duration opOpAssign(string op)(long value)
        if(op == "/")
    {
        if(value == 0)
            throw new TimeException("Attempted division by 0.");

        _hnsecs /= value;

        return this;
    }

    unittest
    {
        _assertThrown!TimeException((){Duration(5) /= 0;}());
        _assertThrown!TimeException((){Duration(-5) /= 0;}());

        static void test(Duration actual, long value, Duration expected, size_t line = __LINE__)
        {
            if((actual /= value) != expected)
                throw new AssertError("op failed", __FILE__, line);

            if(actual != expected)
                throw new AssertError("op assign failed", __FILE__, line);
        }

        test(Duration(5), 7, Duration(0));
        test(Duration(7), 5, Duration(1));

        test(Duration(5), -7, Duration(0));
        test(Duration(7), -5, Duration(-1));

        test(Duration(-5), 7, Duration(0));
        test(Duration(-7), 5, Duration(-1));

        test(Duration(-5), -7, Duration(0));
        test(Duration(-7), -5, Duration(1));

        const cdur = Duration(12);
        immutable idur = Duration(12);
        static assert(!__traits(compiles, cdur /= 12));
        static assert(!__traits(compiles, idur /= 12));
    }


    /++
        Multiplies an integral value and a $(D Duration).

        The legal types of arithmetic for $(D Duration) using this operator
        overload are

        $(TABLE
        $(TR $(TD long) $(TD *) $(TD Duration) $(TD -->) $(TD Duration))
        )

        Params:
            value = The number of units to multiply this $(D Duration) by.
      +/
    Duration opBinaryRight(string op)(long value) const nothrow @nogc
        if(op == "*")
    {
        return opBinary!op(value);
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            assert(5 * cast(D)Duration(7) == Duration(35));
            assert(7 * cast(D)Duration(5) == Duration(35));

            assert(5 * cast(D)Duration(-7) == Duration(-35));
            assert(7 * cast(D)Duration(-5) == Duration(-35));

            assert(-5 * cast(D)Duration(7) == Duration(-35));
            assert(-7 * cast(D)Duration(5) == Duration(-35));

            assert(-5 * cast(D)Duration(-7) == Duration(35));
            assert(-7 * cast(D)Duration(-5) == Duration(35));

            assert(0 * cast(D)Duration(-5) == Duration(0));
            assert(0 * cast(D)Duration(5) == Duration(0));
        }
    }


    /++
        Returns the negation of this $(D Duration).
      +/
    Duration opUnary(string op)() const nothrow @nogc
        if(op == "-")
    {
        return Duration(-_hnsecs);
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            assert(-(cast(D)Duration(7)) == Duration(-7));
            assert(-(cast(D)Duration(5)) == Duration(-5));
            assert(-(cast(D)Duration(-7)) == Duration(7));
            assert(-(cast(D)Duration(-5)) == Duration(5));
            assert(-(cast(D)Duration(0)) == Duration(0));
        }
    }


    /++
        Returns a $(LREF TickDuration) with the same number of hnsecs as this
        $(D Duration).
        Note that the conventional way to convert between $(D Duration) and
        $(D TickDuration) is using $(XREF conv, to), e.g.:
        $(D duration.to!TickDuration())
      +/
    TickDuration opCast(T)() const nothrow @nogc
        if(is(_Unqual!T == TickDuration))
    {
        return TickDuration.from!"hnsecs"(_hnsecs);
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            foreach(units; _TypeTuple!("seconds", "msecs", "usecs", "hnsecs"))
            {
                enum unitsPerSec = convert!("seconds", units)(1);

                if(TickDuration.ticksPerSec >= unitsPerSec)
                {
                    foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
                    {
                        auto t = TickDuration.from!units(1);
                        assertApprox(cast(T)cast(D)dur!units(1), t - TickDuration(1), t + TickDuration(1), units);
                        t = TickDuration.from!units(2);
                        assertApprox(cast(T)cast(D)dur!units(2), t - TickDuration(1), t + TickDuration(1), units);
                    }
                }
                else
                {
                    auto t = TickDuration.from!units(1);
                    assert(t.to!(units, long)() == 0, units);
                    t = TickDuration.from!units(1_000_000);
                    assert(t.to!(units, long)() >= 900_000, units);
                    assert(t.to!(units, long)() <= 1_100_000, units);
                }
            }
        }
    }


    //Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    Duration opCast(T)() const nothrow @nogc
        if(is(_Unqual!T == Duration))
    {
        return this;
    }


    /++
        Splits out the Duration into the given units.

        split takes the list of time units to split out as template arguments.
        The time unit strings must be given in decreasing order. How it returns
        the values for those units depends on the overload used.

        The overload which accepts function arguments takes integral types in
        the order that the time unit strings were given, and those integers are
        passed by $(D ref). split assigns the values for the units to each
        corresponding integer. Any integral type may be used, but no attempt is
        made to prevent integer overflow, so don't use small integral types in
        circumstances where the values for those units aren't likely to fit in
        an integral type that small.

        The overload with no arguments returns the values for the units in a
        struct with members whose names are the same as the given time unit
        strings. The members are all $(D long)s. This overload will also work
        with no time strings being given, in which case $(I all) of the time
        units from weeks through hnsecs will be provided (but no nsecs, since it
        would always be $(D 0)).

        For both overloads, the entire value of the Duration is split among the
        units (rather than splitting the Duration across all units and then only
        providing the values for the requested units), so if only one unit is
        given, the result is equivalent to $(LREF total).

        $(D "nsecs") is accepted by split, but $(D "years") and $(D "months")
        are not.

        For negative durations, all of the split values will be negative.
      +/
    template split(units...)
        if(allAreAcceptedUnits!("weeks", "days", "hours", "minutes", "seconds",
                                "msecs", "usecs", "hnsecs", "nsecs")(units) &&
           unitsAreInDescendingOrder(units))
    {
        /++ Ditto +/
        void split(Args...)(out Args args) const nothrow @nogc
            if(units.length != 0 && args.length == units.length && allAreMutableIntegralTypes!Args)
        {
            long hnsecs = _hnsecs;
            foreach(i, unit; units)
            {
                static if(unit == "nsecs")
                    args[i] = cast(typeof(args[i]))convert!("hnsecs", "nsecs")(hnsecs);
                else
                    args[i] = cast(typeof(args[i]))splitUnitsFromHNSecs!unit(hnsecs);
            }
        }

        /++ Ditto +/
        auto split() const nothrow @nogc
        {
            static if(units.length == 0)
                return split!("weeks", "days", "hours", "minutes", "seconds", "msecs", "usecs", "hnsecs")();
            else
            {
                static string genMemberDecls()
                {
                    string retval;
                    foreach(unit; units)
                    {
                        retval ~= "long ";
                        retval ~= unit;
                        retval ~= "; ";
                    }
                    return retval;
                }

                static struct SplitUnits
                {
                    mixin(genMemberDecls());
                }

                static string genSplitCall()
                {
                    auto retval = "split(";
                    foreach(i, unit; units)
                    {
                        retval ~= "su.";
                        retval ~= unit;
                        if(i < units.length - 1)
                            retval ~= ", ";
                        else
                            retval ~= ");";
                    }
                    return retval;
                }

                SplitUnits su = void;
                mixin(genSplitCall());
                return su;
            }
        }

        /+
            Whether all of the given arguments are integral types.
          +/
        private template allAreMutableIntegralTypes(Args...)
        {
            static if(Args.length == 0)
                enum allAreMutableIntegralTypes = true;
            else static if(!is(Args[0] == long) &&
                           !is(Args[0] == int) &&
                           !is(Args[0] == short) &&
                           !is(Args[0] == byte) &&
                           !is(Args[0] == ulong) &&
                           !is(Args[0] == uint) &&
                           !is(Args[0] == ushort) &&
                           !is(Args[0] == ubyte))
            {
                enum allAreMutableIntegralTypes = false;
            }
            else
                enum allAreMutableIntegralTypes = allAreMutableIntegralTypes!(Args[1 .. $]);
        }

        unittest
        {
            foreach(T; _TypeTuple!(long, int, short, byte, ulong, uint, ushort, ubyte))
                static assert(allAreMutableIntegralTypes!T);
            foreach(T; _TypeTuple!(long, int, short, byte, ulong, uint, ushort, ubyte))
                static assert(!allAreMutableIntegralTypes!(const T));
            foreach(T; _TypeTuple!(char, wchar, dchar, float, double, real, string))
                static assert(!allAreMutableIntegralTypes!T);
            static assert(allAreMutableIntegralTypes!(long, int, short, byte));
            static assert(!allAreMutableIntegralTypes!(long, int, short, char, byte));
            static assert(!allAreMutableIntegralTypes!(long, int*, short));
        }
    }

    ///
    unittest
    {
        {
            auto d = dur!"days"(12) + dur!"minutes"(7) + dur!"usecs"(501223);
            long days;
            int seconds;
            short msecs;
            d.split!("days", "seconds", "msecs")(days, seconds, msecs);
            assert(days == 12);
            assert(seconds == 7 * 60);
            assert(msecs == 501);

            auto splitStruct = d.split!("days", "seconds", "msecs")();
            assert(splitStruct.days == 12);
            assert(splitStruct.seconds == 7 * 60);
            assert(splitStruct.msecs == 501);

            auto fullSplitStruct = d.split();
            assert(fullSplitStruct.weeks == 1);
            assert(fullSplitStruct.days == 5);
            assert(fullSplitStruct.hours == 0);
            assert(fullSplitStruct.minutes == 7);
            assert(fullSplitStruct.seconds == 0);
            assert(fullSplitStruct.msecs == 501);
            assert(fullSplitStruct.usecs == 223);
            assert(fullSplitStruct.hnsecs == 0);

            assert(d.split!"minutes"().minutes == d.total!"minutes");
        }

        {
            auto d = dur!"days"(12);
            assert(d.split!"weeks"().weeks == 1);
            assert(d.split!"days"().days == 12);

            assert(d.split().weeks == 1);
            assert(d.split().days == 5);
        }

        {
            auto d = dur!"days"(7) + dur!"hnsecs"(42);
            assert(d.split!("seconds", "nsecs")().nsecs == 4200);
        }

        {
            auto d = dur!"days"(-7) + dur!"hours"(-9);
            auto result = d.split!("days", "hours")();
            assert(result.days == -7);
            assert(result.hours == -9);
        }
    }

    pure nothrow unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            D d = dur!"weeks"(3) + dur!"days"(5) + dur!"hours"(19) + dur!"minutes"(7) +
                  dur!"seconds"(2) + dur!"hnsecs"(1234567);
            byte weeks;
            ubyte days;
            short hours;
            ushort minutes;
            int seconds;
            uint msecs;
            long usecs;
            ulong hnsecs;
            long nsecs;

            d.split!("weeks", "days", "hours", "minutes", "seconds", "msecs", "usecs", "hnsecs", "nsecs")
                    (weeks, days, hours, minutes, seconds, msecs, usecs, hnsecs, nsecs);
            assert(weeks == 3);
            assert(days == 5);
            assert(hours == 19);
            assert(minutes == 7);
            assert(seconds == 2);
            assert(msecs == 123);
            assert(usecs == 456);
            assert(hnsecs == 7);
            assert(nsecs == 0);

            d.split!("weeks", "days", "hours", "seconds", "usecs")(weeks, days, hours, seconds, usecs);
            assert(weeks == 3);
            assert(days == 5);
            assert(hours == 19);
            assert(seconds == 422);
            assert(usecs == 123456);

            d.split!("days", "minutes", "seconds", "nsecs")(days, minutes, seconds, nsecs);
            assert(days == 26);
            assert(minutes == 1147);
            assert(seconds == 2);
            assert(nsecs == 123456700);

            d.split!("minutes", "msecs", "usecs", "hnsecs")(minutes, msecs, usecs, hnsecs);
            assert(minutes == 38587);
            assert(msecs == 2123);
            assert(usecs == 456);
            assert(hnsecs == 7);

            {
                auto result = d.split!("weeks", "days", "hours", "minutes", "seconds",
                                       "msecs", "usecs", "hnsecs", "nsecs");
                assert(result.weeks == 3);
                assert(result.days == 5);
                assert(result.hours == 19);
                assert(result.minutes == 7);
                assert(result.seconds == 2);
                assert(result.msecs == 123);
                assert(result.usecs == 456);
                assert(result.hnsecs == 7);
                assert(result.nsecs == 0);
            }

            {
                auto result = d.split!("weeks", "days", "hours", "seconds", "usecs");
                assert(result.weeks == 3);
                assert(result.days == 5);
                assert(result.hours == 19);
                assert(result.seconds == 422);
                assert(result.usecs == 123456);
            }

            {
                auto result = d.split!("days", "minutes", "seconds", "nsecs")();
                assert(result.days == 26);
                assert(result.minutes == 1147);
                assert(result.seconds == 2);
                assert(result.nsecs == 123456700);
            }

            {
                auto result = d.split!("minutes", "msecs", "usecs", "hnsecs")();
                assert(result.minutes == 38587);
                assert(result.msecs == 2123);
                assert(result.usecs == 456);
                assert(result.hnsecs == 7);
            }

            {
                auto result = d.split();
                assert(result.weeks == 3);
                assert(result.days == 5);
                assert(result.hours == 19);
                assert(result.minutes == 7);
                assert(result.seconds == 2);
                assert(result.msecs == 123);
                assert(result.usecs == 456);
                assert(result.hnsecs == 7);
                static assert(!is(typeof(result.nsecs)));
            }

            static assert(!is(typeof(d.split("seconds", "hnsecs")(seconds))));
            static assert(!is(typeof(d.split("hnsecs", "seconds", "minutes")(hnsecs, seconds, minutes))));
            static assert(!is(typeof(d.split("hnsecs", "seconds", "msecs")(hnsecs, seconds, msecs))));
            static assert(!is(typeof(d.split("seconds", "hnecs", "msecs")(seconds, hnsecs, msecs))));
            static assert(!is(typeof(d.split("seconds", "msecs", "msecs")(seconds, msecs, msecs))));
            static assert(!is(typeof(d.split("hnsecs", "seconds", "minutes")())));
            static assert(!is(typeof(d.split("hnsecs", "seconds", "msecs")())));
            static assert(!is(typeof(d.split("seconds", "hnecs", "msecs")())));
            static assert(!is(typeof(d.split("seconds", "msecs", "msecs")())));
            alias _TypeTuple!("nsecs", "hnsecs", "usecs", "msecs", "seconds",
                              "minutes", "hours", "days", "weeks") timeStrs;
            foreach(i, str; timeStrs[1 .. $])
                static assert(!is(typeof(d.split!(timeStrs[i - 1], str)())));

            D nd = -d;

            {
                auto result = nd.split();
                assert(result.weeks == -3);
                assert(result.days == -5);
                assert(result.hours == -19);
                assert(result.minutes == -7);
                assert(result.seconds == -2);
                assert(result.msecs == -123);
                assert(result.usecs == -456);
                assert(result.hnsecs == -7);
            }

            {
                auto result = nd.split!("weeks", "days", "hours", "minutes", "seconds", "nsecs")();
                assert(result.weeks == -3);
                assert(result.days == -5);
                assert(result.hours == -19);
                assert(result.minutes == -7);
                assert(result.seconds == -2);
                assert(result.nsecs == -123456700);
            }
        }
    }


    /++
        $(RED Deprecated. Please use $(LREF split) instead. Too frequently,
              get or one of the individual unit getters is used when the
              function that gave the desired behavior was $(LREF total). This
              should make it more explicit and help prevent bugs. This function
              will be removed in June 2015.)

        Returns the number of the given units in this $(D Duration)
        (minus the larger units).

        $(D d.get!"minutes"()) is equivalent to $(D d.split().minutes).
      +/
    deprecated("Please use split instead. get was too frequently confused for total.")
    long get(string units)() const nothrow @nogc
        if(units == "weeks" ||
           units == "days" ||
           units == "hours" ||
           units == "minutes" ||
           units == "seconds")
    {
        static if(units == "weeks")
            return getUnitsFromHNSecs!"weeks"(_hnsecs);
        else
        {
            immutable hnsecs = removeUnitsFromHNSecs!(nextLargerTimeUnits!units)(_hnsecs);
            return getUnitsFromHNSecs!units(hnsecs);
        }
    }

    ///
    deprecated unittest
    {
        assert(dur!"weeks"(12).get!"weeks" == 12);
        assert(dur!"weeks"(12).get!"days" == 0);

        assert(dur!"days"(13).get!"weeks" == 1);
        assert(dur!"days"(13).get!"days" == 6);

        assert(dur!"hours"(49).get!"days" == 2);
        assert(dur!"hours"(49).get!"hours" == 1);
    }

    deprecated unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"weeks"(12)).get!"weeks" == 12);
            assert((cast(D)dur!"weeks"(12)).get!"days" == 0);

            assert((cast(D)dur!"days"(13)).get!"weeks" == 1);
            assert((cast(D)dur!"days"(13)).get!"days" == 6);

            assert((cast(D)dur!"hours"(49)).get!"days" == 2);
            assert((cast(D)dur!"hours"(49)).get!"hours" == 1);
        }
    }


    /++
        $(RED Deprecated. Please use $(LREF split) instead. Too frequently,
              $(LREF get) or one of the individual unit getters is used when the
              function that gave the desired behavior was $(LREF total). This
              should make it more explicit and help prevent bugs. This function
              will be removed in June 2015.)

        Returns the number of weeks in this $(D Duration)
        (minus the larger units).
      +/
    deprecated(`Please use split instead. The functions which wrapped get were too frequently confused with total.`)
    @property long weeks() const nothrow @nogc
    {
        return get!"weeks"();
    }

    ///
    deprecated unittest
    {
        assert(dur!"weeks"(12).weeks == 12);
        assert(dur!"days"(13).weeks == 1);
    }

    deprecated unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"weeks"(12)).weeks == 12);
            assert((cast(D)dur!"days"(13)).weeks == 1);
        }
    }


    /++
        $(RED Deprecated. Please use $(LREF split) instead. Too frequently,
              $(LREF get) or one of the individual unit getters is used when the
              function that gave the desired behavior was $(LREF total). This
              should make it more explicit and help prevent bugs. This function
              will be removed in June 2015.)

        Returns the number of days in this $(D Duration)
        (minus the larger units).
      +/
    deprecated(`Please use split instead. days was too frequently confused for total!"days".`)
    @property long days() const nothrow @nogc
    {
        return get!"days"();
    }

    ///
    deprecated unittest
    {
        assert(dur!"weeks"(12).days == 0);
        assert(dur!"days"(13).days == 6);
        assert(dur!"hours"(49).days == 2);
    }

    deprecated unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"weeks"(12)).days == 0);
            assert((cast(D)dur!"days"(13)).days == 6);
            assert((cast(D)dur!"hours"(49)).days == 2);
        }
    }


    /++
        $(RED Deprecated. Please use $(LREF split) instead. Too frequently,
              $(LREF get) or one of the individual unit getters is used when the
              function that gave the desired behavior was $(LREF total). This
              should make it more explicit and help prevent bugs. This function
              will be removed in June 2015.)

        Returns the number of hours in this $(D Duration)
        (minus the larger units).
      +/
    deprecated(`Please use split instead. hours was too frequently confused for total!"hours".`)
    @property long hours() const nothrow @nogc
    {
        return get!"hours"();
    }

    ///
    deprecated unittest
    {
        assert(dur!"days"(8).hours == 0);
        assert(dur!"hours"(49).hours == 1);
        assert(dur!"minutes"(121).hours == 2);
    }

    deprecated unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"days"(8)).hours == 0);
            assert((cast(D)dur!"hours"(49)).hours == 1);
            assert((cast(D)dur!"minutes"(121)).hours == 2);
        }
    }


    /++
        $(RED Deprecated. Please use $(LREF split) instead. Too frequently,
              $(LREF get) or one of the individual unit getters is used when the
              function that gave the desired behavior was $(LREF total). This
              should make it more explicit and help prevent bugs. This function
              will be removed in June 2015.)

        Returns the number of minutes in this $(D Duration)
        (minus the larger units).
      +/
    deprecated(`Please use split instead. minutes was too frequently confused for total!"minutes".`)
    @property long minutes() const nothrow @nogc
    {
        return get!"minutes"();
    }

    ///
    deprecated unittest
    {
        assert(dur!"hours"(47).minutes == 0);
        assert(dur!"minutes"(127).minutes == 7);
        assert(dur!"seconds"(121).minutes == 2);
    }

    deprecated unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"hours"(47)).minutes == 0);
            assert((cast(D)dur!"minutes"(127)).minutes == 7);
            assert((cast(D)dur!"seconds"(121)).minutes == 2);
        }
    }


    /++
        $(RED Deprecated. Please use $(LREF split) instead. Too frequently,
              $(LREF get) or one of the individual unit getters is used when the
              function that gave the desired behavior was $(LREF total). This
              should make it more explicit and help prevent bugs. This function
              will be removed in June 2015.)

        Returns the number of seconds in this $(D Duration)
        (minus the larger units).
      +/
    deprecated(`Please use split instead. seconds was too frequently confused for total!"seconds".`)
    @property long seconds() const nothrow @nogc
    {
        return get!"seconds"();
    }

    ///
    deprecated unittest
    {
        assert(dur!"minutes"(47).seconds == 0);
        assert(dur!"seconds"(127).seconds == 7);
        assert(dur!"msecs"(1217).seconds == 1);
    }

    deprecated unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"minutes"(47)).seconds == 0);
            assert((cast(D)dur!"seconds"(127)).seconds == 7);
            assert((cast(D)dur!"msecs"(1217)).seconds == 1);
        }
    }


    /++
        $(RED Deprecated. Please use $(LREF split) instead. Too frequently,
              $(LREF get) or one of the individual unit getters is used when the
              function that gave the desired behavior was $(LREF total). This
              should make it more explicit and help prevent bugs. This function
              will be removed in June 2015.)

        Returns the fractional seconds past the second in this $(D Duration).
     +/
    deprecated(`Please use split instead.`)
    @property FracSec fracSec() const nothrow
    {
        try
        {
            immutable hnsecs = removeUnitsFromHNSecs!("seconds")(_hnsecs);

            return FracSec.from!"hnsecs"(hnsecs);
        }
        catch(Exception e)
            assert(0, "FracSec.from!\"hnsecs\"() threw.");
    }

    ///
    deprecated unittest
    {
        assert(dur!"msecs"(1000).fracSec == FracSec.from!"msecs"(0));
        assert(dur!"msecs"(1217).fracSec == FracSec.from!"msecs"(217));
        assert(dur!"usecs"(43).fracSec == FracSec.from!"usecs"(43));
        assert(dur!"hnsecs"(50_007).fracSec == FracSec.from!"hnsecs"(50_007));
        assert(dur!"nsecs"(62_127).fracSec == FracSec.from!"nsecs"(62_100));

        assert(dur!"msecs"(-1000).fracSec == FracSec.from!"msecs"(-0));
        assert(dur!"msecs"(-1217).fracSec == FracSec.from!"msecs"(-217));
        assert(dur!"usecs"(-43).fracSec == FracSec.from!"usecs"(-43));
        assert(dur!"hnsecs"(-50_007).fracSec == FracSec.from!"hnsecs"(-50_007));
        assert(dur!"nsecs"(-62_127).fracSec == FracSec.from!"nsecs"(-62_100));
    }

    deprecated unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"msecs"(1000)).fracSec == FracSec.from!"msecs"(0));
            assert((cast(D)dur!"msecs"(1217)).fracSec == FracSec.from!"msecs"(217));
            assert((cast(D)dur!"usecs"(43)).fracSec == FracSec.from!"usecs"(43));
            assert((cast(D)dur!"hnsecs"(50_007)).fracSec == FracSec.from!"hnsecs"(50_007));
            assert((cast(D)dur!"nsecs"(62_127)).fracSec == FracSec.from!"nsecs"(62_100));

            assert((cast(D)dur!"msecs"(-1000)).fracSec == FracSec.from!"msecs"(-0));
            assert((cast(D)dur!"msecs"(-1217)).fracSec == FracSec.from!"msecs"(-217));
            assert((cast(D)dur!"usecs"(-43)).fracSec == FracSec.from!"usecs"(-43));
            assert((cast(D)dur!"hnsecs"(-50_007)).fracSec == FracSec.from!"hnsecs"(-50_007));
            assert((cast(D)dur!"nsecs"(-62_127)).fracSec == FracSec.from!"nsecs"(-62_100));
        }
    }


    /++
        Returns the total number of the given units in this $(D Duration).
        So, unlike $(D split), it does not strip out the larger units.
      +/
    @property long total(string units)() const nothrow @nogc
        if(units == "weeks" ||
           units == "days" ||
           units == "hours" ||
           units == "minutes" ||
           units == "seconds" ||
           units == "msecs" ||
           units == "usecs" ||
           units == "hnsecs" ||
           units == "nsecs")
    {
        static if(units == "nsecs")
            return convert!("hnsecs", "nsecs")(_hnsecs);
        else
            return getUnitsFromHNSecs!units(_hnsecs);
    }

    ///
    unittest
    {
        assert(dur!"weeks"(12).total!"weeks" == 12);
        assert(dur!"weeks"(12).total!"days" == 84);

        assert(dur!"days"(13).total!"weeks" == 1);
        assert(dur!"days"(13).total!"days" == 13);

        assert(dur!"hours"(49).total!"days" == 2);
        assert(dur!"hours"(49).total!"hours" == 49);

        assert(dur!"nsecs"(2007).total!"hnsecs" == 20);
        assert(dur!"nsecs"(2007).total!"nsecs" == 2000);
    }

    unittest
    {
        foreach(D; _TypeTuple!(const Duration, immutable Duration))
        {
            assert((cast(D)dur!"weeks"(12)).total!"weeks" == 12);
            assert((cast(D)dur!"weeks"(12)).total!"days" == 84);

            assert((cast(D)dur!"days"(13)).total!"weeks" == 1);
            assert((cast(D)dur!"days"(13)).total!"days" == 13);

            assert((cast(D)dur!"hours"(49)).total!"days" == 2);
            assert((cast(D)dur!"hours"(49)).total!"hours" == 49);

            assert((cast(D)dur!"nsecs"(2007)).total!"hnsecs" == 20);
            assert((cast(D)dur!"nsecs"(2007)).total!"nsecs" == 2000);
        }
    }


    /+
        Converts this $(D Duration) to a $(D string).
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString()
    {
        return _toStringImpl();
    }


    /++
        Converts this $(D Duration) to a $(D string).
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString() const nothrow
    {
        return _toStringImpl();
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            assert((cast(D)Duration(0)).toString() == "0 hnsecs");
            assert((cast(D)Duration(1)).toString() == "1 hnsec");
            assert((cast(D)Duration(7)).toString() == "7 hnsecs");
            assert((cast(D)Duration(10)).toString() == "1 μs");
            assert((cast(D)Duration(20)).toString() == "2 μs");
            assert((cast(D)Duration(10_000)).toString() == "1 ms");
            assert((cast(D)Duration(20_000)).toString() == "2 ms");
            assert((cast(D)Duration(10_000_000)).toString() == "1 sec");
            assert((cast(D)Duration(20_000_000)).toString() == "2 secs");
            assert((cast(D)Duration(600_000_000)).toString() == "1 minute");
            assert((cast(D)Duration(1_200_000_000)).toString() == "2 minutes");
            assert((cast(D)Duration(36_000_000_000)).toString() == "1 hour");
            assert((cast(D)Duration(72_000_000_000)).toString() == "2 hours");
            assert((cast(D)Duration(864_000_000_000)).toString() == "1 day");
            assert((cast(D)Duration(1_728_000_000_000)).toString() == "2 days");
            assert((cast(D)Duration(6_048_000_000_000)).toString() == "1 week");
            assert((cast(D)Duration(12_096_000_000_000)).toString() == "2 weeks");

            assert((cast(D)Duration(12)).toString() == "1 μs and 2 hnsecs");
            assert((cast(D)Duration(120_795)).toString() == "12 ms, 79 μs, and 5 hnsecs");
            assert((cast(D)Duration(12_096_020_900_003)).toString() == "2 weeks, 2 secs, 90 ms, and 3 hnsecs");

            assert((cast(D)Duration(-1)).toString() == "-1 hnsecs");
            assert((cast(D)Duration(-7)).toString() == "-7 hnsecs");
            assert((cast(D)Duration(-10)).toString() == "-1 μs");
            assert((cast(D)Duration(-20)).toString() == "-2 μs");
            assert((cast(D)Duration(-10_000)).toString() == "-1 ms");
            assert((cast(D)Duration(-20_000)).toString() == "-2 ms");
            assert((cast(D)Duration(-10_000_000)).toString() == "-1 secs");
            assert((cast(D)Duration(-20_000_000)).toString() == "-2 secs");
            assert((cast(D)Duration(-600_000_000)).toString() == "-1 minutes");
            assert((cast(D)Duration(-1_200_000_000)).toString() == "-2 minutes");
            assert((cast(D)Duration(-36_000_000_000)).toString() == "-1 hours");
            assert((cast(D)Duration(-72_000_000_000)).toString() == "-2 hours");
            assert((cast(D)Duration(-864_000_000_000)).toString() == "-1 days");
            assert((cast(D)Duration(-1_728_000_000_000)).toString() == "-2 days");
            assert((cast(D)Duration(-6_048_000_000_000)).toString() == "-1 weeks");
            assert((cast(D)Duration(-12_096_000_000_000)).toString() == "-2 weeks");

            assert((cast(D)Duration(-12)).toString() == "-1 μs and -2 hnsecs");
            assert((cast(D)Duration(-120_795)).toString() == "-12 ms, -79 μs, and -5 hnsecs");
            assert((cast(D)Duration(-12_096_020_900_003)).toString() == "-2 weeks, -2 secs, -90 ms, and -3 hnsecs");
        }
    }


    /++
        Returns whether this $(D Duration) is negative.
      +/
    @property bool isNegative() const nothrow @nogc
    {
        return _hnsecs < 0;
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            assert(!(cast(D)Duration(100)).isNegative);
            assert(!(cast(D)Duration(1)).isNegative);
            assert(!(cast(D)Duration(0)).isNegative);
            assert((cast(D)Duration(-1)).isNegative);
            assert((cast(D)Duration(-100)).isNegative);
        }
    }


private:

    /+
        Since we have two versions of toString, we have _toStringImpl
        so that they can share implementations.
      +/
    string _toStringImpl() const nothrow
    {
        static void appListSep(ref string res, uint pos, bool last) nothrow
        {
            if (pos == 0)
                return;
            if (!last)
                res ~= ", ";
            else
                res ~= pos == 1 ? " and " : ", and ";
        }

        static void appUnitVal(string units)(ref string res, long val) nothrow
        {
            immutable plural = val != 1;
            string unit;
            static if (units == "seconds")
                unit = plural ? "secs" : "sec";
            else static if (units == "msecs")
                unit = "ms";
            else static if (units == "usecs")
                unit = "μs";
            else
                unit = plural ? units : units[0 .. $-1];
            res ~= numToString(val) ~ " " ~ unit;
        }

        if (_hnsecs == 0) return "0 hnsecs";

        template TT(T...) { alias T TT; }
        alias units = TT!("weeks", "days", "hours", "minutes", "seconds", "msecs", "usecs");

        long hnsecs = _hnsecs; string res; uint pos;
        foreach (unit; units)
        {
            if (auto val = splitUnitsFromHNSecs!unit(hnsecs))
            {
                appListSep(res, pos++, hnsecs == 0);
                appUnitVal!unit(res, val);
            }
            if (hnsecs == 0) break;
        }
        if (hnsecs != 0)
        {
            appListSep(res, pos++, true);
            appUnitVal!"hnsecs"(res, hnsecs);
        }
        return res;
    }


    /+
        Params:
            hnsecs = The total number of hecto-nanoseconds in this $(D Duration).
      +/
    this(long hnsecs) nothrow @nogc
    {
        _hnsecs = hnsecs;
    }


    long _hnsecs;
}

///
unittest
{
    import core.time;

    // using the dur template
    auto numDays = dur!"days"(12);

    // using the days function
    numDays = days(12);

    // alternatively using UFCS syntax
    numDays = 12.days;

    auto myTime = 100.msecs + 20_000.usecs + 30_000.hnsecs;
    assert(myTime == 123.msecs);
}

/++
    These allow you to construct a $(D Duration) from the given time units
    with the given length.

    You can either use the generic function $(D dur) and give it the units as
    a $(D string) or use the named aliases.

    The possible values for units are $(D "weeks"), $(D "days"), $(D "hours"),
    $(D "minutes"), $(D "seconds"), $(D "msecs") (milliseconds), $(D "usecs"),
    (microseconds), $(D "hnsecs") (hecto-nanoseconds, i.e. 100 ns), and
    $(D "nsecs").

    Examples:
--------------------
// Generic
assert(dur!"weeks"(142).total!"weeks" == 142);
assert(dur!"days"(142).total!"days" == 142);
assert(dur!"hours"(142).total!"hours" == 142);
assert(dur!"minutes"(142).total!"minutes" == 142);
assert(dur!"seconds"(142).total!"seconds" == 142);
assert(dur!"msecs"(142).total!"msecs" == 142);
assert(dur!"usecs"(142).total!"usecs" == 142);
assert(dur!"hnsecs"(142).total!"hnsecs" == 142);
assert(dur!"nsecs"(142).total!"nsecs" == 100);

// Non-generic
assert(weeks(142).total!"weeks" == 142);
assert(days(142).total!"days" == 142);
assert(hours(142).total!"hours" == 142);
assert(minutes(142).total!"minutes" == 142);
assert(seconds(142).total!"seconds" == 142);
assert(msecs(142).total!"msecs" == 142);
assert(usecs(142).total!"usecs" == 142);
assert(hnsecs(142).total!"hnsecs" == 142);
assert(nsecs(142).total!"nsecs" == 100);
--------------------

    Params:
        units  = The time units of the $(D Duration) (e.g. $(D "days")).
        length = The number of units in the $(D Duration).
  +/
Duration dur(string units)(long length) @safe pure nothrow @nogc
    if(units == "weeks" ||
       units == "days" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds" ||
       units == "msecs" ||
       units == "usecs" ||
       units == "hnsecs" ||
       units == "nsecs")
{
    return Duration(convert!(units, "hnsecs")(length));
}

alias weeks   = dur!"weeks";   /// Ditto
alias days    = dur!"days";    /// Ditto
alias hours   = dur!"hours";   /// Ditto
alias minutes = dur!"minutes"; /// Ditto
alias seconds = dur!"seconds"; /// Ditto
alias msecs   = dur!"msecs";   /// Ditto
alias usecs   = dur!"usecs";   /// Ditto
alias hnsecs  = dur!"hnsecs";  /// Ditto
alias nsecs   = dur!"nsecs";   /// Ditto

//Verify Examples.
unittest
{
    // Generic
    assert(dur!"weeks"(142).total!"weeks" == 142);
    assert(dur!"days"(142).total!"days" == 142);
    assert(dur!"hours"(142).total!"hours" == 142);
    assert(dur!"minutes"(142).total!"minutes" == 142);
    assert(dur!"seconds"(142).total!"seconds" == 142);
    assert(dur!"msecs"(142).total!"msecs" == 142);
    assert(dur!"usecs"(142).total!"usecs" == 142);
    assert(dur!"hnsecs"(142).total!"hnsecs" == 142);
    assert(dur!"nsecs"(142).total!"nsecs" == 100);

    // Non-generic
    assert(weeks(142).total!"weeks" == 142);
    assert(days(142).total!"days" == 142);
    assert(hours(142).total!"hours" == 142);
    assert(minutes(142).total!"minutes" == 142);
    assert(seconds(142).total!"seconds" == 142);
    assert(msecs(142).total!"msecs" == 142);
    assert(usecs(142).total!"usecs" == 142);
    assert(hnsecs(142).total!"hnsecs" == 142);
    assert(nsecs(142).total!"nsecs" == 100);
}

unittest
{
    foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
    {
        assert(dur!"weeks"(7).total!"weeks" == 7);
        assert(dur!"days"(7).total!"days" == 7);
        assert(dur!"hours"(7).total!"hours" == 7);
        assert(dur!"minutes"(7).total!"minutes" == 7);
        assert(dur!"seconds"(7).total!"seconds" == 7);
        assert(dur!"msecs"(7).total!"msecs" == 7);
        assert(dur!"usecs"(7).total!"usecs" == 7);
        assert(dur!"hnsecs"(7).total!"hnsecs" == 7);
        assert(dur!"nsecs"(7).total!"nsecs" == 0);

        assert(dur!"weeks"(1007) == weeks(1007));
        assert(dur!"days"(1007) == days(1007));
        assert(dur!"hours"(1007) == hours(1007));
        assert(dur!"minutes"(1007) == minutes(1007));
        assert(dur!"seconds"(1007) == seconds(1007));
        assert(dur!"msecs"(1007) == msecs(1007));
        assert(dur!"usecs"(1007) == usecs(1007));
        assert(dur!"hnsecs"(1007) == hnsecs(1007));
        assert(dur!"nsecs"(10) == nsecs(10));
    }
}


/++
    Represents a timestamp of the system's monotonic clock.

    A monotonic clock is one which always goes forward and never moves
    backwards, unlike the system's wall clock time (as represented by
    $(XREF datetime, SysTime)). The system's wall clock time can be adjusted
    by the user or by the system itself via services such as NTP, so it is
    unreliable to use the wall clock time for timing. Timers which use the wall
    clock time could easily end up never going off due changes made to the wall
    clock time or otherwise waiting for a different period of time than that
    specified by the programmer. However, because the monotonic clock always
    increases at a fixed rate and is not affected by adjustments to the wall
    clock time, it is ideal for use with timers or anything which requires high
    precision timing.

    So, MonoTime should be used for anything involving timers and timing,
    whereas $(XREF datetime, SysTime) should be used when the wall clock time
    is required.

    The monotonic clock has no relation to wall clock time. Rather, it holds
    its time as the number of ticks of the clock which have occurred since the
    clock started (typically when the system booted up). So, to determine how
    much time has passed between two points in time, one monotonic time is
    subtracted from the other to determine the number of ticks which occurred
    between the two points of time, and those ticks are divided by the number of
    ticks that occur every second (as represented by MonoTime.ticksPerSecond)
    to get a meaningful duration of time. Normally, MonoTime does these
    calculations for the programmer, but the $(D ticks) and $(D ticksPerSecond)
    properties are provided for those who require direct access to the system
    ticks. However, the normal way that MonoTime would be used is

--------------------
        MonoTime before = MonoTime.currTime;
        // do stuff...
        MonoTime after = MonoTime.currTime;
        Duration timeElapsed = after - before;
--------------------
  +/
struct MonoTime
{
@safe:

    /++
        The current time of the system's monotonic clock. This has no relation
        to the wall clock time, as the wall clock time can be adjusted (e.g.
        by NTP), whereas the monotonic clock always moves forward. The source
        of the monotonic time is system-specific.

        On Windows, $(D QueryPerformanceCounter) is used. On Mac OS X,
        $(D mach_absolute_time) is used, while on other POSIX systems,
        $(D clock_gettime) is used.

        $(RED Warning): On some systems, the monotonic clock may stop counting
                        when the computer goes to sleep or hibernates. So, the
                        monotonic clock may indicate less time than has actually
                        passed if that occurs. This is known to happen on
                        Mac OS X. It has not been tested whether it occurs on
                        either Windows or on Linux.
      +/
    static @property MonoTime currTime() @trusted nothrow @nogc
    {
        if(_ticksPerSecond == 0)
            assert(0, "MonoTime failed to get the frequency of the system's monotonic clock.");

        version(Windows)
        {
            long ticks;
            if(QueryPerformanceCounter(&ticks) == 0)
            {
                // This probably cannot happen on Windows 95 or later
                assert(0, "Call to QueryPerformanceCounter failed.");
            }
            return MonoTime(ticks);
        }
        else version(OSX)
            return MonoTime(mach_absolute_time());
        else version(Posix)
        {
            timespec ts;
            if(clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
                assert(0, "Call to clock_gettime failed.");

            return MonoTime(convClockFreq(ts.tv_sec * 1_000_000_000L + ts.tv_nsec,
                                          1_000_000_000L,
                                          _ticksPerSecond));
        }
    }


    static @property pure nothrow @nogc
    {
    /++
        A $(D MonoTime) of $(D 0) ticks. It's provided to be consistent with
        $(D Duration.zero), and it's more explicit than $(D MonoTime.init).
      +/
    MonoTime zero() { return MonoTime(0); }

    /++
        Largest $(D MonoTime) possible.
      +/
    MonoTime max() { return MonoTime(long.max); }

    /++
        Most negative $(D MonoTime) possible.
      +/
    MonoTime min() { return MonoTime(long.min); }
    }

    unittest
    {
        assert(zero == MonoTime(0));
        assert(MonoTime.max == MonoTime(long.max));
        assert(MonoTime.min == MonoTime(long.min));
        assert(MonoTime.min < MonoTime.zero);
        assert(MonoTime.zero < MonoTime.max);
        assert(MonoTime.min < MonoTime.max);
    }


    /++
        Compares this MonoTime with the given MonoTime.

        Returns:
            $(BOOKTABLE,
                $(TR $(TD this &lt; rhs) $(TD &lt; 0))
                $(TR $(TD this == rhs) $(TD 0))
                $(TR $(TD this &gt; rhs) $(TD &gt; 0))
            )
     +/
    int opCmp(MonoTime rhs) const pure nothrow @nogc
    {
        if(_ticks < rhs._ticks)
            return -1;
        return _ticks > rhs._ticks ? 1 : 0;
    }

    unittest
    {
        foreach(T; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
        {
            foreach(U; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
            {
                T t = MonoTime.currTime;
                U u = t;
                assert(t == u);
                assert(copy(t) == u);
                assert(t == copy(u));
            }
        }

        foreach(T; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
        {
            foreach(U; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
            {
                T before = MonoTime.currTime;
                auto after = U(before._ticks + 42);
                assert(before < after);
                assert(before <= before);
                assert(after > before);
                assert(after >= after);

                assert(copy(before) < after);
                assert(copy(before) <= before);
                assert(copy(after) > before);
                assert(copy(after) >= after);

                assert(before < copy(after));
                assert(before <= copy(before));
                assert(after > copy(before));
                assert(after >= copy(after));
            }
        }

        immutable currTime = MonoTime.currTime;
        assert(MonoTime(long.max) > MonoTime(0));
        assert(MonoTime(0) > MonoTime(long.min));
        assert(MonoTime(long.max) > currTime);
        assert(currTime > MonoTime(0));
        assert(MonoTime(0) < currTime);
        assert(MonoTime(0) < MonoTime(long.max));
        assert(MonoTime(long.min) < MonoTime(0));
    }


    /++
        Subtracting two MonoTimes results in a $(LREF Duration) representing the
        amount of time which elapsed between them.

        The primary way that programs should time how long something takes is to
        do
--------------------
MonoTime before = MonoTime.currTime;
// do stuff
MonoTime after = MonoTime.currTime;

// How long it took.
Duration timeElapsed = after - before;
--------------------
        or to use a wrapper (such as a stop watch type) which does that.

        $(RED Warning):
            Because $(LREF Duration) is in hnsecs, whereas MonoTime is in system
            ticks, it's usually the case that this assertion will fail
--------------------
auto before = MonoTime.currTime;
// do stuff
auto after = MonoTime.currTime;
auto timeElapsed = after - before;
assert(before + timeElapsed == after).
--------------------

            This is generally fine, and by its very nature, converting from
            system ticks to any type of seconds (hnsecs, nsecs, etc.) will
            introduce rounding errors, but if code needs to avoid any of the
            small rounding errors introduced by conversion, then it needs to use
            MonoTime's $(D ticks) property and keep all calculations in ticks
            rather than using $(LREF Duration).
      +/
    Duration opBinary(string op)(MonoTime rhs) const pure nothrow @nogc
        if(op == "-")
    {
        immutable diff = _ticks - rhs._ticks;
        return Duration(convClockFreq(diff , ticksPerSecond, hnsecsPer!"seconds"));
    }

    unittest
    {
        foreach(T; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
        {
            foreach(U; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
            {
                T t = MonoTime.currTime;
                U u = t;
                assert(u - t == Duration.zero);
                assert(copy(t) - u == Duration.zero);
                assert(t - copy(u) == Duration.zero);
            }
        }

        foreach(T; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
        {
            foreach(U; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
            {
                static void test()(T before, U after, Duration min, size_t line = __LINE__) @trusted
                {
                    immutable diff = after - before;
                    scope(failure)
                    {
                        printf("%s %s %s\n",
                               numToStringz(before._ticks),
                               numToStringz(after._ticks),
                               (diff.toString() ~ "\0").ptr);
                    }
                    if(diff >= min) {} else throw new AssertError("unittest failure 1", __FILE__, line);
                    auto calcAfter = before + diff;
                    assertApprox(calcAfter, calcAfter - Duration(1), calcAfter + Duration(1));
                    if(before - after == -diff) {} else throw new AssertError("unittest failure 2", __FILE__, line);
                }

                T before = MonoTime.currTime;
                test(before, MonoTime(before._ticks + 4202), Duration.zero);
                test(before, MonoTime.currTime, Duration.zero);

                auto durLargerUnits = dur!"minutes"(7) + dur!"seconds"(22);
                test(before, before + durLargerUnits + dur!"msecs"(33) + dur!"hnsecs"(571), durLargerUnits);
            }
        }
    }


    /++
        Adding or subtracting a $(LREF Duration) to/from a MonoTime results in
        a MonoTime which is adjusted by that amount.
      +/
    MonoTime opBinary(string op)(Duration rhs) const pure nothrow @nogc
        if(op == "+" || op == "-")
    {
        immutable rhsConverted = convClockFreq(rhs._hnsecs, hnsecsPer!"seconds", ticksPerSecond);
        mixin("return MonoTime(_ticks " ~ op ~ " rhsConverted);");
    }

    unittest
    {
        foreach(T; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
        {
            foreach(U; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
            {
                foreach(V; _TypeTuple!(Duration, const Duration, immutable Duration))
                {
                    T t = MonoTime.currTime;
                    U u1 = t + V(0);
                    U u2 = t - V(0);
                    assert(t == u1);
                    assert(t == u2);
                }
            }
        }

        foreach(T; _TypeTuple!(MonoTime, const MonoTime, immutable MonoTime))
        {
            foreach(U; _TypeTuple!(Duration, const Duration, immutable Duration))
            {
                T t = MonoTime.currTime;

                // We reassign ticks in order to get the same rounding errors
                // that we should be getting with Duration (e.g. MonoTime may be
                // at a higher precision than hnsecs, meaning that 7333 would be
                // truncated when converting to hnsecs).
                long ticks = 7333;
                auto hnsecs = convClockFreq(ticks, MonoTime.ticksPerSecond, hnsecsPer!"seconds");
                ticks = convClockFreq(hnsecs, hnsecsPer!"seconds", MonoTime.ticksPerSecond);

                assert(t - Duration(hnsecs) == MonoTime(t._ticks - ticks));
                assert(t + Duration(hnsecs) == MonoTime(t._ticks + ticks));
            }
        }
    }


    /++ Ditto +/
    ref MonoTime opOpAssign(string op)(Duration rhs) pure nothrow @nogc
        if(op == "+" || op == "-")
    {
        immutable rhsConverted = convClockFreq(rhs._hnsecs, hnsecsPer!"seconds", ticksPerSecond);
        mixin("_ticks " ~ op ~ "= rhsConverted;");
        return this;
    }

    unittest
    {
        foreach(T; _TypeTuple!(const MonoTime, immutable MonoTime))
        {
            T t = MonoTime.currTime;
            static assert(!is(typeof(t += Duration.zero)));
            static assert(!is(typeof(t -= Duration.zero)));
        }

        foreach(T; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            auto mt = MonoTime.currTime;
            auto initial = mt;
            mt += T(0);
            assert(mt == initial);
            mt -= T(0);
            assert(mt == initial);

            // We reassign ticks in order to get the same rounding errors
            // that we should be getting with Duration (e.g. MonoTime may be
            // at a higher precision than hnsecs, meaning that 7333 would be
            // truncated when converting to hnsecs).
            long ticks = 7333;
            auto hnsecs = convClockFreq(ticks, MonoTime.ticksPerSecond, hnsecsPer!"seconds");
            ticks = convClockFreq(hnsecs, hnsecsPer!"seconds", MonoTime.ticksPerSecond);
            auto before = MonoTime(initial._ticks - ticks);

            assert((mt -= Duration(hnsecs)) == before);
            assert(mt  == before);
            assert((mt += Duration(hnsecs)) == initial);
            assert(mt  == initial);
        }
    }


    /++
        The number of ticks in the monotonic time.

        Most programs should not use this directly, but it's exposed for those
        few programs that need it.

        The main reasons that a program might need to use ticks directly is if
        the system clock has higher precision than hnsecs, and the program needs
        that higher precision, or if the program needs to avoid the rounding
        errors caused by converting to hnsecs.
      +/
    @property long ticks() const pure nothrow @nogc
    {
        return _ticks;
    }

    unittest
    {
        auto mt = MonoTime.currTime;
        assert(mt.ticks == mt._ticks);
    }


    /++
        The number of ticks that MonoTime has per second - i.e. the resolution
        or frequency of the system's monotonic clock.

        e.g. if the system clock had a resolution of microseconds, then
        ticksPerSecond would be $(D 1_000_000).
      +/
    static @property long ticksPerSecond() pure nothrow @nogc
    {
        return _ticksPerSecond;
    }

    unittest
    {
        assert(MonoTime.ticksPerSecond == MonoTime._ticksPerSecond);
    }


    ///
    string toString() const pure nothrow
    {
        return "MonoTime(" ~ numToString(_ticks) ~ " ticks, " ~ numToString(_ticksPerSecond) ~ " ticks per second)";
    }

    unittest
    {
        static size_t findSpace(string str, size_t line = __LINE__)
        {
            for(size_t i = 0; i != str.length; ++i)
            {
                if(str[i] == ' ')
                    return i;
            }
            throw new AssertError("unittest failure", __FILE__, line);
        }

        immutable mt = MonoTime.currTime;
        auto str = mt.toString();
        assert(str[0 .. "MonoTime(".length] == "MonoTime(");
        str = str["MonoTime(".length .. $];
        immutable space1 = findSpace(str);
        immutable ticksStr = str[0 .. space1];
        assert(ticksStr == numToString(mt._ticks));
        str = str[space1 + 1 .. $];
        assert(str[0 .. "ticks, ".length] == "ticks, ");
        str = str["ticks, ".length .. $];
        immutable space2 = findSpace(str);
        immutable ticksPerSecondStr = str[0 .. space2];
        assert(ticksPerSecondStr == numToString(MonoTime.ticksPerSecond));
        str = str[space2 + 1 .. $];
        assert(str == "ticks per second)");
    }

private:

    static immutable long _ticksPerSecond;

    @trusted shared static this()
    {
        version(Windows)
        {
            long ticksPerSecond;
            if(QueryPerformanceFrequency(&ticksPerSecond) != 0)
                _ticksPerSecond = ticksPerSecond;
        }
        else version(OSX)
        {
            mach_timebase_info_data_t info;
            if(mach_timebase_info(&info) == 0)
                _ticksPerSecond = 1_000_000_000L * info.numer / info.denom;
        }
        else version(Posix)
        {
            timespec ts;
            if(clock_getres(CLOCK_MONOTONIC, &ts) == 0)
            {
                // For some reason, on some systems, clock_getres returns
                // a resolution which is clearly wrong (it's a millisecond
                // or worse, but the time is updated much more frequently
                // than that). In such cases, we'll just use nanosecond
                // resolution.
                _ticksPerSecond = ts.tv_nsec >= 1000 ? 1_000_000_000L
                                                     : 1_000_000_000L / ts.tv_nsec;
            }
        }
    }

    unittest
    {
        assert(_ticksPerSecond);
    }


    long _ticks;
}


/++
    Converts the given time from one clock frequency/resolution to another.

    See_Also:
        $(LREF ticksToNSecs)
  +/
long convClockFreq(long ticks, long srcTicksPerSecond, long dstTicksPerSecond) @safe pure nothrow @nogc
{
    // This would be more straightforward with floating point arithmetic,
    // but we avoid it here in order to avoid the rounding errors that that
    // introduces. Also, by splitting out the units in this way, we're able
    // to deal with much larger values before running into problems with
    // integer overflow.
    return ticks / srcTicksPerSecond * dstTicksPerSecond +
           ticks % srcTicksPerSecond * dstTicksPerSecond / srcTicksPerSecond;
}

///
unittest
{
    // one tick is one second -> one tick is a hecto-nanosecond
    assert(convClockFreq(45, 1, 10_000_000) == 450_000_000);

    // one tick is one microsecond -> one tick is a millisecond
    assert(convClockFreq(9029, 1_000_000, 1_000) == 9);

    // one tick is 1/3_515_654 of a second -> 1/1_001_010 of a second
    assert(convClockFreq(912_319, 3_515_654, 1_001_010) == 259_764);

    // one tick is 1/MonoTime.ticksPerSecond -> one tick is a nanosecond
    // Equivalent to ticksToNSecs
    auto nsecs = convClockFreq(1982, MonoTime.ticksPerSecond, 1_000_000_000);
}

unittest
{
    assert(convClockFreq(99, 43, 57) == 131);
    assert(convClockFreq(131, 57, 43) == 98);
    assert(convClockFreq(1234567890, 10_000_000, 1_000_000_000) == 123456789000);
    assert(convClockFreq(1234567890, 1_000_000_000, 10_000_000) == 12345678);
    assert(convClockFreq(123456789000, 1_000_000_000, 10_000_000) == 1234567890);
    assert(convClockFreq(12345678, 10_000_000, 1_000_000_000) == 1234567800);
    assert(convClockFreq(13131, 3_515_654, 10_000_000) == 37350);
    assert(convClockFreq(37350, 10_000_000, 3_515_654) == 13130);
    assert(convClockFreq(37350, 3_515_654, 10_000_000) == 106239);
    assert(convClockFreq(106239, 10_000_000, 3_515_654) == 37349);

    // It would be too expensive to cover a large range of possible values for
    // ticks, so we use random values in an attempt to get reasonable coverage.
    import core.stdc.stdlib;
    immutable seed = cast(int)time(null);
    srand(seed);
    scope(failure) printf("seed %d\n", seed);
    enum freq1 = 5_527_551L;
    enum freq2 = 10_000_000L;
    enum freq3 = 1_000_000_000L;
    enum freq4 = 98_123_320L;
    immutable freq5 = MonoTime.ticksPerSecond;

    // This makes it so that freq6 is the first multiple of 10 which is greater
    // than or equal to freq5, which at one point was considered for MonoTime's
    // ticksPerSecond rather than using the system's actual clock frequency, so
    // it seemed like a good test case to have.
    import core.stdc.math;
    immutable numDigitsMinus1 = cast(int)floor(log10(freq5));
    auto freq6 = cast(long)pow(10, numDigitsMinus1);
    if(freq5 > freq6)
        freq6 *= 10;

    foreach(_; 0 .. 10_000)
    {
        long[2] values = [rand(), cast(long)rand() * (rand() % 16)];
        foreach(i; values)
        {
            scope(failure) printf("i %s\n", numToStringz(i));
            assertApprox(convClockFreq(convClockFreq(i, freq1, freq2), freq2, freq1), i - 10, i + 10);
            assertApprox(convClockFreq(convClockFreq(i, freq2, freq1), freq1, freq2), i - 10, i + 10);

            assertApprox(convClockFreq(convClockFreq(i, freq3, freq4), freq4, freq3), i - 100, i + 100);
            assertApprox(convClockFreq(convClockFreq(i, freq4, freq3), freq3, freq4), i - 100, i + 100);

            scope(failure) printf("sys %s mt %s\n", numToStringz(freq5), numToStringz(freq6));
            assertApprox(convClockFreq(convClockFreq(i, freq5, freq6), freq6, freq5), i - 10, i + 10);
            assertApprox(convClockFreq(convClockFreq(i, freq6, freq5), freq5, freq6), i - 10, i + 10);

            // This is here rather than in a unittest block immediately after
            // ticksToNSecs in order to avoid code duplication in the unit tests.
            assert(convClockFreq(i, MonoTime.ticksPerSecond, 1_000_000_000) == ticksToNSecs(i));
        }
    }
}


/++
    Convenience wrapper around $(LREF convClockFreq) which converts ticks at
    a clock frequency of $(D MonoTime.ticksPerSecond) to nanoseconds.

    It's primarily of use when $(D MonoTime.ticksPerSecond) is greater than
    hecto-nanosecond resolution, and an application needs a higher precision
    than hecto-nanoceconds.

    See_Also:
        $(LREF convClockFreq)
  +/
long ticksToNSecs(long ticks) @safe pure nothrow @nogc
{
    return convClockFreq(ticks, MonoTime.ticksPerSecond, 1_000_000_000);
}

///
unittest
{
    auto before = MonoTime.currTime;
    // do stuff
    auto after = MonoTime.currTime;
    auto diffInTicks = after.ticks - before.ticks;
    auto diffInNSecs = ticksToNSecs(diffInTicks);
    assert(diffInNSecs == convClockFreq(diffInTicks, MonoTime.ticksPerSecond, 1_000_000_000));
}


/++
    The reverse of $(LREF ticksToNSecs).
  +/
long nsecsToTicks(long ticks) @safe pure nothrow @nogc
{
    return convClockFreq(ticks, 1_000_000_000, MonoTime.ticksPerSecond);
}

unittest
{
    long ticks = 123409832717333;
    auto nsecs = convClockFreq(ticks, MonoTime.ticksPerSecond, 1_000_000_000);
    ticks = convClockFreq(nsecs, 1_000_000_000, MonoTime.ticksPerSecond);
    assert(nsecsToTicks(nsecs) == ticks);
}



/++
    $(RED Warning: TickDuration will be deprecated in the near future (once all
          uses of it in Phobos have been deprecated). Please use
          $(LREF MonoTime) for the cases where a monotonic timestamp is needed
          and $(LREF Duration) when a duration is needed, rather than using
          TickDuration. It has been decided that TickDuration is too confusing
          (e.g. it conflates a monotonic timestamp and a duration in monotonic
           clock ticks) and that having multiple duration types is too awkward
          and confusing.)

   Represents a duration of time in system clock ticks.

   The system clock ticks are the ticks of the system clock at the highest
   precision that the system provides.
  +/
struct TickDuration
{
    /++
       The number of ticks that the system clock has in one second.

       If $(D ticksPerSec) is $(D 0), then then $(D TickDuration) failed to
       get the value of $(D ticksPerSec) on the current system, and
       $(D TickDuration) is not going to work. That would be highly abnormal
       though.
      +/
    static immutable long ticksPerSec;


    /++
        The tick of the system clock (as a $(D TickDuration)) when the
        application started.
      +/
    static immutable TickDuration appOrigin;


    static @property @safe pure nothrow @nogc
    {
    /++
        It's the same as $(D TickDuration(0)), but it's provided to be
        consistent with $(D Duration) and $(D FracSec), which provide $(D zero)
        properties.
      +/
    TickDuration zero() { return TickDuration(0); }

    /++
        Largest $(D TickDuration) possible.
      +/
    TickDuration max() { return TickDuration(long.max); }

    /++
        Most negative $(D TickDuration) possible.
      +/
    TickDuration min() { return TickDuration(long.min); }
    }

    unittest
    {
        assert(zero == TickDuration(0));
        assert(TickDuration.max == TickDuration(long.max));
        assert(TickDuration.min == TickDuration(long.min));
        assert(TickDuration.min < TickDuration.zero);
        assert(TickDuration.zero < TickDuration.max);
        assert(TickDuration.min < TickDuration.max);
        assert(TickDuration.min - TickDuration(1) == TickDuration.max);
        assert(TickDuration.max + TickDuration(1) == TickDuration.min);
    }


    @trusted shared static this()
    {
        version(Windows)
        {
            if(QueryPerformanceFrequency(cast(long*)&ticksPerSec) == 0)
                ticksPerSec = 0;
        }
        else version(OSX)
        {
            static if(is(typeof(mach_absolute_time)))
            {
                mach_timebase_info_data_t info;

                if(mach_timebase_info(&info))
                    ticksPerSec = 0;
                else
                    ticksPerSec = (1_000_000_000 * info.denom) / info.numer;
            }
            else
                ticksPerSec = 1_000_000;
        }
        else version(Posix)
        {
            static if(is(typeof(clock_gettime)))
            {
                timespec ts;

                if(clock_getres(CLOCK_MONOTONIC, &ts) != 0)
                    ticksPerSec = 0;
                else
                {
                    //For some reason, on some systems, clock_getres returns
                    //a resolution which is clearly wrong (it's a millisecond
                    //or worse, but the time is updated much more frequently
                    //than that). In such cases, we'll just use nanosecond
                    //resolution.
                    ticksPerSec = ts.tv_nsec >= 1000 ? 1_000_000_000
                                                     : 1_000_000_000 / ts.tv_nsec;
                }
            }
            else
                ticksPerSec = 1_000_000;
        }

        if(ticksPerSec != 0)
            appOrigin = TickDuration.currSystemTick;
    }

    unittest
    {
        assert(ticksPerSec);
    }


    /++
       The number of system ticks in this $(D TickDuration).

       You can convert this $(D length) into the number of seconds by dividing
       it by $(D ticksPerSec) (or using one the appropriate property function
       to do it).
      +/
    long length;


    /++
        Converts this $(D TickDuration) to the given units as either an integral
        value or a floating point value.

        Params:
            units = The units to convert to. Accepts $(D "seconds") and smaller
                    only.
            T     = The type to convert to (either an integral type or a
                    floating point type).
      +/
    T to(string units, T)() @safe const pure nothrow @nogc
        if((units == "seconds" ||
            units == "msecs" ||
            units == "usecs" ||
            units == "hnsecs" ||
            units == "nsecs") &&
           ((__traits(isIntegral, T) && T.sizeof >= 4) || __traits(isFloating, T)))
    {
        static if(__traits(isIntegral, T) && T.sizeof >= 4)
        {
            enum unitsPerSec = convert!("seconds", units)(1);

            return cast(T)(length / (ticksPerSec / cast(real)unitsPerSec));
        }
        else static if(__traits(isFloating, T))
        {
            static if(units == "seconds")
                return length / cast(T)ticksPerSec;
            else
            {
                enum unitsPerSec = convert!("seconds", units)(1);

                return to!("seconds", T)() * unitsPerSec;
            }
        }
        else
            static assert(0, "Incorrect template constraint.");
    }


    /++
        Returns the total number of seconds in this $(D TickDuration).
      +/
    @property long seconds() @safe const pure nothrow @nogc
    {
        return to!("seconds", long)();
    }

    unittest
    {
        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            assert((cast(T)TickDuration(ticksPerSec)).seconds == 1);
            assert((cast(T)TickDuration(ticksPerSec - 1)).seconds == 0);
            assert((cast(T)TickDuration(ticksPerSec * 2)).seconds == 2);
            assert((cast(T)TickDuration(ticksPerSec * 2 - 1)).seconds == 1);
            assert((cast(T)TickDuration(-1)).seconds == 0);
            assert((cast(T)TickDuration(-ticksPerSec - 1)).seconds == -1);
            assert((cast(T)TickDuration(-ticksPerSec)).seconds == -1);
        }
    }


    /++
        Returns the total number of milliseconds in this $(D TickDuration).
      +/
    @property long msecs() @safe const pure nothrow @nogc
    {
        return to!("msecs", long)();
    }


    /++
        Returns the total number of microseconds in this $(D TickDuration).
      +/
    @property long usecs() @safe const pure nothrow @nogc
    {
        return to!("usecs", long)();
    }


    /++
        Returns the total number of hecto-nanoseconds in this $(D TickDuration).
      +/
    @property long hnsecs() @safe const pure nothrow @nogc
    {
        return to!("hnsecs", long)();
    }


    /++
        Returns the total number of nanoseconds in this $(D TickDuration).
      +/
    @property long nsecs() @safe const pure nothrow @nogc
    {
        return to!("nsecs", long)();
    }


    /++
        This allows you to construct a $(D TickDuration) from the given time
        units with the given length.

        Params:
            units  = The time units of the $(D TickDuration) (e.g. $(D "msecs")).
            length = The number of units in the $(D TickDuration).
      +/
    static TickDuration from(string units)(long length) @safe pure nothrow @nogc
        if(units == "seconds" ||
           units == "msecs" ||
           units == "usecs" ||
           units == "hnsecs" ||
           units == "nsecs")
    {
        enum unitsPerSec = convert!("seconds", units)(1);

        return TickDuration(cast(long)(length * (ticksPerSec / cast(real)unitsPerSec)));
    }

    unittest
    {
        foreach(units; _TypeTuple!("seconds", "msecs", "usecs", "nsecs"))
        {
            foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
            {
                assertApprox((cast(T)TickDuration.from!units(1000)).to!(units, long)(),
                             500, 1500, units);
                assertApprox((cast(T)TickDuration.from!units(1_000_000)).to!(units, long)(),
                             900_000, 1_100_000, units);
                assertApprox((cast(T)TickDuration.from!units(2_000_000)).to!(units, long)(),
                             1_900_000, 2_100_000, units);
            }
        }
    }


    /++
        Returns a $(LREF Duration) with the same number of hnsecs as this
        $(D TickDuration).
        Note that the conventional way to convert between $(D TickDuration)
        and $(D Duration) is using $(XREF conv, to), e.g.:
        $(D tickDuration.to!Duration())
      +/
    Duration opCast(T)() @safe const pure nothrow @nogc
        if(is(_Unqual!T == Duration))
    {
        return Duration(hnsecs);
    }

    unittest
    {
        foreach(D; _TypeTuple!(Duration, const Duration, immutable Duration))
        {
            foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
            {
                auto expected = dur!"seconds"(1);
                assert(cast(D)cast(T)TickDuration.from!"seconds"(1) == expected);

                foreach(units; _TypeTuple!("msecs", "usecs", "hnsecs"))
                {
                    D actual = cast(D)cast(T)TickDuration.from!units(1_000_000);
                    assertApprox(actual, dur!units(900_000), dur!units(1_100_000));
                }
            }
        }
    }


    //Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    TickDuration opCast(T)() @safe const pure nothrow @nogc
        if(is(_Unqual!T == TickDuration))
    {
        return this;
    }


    /++
        Adds or subtracts two $(D TickDuration)s as well as assigning the result
        to this $(D TickDuration).

        The legal types of arithmetic for $(D TickDuration) using this operator
        are

        $(TABLE
        $(TR $(TD TickDuration) $(TD +=) $(TD TickDuration) $(TD -->) $(TD TickDuration))
        $(TR $(TD TickDuration) $(TD -=) $(TD TickDuration) $(TD -->) $(TD TickDuration))
        )

        Params:
            rhs = The $(D TickDuration) to add to or subtract from this
                  $(D $(D TickDuration)).
      +/
    ref TickDuration opOpAssign(string op)(TickDuration rhs) @safe pure nothrow @nogc
        if(op == "+" || op == "-")
    {
        mixin("length " ~ op ~ "= rhs.length;");
        return this;
    }

    unittest
    {
        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            auto a = TickDuration.currSystemTick;
            auto result = a += cast(T)TickDuration.currSystemTick;
            assert(a == result);
            assert(a.to!("seconds", real)() >= 0);

            auto b = TickDuration.currSystemTick;
            result = b -= cast(T)TickDuration.currSystemTick;
            assert(b == result);
            assert(b.to!("seconds", real)() <= 0);

            foreach(U; _TypeTuple!(const TickDuration, immutable TickDuration))
            {
                U u = TickDuration(12);
                static assert(!__traits(compiles, u += cast(T)TickDuration.currSystemTick));
                static assert(!__traits(compiles, u -= cast(T)TickDuration.currSystemTick));
            }
        }
    }


    /++
        Adds or subtracts two $(D TickDuration)s.

        The legal types of arithmetic for $(D TickDuration) using this operator
        are

        $(TABLE
        $(TR $(TD TickDuration) $(TD +) $(TD TickDuration) $(TD -->) $(TD TickDuration))
        $(TR $(TD TickDuration) $(TD -) $(TD TickDuration) $(TD -->) $(TD TickDuration))
        )

        Params:
            rhs = The $(D TickDuration) to add to or subtract from this
                  $(D TickDuration).
      +/
    TickDuration opBinary(string op)(TickDuration rhs) @safe const pure nothrow @nogc
        if(op == "+" || op == "-")
    {
        return TickDuration(mixin("length " ~ op ~ " rhs.length"));
    }

    unittest
    {
        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            T a = TickDuration.currSystemTick;
            T b = TickDuration.currSystemTick;
            assert((a + b).seconds > 0);
            assert((a - b).seconds <= 0);
        }
    }


    /++
        Returns the negation of this $(D TickDuration).
      +/
    TickDuration opUnary(string op)() @safe const pure nothrow @nogc
        if(op == "-")
    {
        return TickDuration(-length);
    }

    unittest
    {
        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            assert(-(cast(T)TickDuration(7)) == TickDuration(-7));
            assert(-(cast(T)TickDuration(5)) == TickDuration(-5));
            assert(-(cast(T)TickDuration(-7)) == TickDuration(7));
            assert(-(cast(T)TickDuration(-5)) == TickDuration(5));
            assert(-(cast(T)TickDuration(0)) == TickDuration(0));
        }
    }


    /++
       operator overloading "<, >, <=, >="
      +/
    int opCmp(TickDuration rhs) @safe const pure nothrow @nogc
    {
        return length < rhs.length ? -1 : (length == rhs.length ? 0 : 1);
    }

    unittest
    {
        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            foreach(U; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
            {
                T t = TickDuration.currSystemTick;
                U u = t;
                assert(t == u);
                assert(copy(t) == u);
                assert(t == copy(u));
            }
        }

        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            foreach(U; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
            {
                T t = TickDuration.currSystemTick;
                U u = t + t;
                assert(t < u);
                assert(t <= t);
                assert(u > t);
                assert(u >= u);

                assert(copy(t) < u);
                assert(copy(t) <= t);
                assert(copy(u) > t);
                assert(copy(u) >= u);

                assert(t < copy(u));
                assert(t <= copy(t));
                assert(u > copy(t));
                assert(u >= copy(u));
            }
        }
    }


    /++
        The legal types of arithmetic for $(D TickDuration) using this operator
        overload are

        $(TABLE
        $(TR $(TD TickDuration) $(TD *) $(TD long) $(TD -->) $(TD TickDuration))
        $(TR $(TD TickDuration) $(TD *) $(TD floating point) $(TD -->) $(TD TickDuration))
        )

        Params:
            value = The value to divide from this duration.
      +/
    void opOpAssign(string op, T)(T value) @safe pure nothrow @nogc
        if(op == "*" &&
           (__traits(isIntegral, T) || __traits(isFloating, T)))
    {
        length *= value;
    }

    unittest
    {
        immutable curr = TickDuration.currSystemTick;
        TickDuration t1 = curr;
        immutable t2 = curr + curr;
        t1 *= 2;
        assert(t1 == t2);

        t1 = curr;
        t1 *= 2.0;
        immutable tol = TickDuration(cast(long)(_abs(t1.length) * double.epsilon * 2.0));
        assertApprox(t1, t2 - tol, t2 + tol);

        t1 = curr;
        t1 *= 2.1;
        assert(t1 > t2);

        foreach(T; _TypeTuple!(const TickDuration, immutable TickDuration))
        {
            T t = TickDuration.currSystemTick;
            assert(!__traits(compiles, t *= 12));
            assert(!__traits(compiles, t *= 12.0));
        }
    }


    /++
        The legal types of arithmetic for $(D TickDuration) using this operator
        overload are

        $(TABLE
        $(TR $(TD TickDuration) $(TD /) $(TD long) $(TD -->) $(TD TickDuration))
        $(TR $(TD TickDuration) $(TD /) $(TD floating point) $(TD -->) $(TD TickDuration))
        )

        Params:
            value = The value to divide from this $(D TickDuration).

        Throws:
            $(D TimeException) if an attempt to divide by $(D 0) is made.
      +/
    void opOpAssign(string op, T)(T value) @safe pure
        if(op == "/" &&
           (__traits(isIntegral, T) || __traits(isFloating, T)))
    {
        if(value == 0)
            throw new TimeException("Attempted division by 0.");

        length /= value;
    }

    unittest
    {
        immutable curr = TickDuration.currSystemTick;
        immutable t1 = curr;
        TickDuration t2 = curr + curr;
        t2 /= 2;
        assert(t1 == t2);

        t2 = curr + curr;
        t2 /= 2.0;
        immutable tol = TickDuration(cast(long)(_abs(t2.length) * double.epsilon / 2.0));
        assertApprox(t1, t2 - tol, t2 + tol);

        t2 = curr + curr;
        t2 /= 2.1;
        assert(t1 > t2);

        _assertThrown!TimeException(t2 /= 0);

        foreach(T; _TypeTuple!(const TickDuration, immutable TickDuration))
        {
            T t = TickDuration.currSystemTick;
            assert(!__traits(compiles, t /= 12));
            assert(!__traits(compiles, t /= 12.0));
        }
    }


    /++
        The legal types of arithmetic for $(D TickDuration) using this operator
        overload are

        $(TABLE
        $(TR $(TD TickDuration) $(TD *) $(TD long) $(TD -->) $(TD TickDuration))
        $(TR $(TD TickDuration) $(TD *) $(TD floating point) $(TD -->) $(TD TickDuration))
        )

        Params:
            value = The value to divide from this $(D TickDuration).
      +/
    TickDuration opBinary(string op, T)(T value) @safe const pure nothrow @nogc
        if(op == "*" &&
           (__traits(isIntegral, T) || __traits(isFloating, T)))
    {
        return TickDuration(cast(long)(length * value));
    }

    unittest
    {
        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            T t1 = TickDuration.currSystemTick;
            T t2 = t1 + t1;
            assert(t1 * 2 == t2);
            immutable tol = TickDuration(cast(long)(_abs(t1.length) * double.epsilon * 2.0));
            assertApprox(t1 * 2.0, t2 - tol, t2 + tol);
            assert(t1 * 2.1 > t2);
        }
    }


    /++
        The legal types of arithmetic for $(D TickDuration) using this operator
        overload are

        $(TABLE
        $(TR $(TD TickDuration) $(TD /) $(TD long) $(TD -->) $(TD TickDuration))
        $(TR $(TD TickDuration) $(TD /) $(TD floating point) $(TD -->) $(TD TickDuration))
        )

        Params:
            value = The value to divide from this $(D TickDuration).

        Throws:
            $(D TimeException) if an attempt to divide by $(D 0) is made.
      +/
    TickDuration opBinary(string op, T)(T value) @safe const pure
        if(op == "/" &&
           (__traits(isIntegral, T) || __traits(isFloating, T)))
    {
        if(value == 0)
            throw new TimeException("Attempted division by 0.");

        return TickDuration(cast(long)(length / value));
    }

    unittest
    {
        foreach(T; _TypeTuple!(TickDuration, const TickDuration, immutable TickDuration))
        {
            T t1 = TickDuration.currSystemTick;
            T t2 = t1 + t1;
            assert(t2 / 2 == t1);
            immutable tol = TickDuration(cast(long)(_abs(t2.length) * double.epsilon / 2.0));
            assertApprox(t2 / 2.0, t1 - tol, t1 + tol);
            assert(t2 / 2.1 < t1);

            _assertThrown!TimeException(t2 / 0);
        }
    }


    /++
        Params:
            ticks = The number of ticks in the TickDuration.
      +/
    @safe pure nothrow @nogc this(long ticks)
    {
        this.length = ticks;
    }

    unittest
    {
        foreach(i; [-42, 0, 42])
            assert(TickDuration(i).length == i);
    }


    /++
        The current system tick. The number of ticks per second varies from
        system to system. $(D currSystemTick) uses a monotonic clock, so it's
        intended for precision timing by comparing relative time values, not for
        getting the current system time.

        On Windows, $(D QueryPerformanceCounter) is used. On Mac OS X,
        $(D mach_absolute_time) is used, while on other Posix systems,
        $(D clock_gettime) is used. If $(D mach_absolute_time) or
        $(D clock_gettime) is unavailable, then Posix systems use
        $(D gettimeofday) (the decision is made when $(D TickDuration) is
        compiled), which unfortunately, is not monotonic, but if
        $(D mach_absolute_time) and $(D clock_gettime) aren't available, then
        $(D gettimeofday) is the the best that there is.

        $(RED Warning):
            On some systems, the monotonic clock may stop counting when
            the computer goes to sleep or hibernates. So, the monotonic
            clock could be off if that occurs. This is known to happen
            on Mac OS X. It has not been tested whether it occurs on
            either Windows or on Linux.

        Throws:
            $(D TimeException) if it fails to get the time.
      +/
    static @property TickDuration currSystemTick() @trusted nothrow @nogc
    {
        version(Windows)
        {
            ulong ticks;
            if(QueryPerformanceCounter(cast(long*)&ticks) == 0)
                assert(0, "Failed in QueryPerformanceCounter().");

            return TickDuration(ticks);
        }
        else version(OSX)
        {
            static if(is(typeof(mach_absolute_time)))
                return TickDuration(cast(long)mach_absolute_time());
            else
            {
                timeval tv;
                if(gettimeofday(&tv, null) != 0)
                    assert(0, "Failed in gettimeofday().");

                return TickDuration(tv.tv_sec * TickDuration.ticksPerSec +
                                    tv.tv_usec * TickDuration.ticksPerSec / 1000 / 1000);
            }
        }
        else version(Posix)
        {
            static if(is(typeof(clock_gettime)))
            {
                timespec ts;
                if(clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
                    assert(0, "Failed in clock_gettime().");

                return TickDuration(ts.tv_sec * TickDuration.ticksPerSec +
                                    ts.tv_nsec * TickDuration.ticksPerSec / 1000 / 1000 / 1000);
            }
            else
            {
                timeval tv;
                if(gettimeofday(&tv, null) != 0)
                    assert(0, "Failed in gettimeofday().");

                return TickDuration(tv.tv_sec * TickDuration.ticksPerSec +
                                    tv.tv_usec * TickDuration.ticksPerSec / 1000 / 1000);
            }
        }
    }

    @safe nothrow unittest
    {
        assert(TickDuration.currSystemTick.length > 0);
    }
}


/++
    Generic way of converting between two time units. Conversions to smaller
    units use truncating division. Years and months can be converted to each
    other, small units can be converted to each other, but years and months
    cannot be converted to or from smaller units (due to the varying number
    of days in a month or year).

    Params:
        from  = The units of time to convert from.
        to    = The units of time to convert to.
        value = The value to convert.

    Examples:
--------------------
assert(convert!("years", "months")(1) == 12);
assert(convert!("months", "years")(12) == 1);

assert(convert!("weeks", "days")(1) == 7);
assert(convert!("hours", "seconds")(1) == 3600);
assert(convert!("seconds", "days")(1) == 0);
assert(convert!("seconds", "days")(86_400) == 1);

assert(convert!("nsecs", "nsecs")(1) == 1);
assert(convert!("nsecs", "hnsecs")(1) == 0);
assert(convert!("hnsecs", "nsecs")(1) == 100);
assert(convert!("nsecs", "seconds")(1) == 0);
assert(convert!("seconds", "nsecs")(1) == 1_000_000_000);
--------------------
  +/
long convert(string from, string to)(long value) @safe pure nothrow @nogc
    if(((from == "weeks" ||
         from == "days" ||
         from == "hours" ||
         from == "minutes" ||
         from == "seconds" ||
         from == "msecs" ||
         from == "usecs" ||
         from == "hnsecs" ||
         from == "nsecs") &&
        (to == "weeks" ||
         to == "days" ||
         to == "hours" ||
         to == "minutes" ||
         to == "seconds" ||
         to == "msecs" ||
         to == "usecs" ||
         to == "hnsecs" ||
         to == "nsecs")) ||
       ((from == "years" || from == "months") && (to == "years" || to == "months")))
{
    static if(from == "years")
    {
        static if(to == "years")
            return value;
        else static if(to == "months")
            return value * 12;
        else
            static assert(0, "A generic month or year cannot be converted to or from smaller units.");
    }
    else static if(from == "months")
    {
        static if(to == "years")
            return value / 12;
        else static if(to == "months")
            return value;
        else
            static assert(0, "A generic month or year cannot be converted to or from smaller units.");
    }
    else static if(from == "nsecs" && to == "nsecs")
        return value;
    else static if(from == "nsecs")
        return convert!("hnsecs", to)(value / 100);
    else static if(to == "nsecs")
        return convert!(from, "hnsecs")(value) * 100;
    else
        return (hnsecsPer!from * value) / hnsecsPer!to;
}

//Verify Examples
unittest
{
    assert(convert!("years", "months")(1) == 12);
    assert(convert!("months", "years")(12) == 1);

    assert(convert!("weeks", "days")(1) == 7);
    assert(convert!("hours", "seconds")(1) == 3600);
    assert(convert!("seconds", "days")(1) == 0);
    assert(convert!("seconds", "days")(86_400) == 1);

    assert(convert!("nsecs", "nsecs")(1) == 1);
    assert(convert!("nsecs", "hnsecs")(1) == 0);
    assert(convert!("hnsecs", "nsecs")(1) == 100);
    assert(convert!("nsecs", "seconds")(1) == 0);
    assert(convert!("seconds", "nsecs")(1) == 1_000_000_000);
}

unittest
{
    foreach(units; _TypeTuple!("weeks", "days", "hours", "seconds", "msecs", "usecs", "hnsecs", "nsecs"))
    {
        static assert(!__traits(compiles, convert!("years", units)(12)), units);
        static assert(!__traits(compiles, convert!(units, "years")(12)), units);
    }

    foreach(units; _TypeTuple!("years", "months", "weeks", "days",
                               "hours", "seconds", "msecs", "usecs", "hnsecs", "nsecs"))
    {
        assert(convert!(units, units)(12) == 12);
    }

    assert(convert!("weeks", "hnsecs")(1) == 6_048_000_000_000L);
    assert(convert!("days", "hnsecs")(1) == 864_000_000_000L);
    assert(convert!("hours", "hnsecs")(1) == 36_000_000_000L);
    assert(convert!("minutes", "hnsecs")(1) == 600_000_000L);
    assert(convert!("seconds", "hnsecs")(1) == 10_000_000L);
    assert(convert!("msecs", "hnsecs")(1) == 10_000);
    assert(convert!("usecs", "hnsecs")(1) == 10);

    assert(convert!("hnsecs", "weeks")(6_048_000_000_000L) == 1);
    assert(convert!("hnsecs", "days")(864_000_000_000L) == 1);
    assert(convert!("hnsecs", "hours")(36_000_000_000L) == 1);
    assert(convert!("hnsecs", "minutes")(600_000_000L) == 1);
    assert(convert!("hnsecs", "seconds")(10_000_000L) == 1);
    assert(convert!("hnsecs", "msecs")(10_000) == 1);
    assert(convert!("hnsecs", "usecs")(10) == 1);

    assert(convert!("weeks", "days")(1) == 7);
    assert(convert!("days", "weeks")(7) == 1);

    assert(convert!("days", "hours")(1) == 24);
    assert(convert!("hours", "days")(24) == 1);

    assert(convert!("hours", "minutes")(1) == 60);
    assert(convert!("minutes", "hours")(60) == 1);

    assert(convert!("minutes", "seconds")(1) == 60);
    assert(convert!("seconds", "minutes")(60) == 1);

    assert(convert!("seconds", "msecs")(1) == 1000);
    assert(convert!("msecs", "seconds")(1000) == 1);

    assert(convert!("msecs", "usecs")(1) == 1000);
    assert(convert!("usecs", "msecs")(1000) == 1);

    assert(convert!("usecs", "hnsecs")(1) == 10);
    assert(convert!("hnsecs", "usecs")(10) == 1);

    assert(convert!("weeks", "nsecs")(1) == 604_800_000_000_000L);
    assert(convert!("days", "nsecs")(1) == 86_400_000_000_000L);
    assert(convert!("hours", "nsecs")(1) == 3_600_000_000_000L);
    assert(convert!("minutes", "nsecs")(1) == 60_000_000_000L);
    assert(convert!("seconds", "nsecs")(1) == 1_000_000_000L);
    assert(convert!("msecs", "nsecs")(1) == 1_000_000);
    assert(convert!("usecs", "nsecs")(1) == 1000);
    assert(convert!("hnsecs", "nsecs")(1) == 100);

    assert(convert!("nsecs", "weeks")(604_800_000_000_000L) == 1);
    assert(convert!("nsecs", "days")(86_400_000_000_000L) == 1);
    assert(convert!("nsecs", "hours")(3_600_000_000_000L) == 1);
    assert(convert!("nsecs", "minutes")(60_000_000_000L) == 1);
    assert(convert!("nsecs", "seconds")(1_000_000_000L) == 1);
    assert(convert!("nsecs", "msecs")(1_000_000) == 1);
    assert(convert!("nsecs", "usecs")(1000) == 1);
    assert(convert!("nsecs", "hnsecs")(100) == 1);
}


/++
    Represents fractional seconds.

    This is the portion of the time which is smaller than a second and it cannot
    hold values which would be greater than or equal to a second (or less than
    or equal to a negative second).

    It holds hnsecs internally, but you can create it using either milliseconds,
    microseconds, or hnsecs. What it does is allow for a simple way to set or
    adjust the fractional seconds portion of a $(D Duration) or a
    $(XREF datetime, SysTime) without having to worry about whether you're
    dealing with milliseconds, microseconds, or hnsecs.

    $(D FracSec)'s functions which take time unit strings do accept
    $(D "nsecs"), but because the resolution of $(D Duration) and
    $(XREF datetime, SysTime) is hnsecs, you don't actually get precision higher
    than hnsecs. $(D "nsecs") is accepted merely for convenience. Any values
    given as nsecs will be converted to hnsecs using $(D convert) (which uses
    truncating division when converting to smaller units).
  +/
struct FracSec
{
@safe pure:

public:

    /++
        A $(D FracSec) of $(D 0). It's shorter than doing something like
        $(D FracSec.from!"msecs"(0)) and more explicit than $(D FracSec.init).
      +/
    static @property nothrow @nogc FracSec zero() { return FracSec(0); }

    unittest
    {
        assert(zero == FracSec.from!"msecs"(0));
    }


    /++
        Create a $(D FracSec) from the given units ($(D "msecs"), $(D "usecs"),
        or $(D "hnsecs")).

        Params:
            units = The units to create a FracSec from.
            value = The number of the given units passed the second.

        Throws:
            $(D TimeException) if the given value would result in a $(D FracSec)
            greater than or equal to $(D 1) second or less than or equal to
            $(D -1) seconds.
      +/
    static FracSec from(string units)(long value)
        if(units == "msecs" ||
           units == "usecs" ||
           units == "hnsecs" ||
           units == "nsecs")
    {
        immutable hnsecs = cast(int)convert!(units, "hnsecs")(value);
        _enforceValid(hnsecs);
        return FracSec(hnsecs);
    }

    unittest
    {
        assert(FracSec.from!"msecs"(0) == FracSec(0));
        assert(FracSec.from!"usecs"(0) == FracSec(0));
        assert(FracSec.from!"hnsecs"(0) == FracSec(0));

        foreach(sign; [1, -1])
        {
            _assertThrown!TimeException(from!"msecs"(1000 * sign));

            assert(FracSec.from!"msecs"(1 * sign) == FracSec(10_000 * sign));
            assert(FracSec.from!"msecs"(999 * sign) == FracSec(9_990_000 * sign));

            _assertThrown!TimeException(from!"usecs"(1_000_000 * sign));

            assert(FracSec.from!"usecs"(1 * sign) == FracSec(10 * sign));
            assert(FracSec.from!"usecs"(999 * sign) == FracSec(9990 * sign));
            assert(FracSec.from!"usecs"(999_999 * sign) == FracSec(9999_990 * sign));

            _assertThrown!TimeException(from!"hnsecs"(10_000_000 * sign));

            assert(FracSec.from!"hnsecs"(1 * sign) == FracSec(1 * sign));
            assert(FracSec.from!"hnsecs"(999 * sign) == FracSec(999 * sign));
            assert(FracSec.from!"hnsecs"(999_999 * sign) == FracSec(999_999 * sign));
            assert(FracSec.from!"hnsecs"(9_999_999 * sign) == FracSec(9_999_999 * sign));

            assert(FracSec.from!"nsecs"(1 * sign) == FracSec(0));
            assert(FracSec.from!"nsecs"(10 * sign) == FracSec(0));
            assert(FracSec.from!"nsecs"(99 * sign) == FracSec(0));
            assert(FracSec.from!"nsecs"(100 * sign) == FracSec(1 * sign));
            assert(FracSec.from!"nsecs"(99_999 * sign) == FracSec(999 * sign));
            assert(FracSec.from!"nsecs"(99_999_999 * sign) == FracSec(999_999 * sign));
            assert(FracSec.from!"nsecs"(999_999_999 * sign) == FracSec(9_999_999 * sign));
        }
    }


    /++
        Returns the negation of this $(D FracSec).
      +/
    FracSec opUnary(string op)() const nothrow @nogc
        if(op == "-")
    {
        return FracSec(-_hnsecs);
    }

    unittest
    {
        foreach(val; [-7, -5, 0, 5, 7])
        {
            foreach(F; _TypeTuple!(FracSec, const FracSec, immutable FracSec))
            {
                F fs = FracSec(val);
                assert(-fs == FracSec(-val));
            }
        }
    }


    /++
        The value of this $(D FracSec) as milliseconds.
      +/
    @property int msecs() const nothrow @nogc
    {
        return cast(int)convert!("hnsecs", "msecs")(_hnsecs);
    }

    unittest
    {
        foreach(F; _TypeTuple!(FracSec, const FracSec, immutable FracSec))
        {
            assert(FracSec(0).msecs == 0);

            foreach(sign; [1, -1])
            {
                assert((cast(F)FracSec(1 * sign)).msecs == 0);
                assert((cast(F)FracSec(999 * sign)).msecs == 0);
                assert((cast(F)FracSec(999_999 * sign)).msecs == 99 * sign);
                assert((cast(F)FracSec(9_999_999 * sign)).msecs == 999 * sign);
            }
        }
    }


    /++
        The value of this $(D FracSec) as milliseconds.

        Params:
            milliseconds = The number of milliseconds passed the second.

        Throws:
            $(D TimeException) if the given value is not less than $(D 1) second
            and greater than a $(D -1) seconds.
      +/
    @property void msecs(int milliseconds)
    {
        immutable hnsecs = cast(int)convert!("msecs", "hnsecs")(milliseconds);
        _enforceValid(hnsecs);
        _hnsecs = hnsecs;
    }

    unittest
    {
        static void test(int msecs, FracSec expected = FracSec.init, size_t line = __LINE__)
        {
            FracSec fs;
            fs.msecs = msecs;

            if(fs != expected)
                throw new AssertError("unittest failure", __FILE__, line);
        }

        _assertThrown!TimeException(test(-1000));
        _assertThrown!TimeException(test(1000));

        test(0, FracSec(0));

        foreach(sign; [1, -1])
        {
            test(1 * sign, FracSec(10_000 * sign));
            test(999 * sign, FracSec(9_990_000 * sign));
        }

        foreach(F; _TypeTuple!(const FracSec, immutable FracSec))
        {
            F fs = FracSec(1234567);
            static assert(!__traits(compiles, fs.msecs = 12), F.stringof);
        }
    }


    /++
        The value of this $(D FracSec) as microseconds.
      +/
    @property int usecs() const nothrow @nogc
    {
        return cast(int)convert!("hnsecs", "usecs")(_hnsecs);
    }

    unittest
    {
        foreach(F; _TypeTuple!(FracSec, const FracSec, immutable FracSec))
        {
            assert(FracSec(0).usecs == 0);

            foreach(sign; [1, -1])
            {
                assert((cast(F)FracSec(1 * sign)).usecs == 0);
                assert((cast(F)FracSec(999 * sign)).usecs == 99 * sign);
                assert((cast(F)FracSec(999_999 * sign)).usecs == 99_999 * sign);
                assert((cast(F)FracSec(9_999_999 * sign)).usecs == 999_999 * sign);
            }
        }
    }


    /++
        The value of this $(D FracSec) as microseconds.

        Params:
            microseconds = The number of microseconds passed the second.

        Throws:
            $(D TimeException) if the given value is not less than $(D 1) second
            and greater than a $(D -1) seconds.
      +/
    @property void usecs(int microseconds)
    {
        immutable hnsecs = cast(int)convert!("usecs", "hnsecs")(microseconds);
        _enforceValid(hnsecs);
        _hnsecs = hnsecs;
    }

    unittest
    {
        static void test(int usecs, FracSec expected = FracSec.init, size_t line = __LINE__)
        {
            FracSec fs;
            fs.usecs = usecs;

            if(fs != expected)
                throw new AssertError("unittest failure", __FILE__, line);
        }

        _assertThrown!TimeException(test(-1_000_000));
        _assertThrown!TimeException(test(1_000_000));

        test(0, FracSec(0));

        foreach(sign; [1, -1])
        {
            test(1 * sign, FracSec(10 * sign));
            test(999 * sign, FracSec(9990 * sign));
            test(999_999 * sign, FracSec(9_999_990 * sign));
        }

        foreach(F; _TypeTuple!(const FracSec, immutable FracSec))
        {
            F fs = FracSec(1234567);
            static assert(!__traits(compiles, fs.usecs = 12), F.stringof);
        }
    }


    /++
        The value of this $(D FracSec) as hnsecs.
      +/
    @property int hnsecs() const nothrow @nogc
    {
        return _hnsecs;
    }

    unittest
    {
        foreach(F; _TypeTuple!(FracSec, const FracSec, immutable FracSec))
        {
            assert(FracSec(0).hnsecs == 0);

            foreach(sign; [1, -1])
            {
                assert((cast(F)FracSec(1 * sign)).hnsecs == 1 * sign);
                assert((cast(F)FracSec(999 * sign)).hnsecs == 999 * sign);
                assert((cast(F)FracSec(999_999 * sign)).hnsecs == 999_999 * sign);
                assert((cast(F)FracSec(9_999_999 * sign)).hnsecs == 9_999_999 * sign);
            }
        }
    }


    /++
        The value of this $(D FracSec) as hnsecs.

        Params:
            hnsecs = The number of hnsecs passed the second.

        Throws:
            $(D TimeException) if the given value is not less than $(D 1) second
            and greater than a $(D -1) seconds.
      +/
    @property void hnsecs(int hnsecs)
    {
        _enforceValid(hnsecs);
        _hnsecs = hnsecs;
    }

    unittest
    {
        static void test(int hnsecs, FracSec expected = FracSec.init, size_t line = __LINE__)
        {
            FracSec fs;
            fs.hnsecs = hnsecs;

            if(fs != expected)
                throw new AssertError("unittest failure", __FILE__, line);
        }

        _assertThrown!TimeException(test(-10_000_000));
        _assertThrown!TimeException(test(10_000_000));

        test(0, FracSec(0));

        foreach(sign; [1, -1])
        {
            test(1 * sign, FracSec(1 * sign));
            test(999 * sign, FracSec(999 * sign));
            test(999_999 * sign, FracSec(999_999 * sign));
            test(9_999_999 * sign, FracSec(9_999_999 * sign));
        }

        foreach(F; _TypeTuple!(const FracSec, immutable FracSec))
        {
            F fs = FracSec(1234567);
            static assert(!__traits(compiles, fs.hnsecs = 12), F.stringof);
        }
    }


    /++
        The value of this $(D FracSec) as nsecs.

        Note that this does not give you any greater precision
        than getting the value of this $(D FracSec) as hnsecs.
      +/
    @property int nsecs() const nothrow @nogc
    {
        return cast(int)convert!("hnsecs", "nsecs")(_hnsecs);
    }

    unittest
    {
        foreach(F; _TypeTuple!(FracSec, const FracSec, immutable FracSec))
        {
            assert(FracSec(0).nsecs == 0);

            foreach(sign; [1, -1])
            {
                assert((cast(F)FracSec(1 * sign)).nsecs == 100 * sign);
                assert((cast(F)FracSec(999 * sign)).nsecs == 99_900 * sign);
                assert((cast(F)FracSec(999_999 * sign)).nsecs == 99_999_900 * sign);
                assert((cast(F)FracSec(9_999_999 * sign)).nsecs == 999_999_900 * sign);
            }
        }
    }


    /++
        The value of this $(D FracSec) as nsecs.

        Note that this does not give you any greater precision
        than setting the value of this $(D FracSec) as hnsecs.

        Params:
            nsecs = The number of nsecs passed the second.

        Throws:
            $(D TimeException) if the given value is not less than $(D 1) second
            and greater than a $(D -1) seconds.
      +/
    @property void nsecs(long nsecs)
    {
        immutable hnsecs = cast(int)convert!("nsecs", "hnsecs")(nsecs);
        _enforceValid(hnsecs);
        _hnsecs = hnsecs;
    }

    unittest
    {
        static void test(int nsecs, FracSec expected = FracSec.init, size_t line = __LINE__)
        {
            FracSec fs;
            fs.nsecs = nsecs;

            if(fs != expected)
                throw new AssertError("unittest failure", __FILE__, line);
        }

        _assertThrown!TimeException(test(-1_000_000_000));
        _assertThrown!TimeException(test(1_000_000_000));

        test(0, FracSec(0));

        foreach(sign; [1, -1])
        {
            test(1 * sign, FracSec(0));
            test(10 * sign, FracSec(0));
            test(100 * sign, FracSec(1 * sign));
            test(999 * sign, FracSec(9 * sign));
            test(999_999 * sign, FracSec(9999 * sign));
            test(9_999_999 * sign, FracSec(99_999 * sign));
        }

        foreach(F; _TypeTuple!(const FracSec, immutable FracSec))
        {
            F fs = FracSec(1234567);
            static assert(!__traits(compiles, fs.nsecs = 12), F.stringof);
        }
    }


    /+
        Converts this $(D TickDuration) to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString()
    {
        return _toStringImpl();
    }


    /++
        Converts this $(D TickDuration) to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString() const nothrow
    {
        return _toStringImpl();
    }

    unittest
    {
        auto fs = FracSec(12);
        const cfs = FracSec(12);
        immutable ifs = FracSec(12);
        assert(fs.toString() == "12 hnsecs");
        assert(cfs.toString() == "12 hnsecs");
        assert(ifs.toString() == "12 hnsecs");
    }


private:

    /+
        Since we have two versions of $(D toString), we have $(D _toStringImpl)
        so that they can share implementations.
      +/
    string _toStringImpl() const nothrow
    {
        try
        {
            long hnsecs = _hnsecs;

            immutable milliseconds = splitUnitsFromHNSecs!"msecs"(hnsecs);
            immutable microseconds = splitUnitsFromHNSecs!"usecs"(hnsecs);

            if(hnsecs == 0)
            {
                if(microseconds == 0)
                {
                    if(milliseconds == 0)
                        return "0 hnsecs";
                    else
                    {
                        if(milliseconds == 1)
                            return "1 ms";
                        else
                            return numToString(milliseconds) ~ " ms";
                    }
                }
                else
                {
                    immutable fullMicroseconds = getUnitsFromHNSecs!"usecs"(_hnsecs);

                    if(fullMicroseconds == 1)
                        return "1 μs";
                    else
                        return numToString(fullMicroseconds) ~ " μs";
                }
            }
            else
            {
                if(_hnsecs == 1)
                    return "1 hnsec";
                else
                    return numToString(_hnsecs) ~ " hnsecs";
            }
        }
        catch(Exception e)
            assert(0, "Something threw when nothing can throw.");
    }

    unittest
    {
        foreach(sign; [1 , -1])
        {
            immutable signStr = sign == 1 ? "" : "-";

            assert(FracSec.from!"msecs"(0 * sign).toString() == "0 hnsecs");
            assert(FracSec.from!"msecs"(1 * sign).toString() == signStr ~ "1 ms");
            assert(FracSec.from!"msecs"(2 * sign).toString() == signStr ~ "2 ms");
            assert(FracSec.from!"msecs"(100 * sign).toString() == signStr ~ "100 ms");
            assert(FracSec.from!"msecs"(999 * sign).toString() == signStr ~ "999 ms");

            assert(FracSec.from!"usecs"(0* sign).toString() == "0 hnsecs");
            assert(FracSec.from!"usecs"(1* sign).toString() == signStr ~ "1 μs");
            assert(FracSec.from!"usecs"(2* sign).toString() == signStr ~ "2 μs");
            assert(FracSec.from!"usecs"(100* sign).toString() == signStr ~ "100 μs");
            assert(FracSec.from!"usecs"(999* sign).toString() == signStr ~ "999 μs");
            assert(FracSec.from!"usecs"(1000* sign).toString() == signStr ~ "1 ms");
            assert(FracSec.from!"usecs"(2000* sign).toString() == signStr ~ "2 ms");
            assert(FracSec.from!"usecs"(9999* sign).toString() == signStr ~ "9999 μs");
            assert(FracSec.from!"usecs"(10_000* sign).toString() == signStr ~ "10 ms");
            assert(FracSec.from!"usecs"(20_000* sign).toString() == signStr ~ "20 ms");
            assert(FracSec.from!"usecs"(100_000* sign).toString() == signStr ~ "100 ms");
            assert(FracSec.from!"usecs"(100_001* sign).toString() == signStr ~ "100001 μs");
            assert(FracSec.from!"usecs"(999_999* sign).toString() == signStr ~ "999999 μs");

            assert(FracSec.from!"hnsecs"(0* sign).toString() == "0 hnsecs");
            assert(FracSec.from!"hnsecs"(1* sign).toString() == (sign == 1 ? "1 hnsec" : "-1 hnsecs"));
            assert(FracSec.from!"hnsecs"(2* sign).toString() == signStr ~ "2 hnsecs");
            assert(FracSec.from!"hnsecs"(100* sign).toString() == signStr ~ "10 μs");
            assert(FracSec.from!"hnsecs"(999* sign).toString() == signStr ~ "999 hnsecs");
            assert(FracSec.from!"hnsecs"(1000* sign).toString() == signStr ~ "100 μs");
            assert(FracSec.from!"hnsecs"(2000* sign).toString() == signStr ~ "200 μs");
            assert(FracSec.from!"hnsecs"(9999* sign).toString() == signStr ~ "9999 hnsecs");
            assert(FracSec.from!"hnsecs"(10_000* sign).toString() == signStr ~ "1 ms");
            assert(FracSec.from!"hnsecs"(20_000* sign).toString() == signStr ~ "2 ms");
            assert(FracSec.from!"hnsecs"(100_000* sign).toString() == signStr ~ "10 ms");
            assert(FracSec.from!"hnsecs"(100_001* sign).toString() == signStr ~ "100001 hnsecs");
            assert(FracSec.from!"hnsecs"(200_000* sign).toString() == signStr ~ "20 ms");
            assert(FracSec.from!"hnsecs"(999_999* sign).toString() == signStr ~ "999999 hnsecs");
            assert(FracSec.from!"hnsecs"(1_000_001* sign).toString() == signStr ~ "1000001 hnsecs");
            assert(FracSec.from!"hnsecs"(9_999_999* sign).toString() == signStr ~ "9999999 hnsecs");
        }
    }


    /+
        Returns whether the given number of hnsecs fits within the range of
        $(D FracSec).

        Params:
            hnsecs = The number of hnsecs.
      +/
    static bool _valid(int hnsecs) nothrow @nogc
    {
        immutable second = convert!("seconds", "hnsecs")(1);
        return hnsecs > -second && hnsecs < second;
    }


    /+
        Throws:
            $(D TimeException) if $(D valid(hnsecs)) is $(D false).
      +/
    static void _enforceValid(int hnsecs)
    {
        if(!_valid(hnsecs))
            throw new TimeException("FracSec must be greater than equal to 0 and less than 1 second.");
    }


    /+
        Params:
            hnsecs = The number of hnsecs passed the second.
      +/
    this(int hnsecs) nothrow @nogc
    {
        _hnsecs = hnsecs;
    }


    invariant()
    {
        if(!_valid(_hnsecs))
            throw new AssertError("Invaliant Failure: hnsecs [" ~ numToString(_hnsecs) ~ "]", __FILE__, __LINE__);
    }


    int _hnsecs;
}


/++
    Exception type used by core.time.
  +/
class TimeException : Exception
{
    /++
        Params:
            msg  = The message for the exception.
            file = The file where the exception occurred.
            line = The line number where the exception occurred.
            next = The previous exception in the chain of exceptions, if any.
      +/
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow
    {
        super(msg, file, line, next);
    }

    /++
        Params:
            msg  = The message for the exception.
            next = The previous exception in the chain of exceptions.
            file = The file where the exception occurred.
            line = The line number where the exception occurred.
      +/
    this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow
    {
        super(msg, file, line, next);
    }
}

unittest
{
    {
        auto e = new TimeException("hello");
        assert(e.msg == "hello");
        assert(e.file == __FILE__);
        assert(e.line == __LINE__ - 3);
        assert(e.next is null);
    }

    {
        auto next = new Exception("foo");
        auto e = new TimeException("goodbye", next);
        assert(e.msg == "goodbye");
        assert(e.file == __FILE__);
        assert(e.line == __LINE__ - 3);
        assert(e.next is next);
    }
}



/++
    Returns the absolute value of a duration.
  +/
Duration abs(Duration duration) @safe pure nothrow @nogc
{
    return Duration(_abs(duration._hnsecs));
}

/++ Ditto +/
TickDuration abs(TickDuration duration) @safe pure nothrow @nogc
{
    return TickDuration(_abs(duration.length));
}

unittest
{
    assert(abs(dur!"msecs"(5)) == dur!"msecs"(5));
    assert(abs(dur!"msecs"(-5)) == dur!"msecs"(5));

    assert(abs(TickDuration(17)) == TickDuration(17));
    assert(abs(TickDuration(-17)) == TickDuration(17));
}


//==============================================================================
// Private Section.
//
// Much of this is a copy or simplified copy of what's in std.datetime.
//==============================================================================
private:


/+
    Template to help with converting between time units.
 +/
template hnsecsPer(string units)
    if(units == "weeks" ||
       units == "days" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds" ||
       units == "msecs" ||
       units == "usecs" ||
       units == "hnsecs")
{
    static if(units == "hnsecs")
        enum hnsecsPer = 1L;
    else static if(units == "usecs")
        enum hnsecsPer = 10L;
    else static if(units == "msecs")
        enum hnsecsPer = 1000 * hnsecsPer!"usecs";
    else static if(units == "seconds")
        enum hnsecsPer = 1000 * hnsecsPer!"msecs";
    else static if(units == "minutes")
        enum hnsecsPer = 60 * hnsecsPer!"seconds";
    else static if(units == "hours")
        enum hnsecsPer = 60 * hnsecsPer!"minutes";
    else static if(units == "days")
        enum hnsecsPer = 24 * hnsecsPer!"hours";
    else static if(units == "weeks")
        enum hnsecsPer = 7 * hnsecsPer!"days";
}

/+
    Splits out a particular unit from hnsecs and gives you the value for that
    unit and the remaining hnsecs. It really shouldn't be used unless all units
    larger than the given units have already been split out.

    Params:
        units  = The units to split out.
        hnsecs = The current total hnsecs. Upon returning, it is the hnsecs left
                 after splitting out the given units.

    Returns:
        The number of the given units from converting hnsecs to those units.

    Examples:
--------------------
auto hnsecs = 2595000000007L;
immutable days = splitUnitsFromHNSecs!"days"(hnsecs);
assert(days == 3);
assert(hnsecs == 3000000007);

immutable minutes = splitUnitsFromHNSecs!"minutes"(hnsecs);
assert(minutes == 5);
assert(hnsecs == 7);
--------------------
  +/
long splitUnitsFromHNSecs(string units)(ref long hnsecs) @safe pure nothrow @nogc
    if(units == "weeks" ||
       units == "days" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds" ||
       units == "msecs" ||
       units == "usecs" ||
       units == "hnsecs")
{
    immutable value = convert!("hnsecs", units)(hnsecs);
    hnsecs -= convert!(units, "hnsecs")(value);

    return value;
}

//Verify Examples.
unittest
{
    auto hnsecs = 2595000000007L;
    immutable days = splitUnitsFromHNSecs!"days"(hnsecs);
    assert(days == 3);
    assert(hnsecs == 3000000007);

    immutable minutes = splitUnitsFromHNSecs!"minutes"(hnsecs);
    assert(minutes == 5);
    assert(hnsecs == 7);
}


/+
    This function is used to split out the units without getting the remaining
    hnsecs.

    See_Also:
        $(LREF splitUnitsFromHNSecs)

    Params:
        units  = The units to split out.
        hnsecs = The current total hnsecs.

    Returns:
        The split out value.

    Examples:
--------------------
auto hnsecs = 2595000000007L;
immutable days = getUnitsFromHNSecs!"days"(hnsecs);
assert(days == 3);
assert(hnsecs == 2595000000007L);
--------------------
  +/
long getUnitsFromHNSecs(string units)(long hnsecs) @safe pure nothrow @nogc
    if(units == "weeks" ||
       units == "days" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds" ||
       units == "msecs" ||
       units == "usecs" ||
       units == "hnsecs")
{
    return convert!("hnsecs", units)(hnsecs);
}

//Verify Examples.
unittest
{
    auto hnsecs = 2595000000007L;
    immutable days = getUnitsFromHNSecs!"days"(hnsecs);
    assert(days == 3);
    assert(hnsecs == 2595000000007L);
}


/+
    This function is used to split out the units without getting the units but
    just the remaining hnsecs.

    See_Also:
        $(LREF splitUnitsFromHNSecs)

    Params:
        units  = The units to split out.
        hnsecs = The current total hnsecs.

    Returns:
        The remaining hnsecs.

    Examples:
--------------------
auto hnsecs = 2595000000007L;
auto returned = removeUnitsFromHNSecs!"days"(hnsecs);
assert(returned == 3000000007);
assert(hnsecs == 2595000000007L);
--------------------
  +/
long removeUnitsFromHNSecs(string units)(long hnsecs) @safe pure nothrow @nogc
    if(units == "weeks" ||
       units == "days" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds" ||
       units == "msecs" ||
       units == "usecs" ||
       units == "hnsecs")
{
    immutable value = convert!("hnsecs", units)(hnsecs);

    return hnsecs - convert!(units, "hnsecs")(value);
}

//Verify Examples.
unittest
{
    auto hnsecs = 2595000000007L;
    auto returned = removeUnitsFromHNSecs!"days"(hnsecs);
    assert(returned == 3000000007);
    assert(hnsecs == 2595000000007L);
}


/+
    Whether all of the given strings are among the accepted strings.
  +/
bool allAreAcceptedUnits(acceptedUnits...)(string[] units...)
{
    foreach(unit; units)
    {
        bool found = false;
        foreach(acceptedUnit; acceptedUnits)
        {
            if(unit == acceptedUnit)
            {
                found = true;
                break;
            }
        }
        if(!found)
            return false;
    }
    return true;
}

unittest
{
    assert(allAreAcceptedUnits!("hours", "seconds")("seconds", "hours"));
    assert(!allAreAcceptedUnits!("hours", "seconds")("minutes", "hours"));
    assert(!allAreAcceptedUnits!("hours", "seconds")("seconds", "minutes"));
    assert(allAreAcceptedUnits!("days", "hours", "minutes", "seconds", "msecs")("minutes"));
    assert(!allAreAcceptedUnits!("days", "hours", "minutes", "seconds", "msecs")("usecs"));
    assert(!allAreAcceptedUnits!("days", "hours", "minutes", "seconds", "msecs")("secs"));
}


/+
    Whether the given time unit strings are arranged in order from largest to
    smallest.
  +/
bool unitsAreInDescendingOrder(string[] units...)
{
    if(units.length <= 1)
        return true;

    immutable string[] timeStrings = ["nsecs", "hnsecs", "usecs", "msecs", "seconds",
                                      "minutes", "hours", "days", "weeks", "months", "years"];
    size_t currIndex = 42;
    foreach(i, timeStr; timeStrings)
    {
        if(units[0] == timeStr)
        {
            currIndex = i;
            break;
        }
    }
    assert(currIndex != 42);

    foreach(unit; units[1 .. $])
    {
        size_t nextIndex = 42;
        foreach(i, timeStr; timeStrings)
        {
            if(unit == timeStr)
            {
                nextIndex = i;
                break;
            }
        }
        assert(nextIndex != 42);

        if(currIndex <= nextIndex)
            return false;
        currIndex = nextIndex;
    }
    return true;
}

unittest
{
    assert(unitsAreInDescendingOrder("years", "months", "weeks", "days", "hours", "minutes",
                                     "seconds", "msecs", "usecs", "hnsecs", "nsecs"));
    assert(unitsAreInDescendingOrder("weeks", "hours", "msecs"));
    assert(unitsAreInDescendingOrder("days", "hours", "minutes"));
    assert(unitsAreInDescendingOrder("hnsecs"));
    assert(!unitsAreInDescendingOrder("days", "hours", "hours"));
    assert(!unitsAreInDescendingOrder("days", "hours", "days"));
}


/+
    The time units which are one step larger than the given units.

    Examples:
--------------------
assert(nextLargerTimeUnits!"minutes" == "hours");
assert(nextLargerTimeUnits!"hnsecs" == "usecs");
--------------------
  +/
template nextLargerTimeUnits(string units)
    if(units == "days" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds" ||
       units == "msecs" ||
       units == "usecs" ||
       units == "hnsecs" ||
       units == "nsecs")
{
    static if(units == "days")
        enum nextLargerTimeUnits = "weeks";
    else static if(units == "hours")
        enum nextLargerTimeUnits = "days";
    else static if(units == "minutes")
        enum nextLargerTimeUnits = "hours";
    else static if(units == "seconds")
        enum nextLargerTimeUnits = "minutes";
    else static if(units == "msecs")
        enum nextLargerTimeUnits = "seconds";
    else static if(units == "usecs")
        enum nextLargerTimeUnits = "msecs";
    else static if(units == "hnsecs")
        enum nextLargerTimeUnits = "usecs";
    else static if(units == "nsecs")
        enum nextLargerTimeUnits = "hnsecs";
    else
        static assert(0, "Broken template constraint");
}

//Verify Examples.
unittest
{
    assert(nextLargerTimeUnits!"minutes" == "hours");
    assert(nextLargerTimeUnits!"hnsecs" == "usecs");
}

unittest
{
    assert(nextLargerTimeUnits!"nsecs" == "hnsecs");
    assert(nextLargerTimeUnits!"hnsecs" == "usecs");
    assert(nextLargerTimeUnits!"usecs" == "msecs");
    assert(nextLargerTimeUnits!"msecs" == "seconds");
    assert(nextLargerTimeUnits!"seconds" == "minutes");
    assert(nextLargerTimeUnits!"minutes" == "hours");
    assert(nextLargerTimeUnits!"hours" == "days");
    assert(nextLargerTimeUnits!"days" == "weeks");

    static assert(!__traits(compiles, nextLargerTimeUnits!"weeks"));
    static assert(!__traits(compiles, nextLargerTimeUnits!"months"));
    static assert(!__traits(compiles, nextLargerTimeUnits!"years"));
}


/+
    Local version of abs, since std.math.abs is in Phobos, not druntime.
  +/
long _abs(long val) @safe pure nothrow @nogc
{
    return val >= 0 ? val : -val;
}


/++
    Unfortunately, $(D snprintf) is not pure, so here's a way to convert
    a number to a string which is.
  +/
string numToString(long value) @safe pure nothrow
{
    try
    {
        immutable negative = value < 0;
        char[25] str;
        size_t i = str.length;

        if(negative)
            value = -value;

        while(1)
        {
            char digit = cast(char)('0' + value % 10);
            value /= 10;

            str[--i] = digit;
            assert(i > 0);

            if(value == 0)
                break;
        }

        if(negative)
            return "-" ~ str[i .. $].idup;
        else
            return str[i .. $].idup;
    }
    catch(Exception e)
        assert(0, "Something threw when nothing can throw.");
}

version(unittest) const(char)* numToStringz(long value) @safe pure nothrow
{
    return (numToString(value) ~ "\0").ptr;
}


/+ A copy of std.typecons.TypeTuple. +/
private template _TypeTuple(TList...)
{
    alias TList _TypeTuple;
}


/+ An adjusted copy of std.exception.assertThrown. +/
version(unittest) void _assertThrown(T : Throwable = Exception, E)
                                    (lazy E expression,
                                     string msg = null,
                                     string file = __FILE__,
                                     size_t line = __LINE__)
{
    bool thrown = false;

    try
        expression();
    catch(T t)
        thrown = true;

    if(!thrown)
    {
        immutable tail = msg.length == 0 ? "." : ": " ~ msg;

        throw new AssertError("assertThrown() failed: No " ~ T.stringof ~ " was thrown" ~ tail, file, line);
    }
}

unittest
{

    void throwEx(Throwable t)
    {
        throw t;
    }

    void nothrowEx()
    {}

    try
        _assertThrown!Exception(throwEx(new Exception("It's an Exception")));
    catch(AssertError)
        assert(0);

    try
        _assertThrown!Exception(throwEx(new Exception("It's an Exception")), "It's a message");
    catch(AssertError)
        assert(0);

    try
        _assertThrown!AssertError(throwEx(new AssertError("It's an AssertError", __FILE__, __LINE__)));
    catch(AssertError)
        assert(0);

    try
        _assertThrown!AssertError(throwEx(new AssertError("It's an AssertError", __FILE__, __LINE__)), "It's a message");
    catch(AssertError)
        assert(0);


    {
        bool thrown = false;
        try
            _assertThrown!Exception(nothrowEx());
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
            _assertThrown!Exception(nothrowEx(), "It's a message");
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
            _assertThrown!AssertError(nothrowEx());
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
            _assertThrown!AssertError(nothrowEx(), "It's a message");
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }
}


version(unittest) void assertApprox(D, E)(D actual,
                                          E lower,
                                          E upper,
                                          string msg = "unittest failure",
                                          size_t line = __LINE__)
    if(is(D : const Duration) && is(E : const Duration))
{
    if(actual < lower)
        throw new AssertError(msg ~ ": lower: " ~ actual.toString(), __FILE__, line);
    if(actual > upper)
        throw new AssertError(msg ~ ": upper: " ~ actual.toString(), __FILE__, line);
}

version(unittest) void assertApprox(D, E)(D actual,
                                          E lower,
                                          E upper,
                                          string msg = "unittest failure",
                                          size_t line = __LINE__)
    if(is(D : const TickDuration) && is(E : const TickDuration))
{
    if(actual.length < lower.length || actual.length > upper.length)
    {
        throw new AssertError(msg ~ ": [" ~ numToString(lower.length) ~ "] [" ~
                              numToString(actual.length) ~ "] [" ~
                              numToString(upper.length) ~ "]", __FILE__, line);
    }
}

version(unittest) void assertApprox(MonoTime actual,
                                    MonoTime lower,
                                    MonoTime upper,
                                    string msg = "unittest failure",
                                    size_t line = __LINE__)
{
    assertApprox(actual._ticks, lower._ticks, upper._ticks, msg, line);
}

version(unittest) void assertApprox(long actual,
                                    long lower,
                                    long upper,
                                    string msg = "unittest failure",
                                    size_t line = __LINE__)
{
    if(actual < lower)
        throw new AssertError(msg ~ ": lower: " ~ numToString(actual), __FILE__, line);
    if(actual > upper)
        throw new AssertError(msg ~ ": upper: " ~ numToString(actual), __FILE__, line);
}
