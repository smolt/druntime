// A temporary place to drop in some hacks and other magic while porting iOS
module ldc.xyzzy;

shared uint skippedTests;

void skipTest()()
{
    pragma(msg, "Note: skipping tests with compile error");
    ++skippedTests;
}
