/**
 * Implementation of associative arrays.
 *
 * Copyright: Copyright Digital Mars 2000 - 2010.
 * License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Walter Bright, Sean Kelly
 */

/*          Copyright Digital Mars 2000 - 2010.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module rt.aaA;

private
{
    import core.stdc.stdarg;
    import core.stdc.string;
    import core.stdc.stdio;
    import core.memory;
    import rt.lifetime : _d_newarrayU;

    // Convenience function to make sure the NO_INTERIOR gets set on the
    // bucket array.
    Entry*[] newBuckets(in size_t len) @trusted pure nothrow
    {
        auto ptr = cast(Entry**) GC.calloc(
            len * (Entry*).sizeof, GC.BlkAttr.NO_INTERIOR);
        return ptr[0..len];
    }
}

// Auto-rehash and pre-allocate - Dave Fladebo

static immutable size_t[] prime_list = [
              31UL,
              97UL,            389UL,
           1_543UL,          6_151UL,
          24_593UL,         98_317UL,
          393_241UL,      1_572_869UL,
        6_291_469UL,     25_165_843UL,
      100_663_319UL,    402_653_189UL,
    1_610_612_741UL,  4_294_967_291UL,
//  8_589_934_513UL, 17_179_869_143UL
];

/* This is the type of the return value for dynamic arrays.
 * It should be a type that is returned in registers.
 * Although DMD will return types of Array in registers,
 * gcc will not, so we instead use a 'long'.
 */
alias void[] ArrayRet_t;

struct Array
{
    size_t length;
    void* ptr;
}

struct Entry
{
    Entry *next;
    size_t hash;
    /* key   */
    /* value */
}

struct Impl
{
    Entry*[] buckets;
    size_t nodes;       // total number of entries
    size_t firstUsedBucket; // starting index for first used bucket.
    TypeInfo _keyti;
    Entry*[4] binit;    // initial value of buckets[]

    @property const(TypeInfo) keyti() const @safe pure nothrow @nogc
    { return _keyti; }

    // helper function to determine first used bucket, and update implementation's cache for it
    // NOTE: will not work with immutable AA in ROM, but that doesn't exist yet.
    size_t firstUsedBucketCache() @safe pure nothrow @nogc
    in
    {
        assert(firstUsedBucket <= buckets.length);
        foreach(i; 0 .. firstUsedBucket)
            assert(buckets[i] is null);
    }
    body
    {
        size_t i;
        for(i = firstUsedBucket; i < buckets.length; ++i)
            if(buckets[i] !is null)
                break;
        return firstUsedBucket = i;
    }
}

/* This is the type actually seen by the programmer, although
 * it is completely opaque.
 */
alias void* AA;

/**********************************
 * Align to next pointer boundary, so that
 * GC won't be faced with misaligned pointers
 * in value.
 */
size_t aligntsize(in size_t tsize) @safe pure nothrow @nogc
{
    version (D_LP64) {
        // align to 16 bytes on 64-bit
        return (tsize + 15) & ~(15);
    }
    else {
        return (tsize + size_t.sizeof - 1) & ~(size_t.sizeof - 1);
    }
}

extern (C):

/****************************************************
 * Determine number of entries in associative array.
 */
size_t _aaLen(in AA aa) pure nothrow @nogc
in
{
    //printf("_aaLen()+\n");
    //_aaInv(aa);
}
out (result)
{
    size_t len = 0;

    auto impl = cast(const(Impl*)) aa;
    if (impl)
    {
        foreach (const(Entry)* e; impl.buckets)
        {
            while (e)
            {
                len++;
                e = e.next;
            }
        }
    }
    assert(len == result);

    //printf("_aaLen()-\n");
}
body
{
    auto impl = cast(const(Impl*)) aa;
    return impl ? impl.nodes : 0;
}


/*************************************************
 * Get pointer to value in associative array indexed by key.
 * Add entry for key if it is not already there.
 */
void* _aaGetX(AA* aa, const TypeInfo keyti, in size_t valuesize, in void* pkey)
in
{
    assert(aa);
}
body
{
    if (*aa is null)
    {
        auto impl = new Impl();
        impl.buckets = impl.binit[];
        impl.firstUsedBucket = impl.buckets.length;
        impl._keyti = cast() keyti;
        *aa = impl;
    }
    return _aaGetImpl(aa, keyti, valuesize, pkey);
}

void* _aaGetY(AA* aa, const TypeInfo_AssociativeArray ti, in size_t valuesize, in void* pkey)
{
    if (*aa is null)
    {
        auto impl = new Impl();
        impl.buckets = impl.binit[];
        impl.firstUsedBucket = impl.buckets.length;
        impl._keyti = cast() ti.key;
        *aa = impl;
    }
    return _aaGetImpl(aa, ti.key, valuesize, pkey);
}

void* _aaGetImpl(AA* aa, const TypeInfo keyti, in size_t valuesize, in void* pkey)
out (result)
{
    assert(result);
    auto impl = cast(Impl*) *aa;
    assert(impl !is null);
    assert(impl.buckets.length);
    //assert(_aaInAh(*aa.a, key));
}
body
{
    //printf("keyti = %p\n", keyti);
    //printf("aa = %p\n", aa);

    auto impl = cast(Impl*) *aa;
    if (impl is null)
    {
        impl = new Impl();
        impl.buckets = impl.binit[];
        impl.firstUsedBucket = impl.buckets.length;
        impl._keyti = cast() keyti;
        *aa = impl;
    }
    //printf("aa = %p\n", aa);
    //printf("aa.a = %p\n", aa.a);

    immutable keytitsize = keyti.tsize;

    immutable key_hash = keyti.getHash(pkey);
    immutable i = key_hash % impl.buckets.length;
    //printf("hash = %d\n", key_hash);

    Entry** pe = &impl.buckets[i];
    Entry* e;
    while ((e = *pe) !is null)
    {
        if (key_hash == e.hash)
        {
            if (keyti.equals(pkey, e + 1))
                goto Lret;
        }
        pe = &e.next;
    }

    {
        // Not found, create new elem
        //printf("create new one\n");
        size_t size = Entry.sizeof + aligntsize(keytitsize) + valuesize;
        e = cast(Entry *) GC.malloc(size, 0); // TODO: needs typeid(Entry+)
        e.next = null;
        e.hash = key_hash;
        ubyte* ptail = cast(ubyte*)(e + 1);
        memcpy(ptail, pkey, keytitsize);
        memset(ptail + aligntsize(keytitsize), 0, valuesize); // zero value
        *pe = e;

        auto nodes = ++impl.nodes;
        //printf("length = %d, nodes = %d\n", aa.a.buckets.length, nodes);

        // update cache if necessary
        if (i < impl.firstUsedBucket)
                impl.firstUsedBucket = i;
        if (nodes > impl.buckets.length * 4)
        {
            //printf("rehash\n");
            _aaRehash(aa,keyti);
        }
    }

Lret:
    return cast(void*)(e + 1) + aligntsize(keytitsize);
}


/// Same as above but with a function pointer to aaLiteral!(Key, Value) for creating a typed AA instance.
void* _aaGetZ(AA* aa, const TypeInfo keyti, in size_t valuesize, in void* pkey,
              void *function(void[], void[]) @trusted pure aaLiteral)
{
    return _aaGetX(aa, keyti, valuesize, pkey);
}

// bug 13748
pure nothrow unittest
{
    int[int] aa;
    // make all values go into the last bucket (int hash is simply the int)
    foreach(i; 0..16)
    {
        aa[3 + i * 4] = 1;
        assert(aa.keys.length == i+1);
    }

    // now force a rehash, but with a different value
    aa[0] = 1;
    assert(aa.keys.length == 17);
}


/*************************************************
 * Get pointer to value in associative array indexed by key.
 * Returns null if it is not already there.
 */
inout(void)* _aaGetRvalueX(inout AA aa, in TypeInfo keyti, in size_t valuesize, in void* pkey)
{
    return _aaInX(aa, keyti, pkey);
}


/*************************************************
 * Determine if key is in aa.
 * Returns:
 *      null    not in aa
 *      !=null  in aa, return pointer to value
 */
inout(void)* _aaInX(inout AA aa, in TypeInfo keyti, in void* pkey)
in
{
}
out (result)
{
    //assert(result == 0 || result == 1);
}
body
{
    auto impl = cast(inout(Impl*)) aa;
    if (impl is null)
        return null;

    //printf("_aaIn(), .length = %d, .ptr = %x\n", aa.a.length, cast(uint)aa.a.ptr);
    if (immutable len = impl.buckets.length)
    {
        immutable key_hash = keyti.getHash(pkey);
        immutable i = key_hash % len;
        //printf("hash = %d\n", key_hash);

        inout(Entry)* e = impl.buckets[i];
        while (e !is null)
        {
            if (key_hash == e.hash)
            {
                if (keyti.equals(pkey, e + 1))
                    return cast(inout void*)(e + 1) + aligntsize(keyti.tsize);
            }
            e = e.next;
        }
    }

    // Not found
    return null;
}

/*************************************************
 * Delete key entry in aa[].
 * If key is not in aa[], do nothing.
 */
bool _aaDelX(AA aa, in TypeInfo keyti, in void* pkey)
{
    auto impl = cast(Impl*) aa;
    if (!impl || !impl.buckets.length)
        return false;
    auto key_hash = keyti.getHash(pkey);
    //printf("hash = %d\n", key_hash);
    immutable size_t i = key_hash % impl.buckets.length;
    auto pe = &impl.buckets[i];
    for (Entry *e = void; (e = *pe) !is null; pe = &e.next)
    {
        if (key_hash != e.hash || !keyti.equals(pkey, e + 1))
            continue;
        *pe = e.next;
        if (!(--impl.nodes))
            // reset cache, we know there are no nodes in the aa.
            impl.firstUsedBucket = impl.buckets.length;
        // ee could be freed here, but user code may 
        // hold pointers to it
        return true;
    }
    return false;
}


/********************************************
 * Produce array of values from aa.
 */
inout(ArrayRet_t) _aaValues(inout AA aa, in size_t keysize, in size_t valuesize, const TypeInfo tiValueArray) pure nothrow
{
    size_t resi;
    Array a;

    auto alignsize = aligntsize(keysize);

    auto impl = cast(inout(Impl*)) aa;
    if (impl !is null)
    {
        a.length = _aaLen(aa);
        a.ptr = cast(byte*) _d_newarrayU(tiValueArray, a.length).ptr;
        resi = 0;
        foreach (inout(Entry)* e; impl.buckets[impl.firstUsedBucket..$])
        {
            while (e)
            {
                memcpy(a.ptr + resi * valuesize,
                       cast(byte*)e + Entry.sizeof + alignsize,
                       valuesize);
                // TODO: no postblit here?
                resi++;
                e = e.next;
            }
        }
        assert(resi == a.length);
    }
    return *cast(inout ArrayRet_t*)(&a);
}


/********************************************
 * Rehash an array.
 */
void* _aaRehash(AA* paa, in TypeInfo keyti) pure nothrow
in
{
    //_aaInvAh(paa);
}
out (result)
{
    //_aaInvAh(result);
}
body
{
    //printf("Rehash\n");
    auto impl = cast(Impl*) *paa;
    if (impl !is null)
    {
        auto len = _aaLen(*paa);
        if (len)
        {
            Impl newImpl;

            size_t i;
            for (i = 0; i < prime_list.length - 1; i++)
            {
                if (len <= prime_list[i])
                    break;
            }
            len = prime_list[i];
            newImpl.buckets = newBuckets(len);
            newImpl.firstUsedBucket = newImpl.buckets.length;

            foreach (e; impl.buckets[impl.firstUsedBucket..$])
            {
                while (e)
                {
                    auto enext = e.next;
                    const j = e.hash % len;
                    e.next = newImpl.buckets[j];
                    newImpl.buckets[j] = e;
                    e = enext;
                    if(j < newImpl.firstUsedBucket)
                        newImpl.firstUsedBucket = j;
                }
            }
            if (impl.buckets.ptr == impl.binit.ptr)
                impl.binit[] = null;
            else
                GC.free(impl.buckets.ptr);

            newImpl.nodes = impl.nodes;
            newImpl._keyti = impl._keyti;

            *impl = newImpl;
        }
        else
        {
            if (impl.buckets.ptr != impl.binit.ptr)
                GC.free(impl.buckets.ptr);
            impl.buckets = impl.binit[];
            impl.firstUsedBucket = impl.buckets.length; // start out with the cache at the end
        }
    }
    return impl;
}

/********************************************
 * Produce array of N byte keys from aa.
 */
inout(ArrayRet_t) _aaKeys(inout AA aa, in size_t keysize, const TypeInfo tiKeyArray) pure nothrow
{
    auto len = _aaLen(aa);
    if (!len)
        return null;

    void* res = _d_newarrayU(tiKeyArray, len).ptr;

    auto impl = cast(inout(Impl*)) aa;
    size_t resi = 0;
    // note, can't use firstUsedBucketCache here, aa is inout
    foreach (inout(Entry)* e; impl.buckets[impl.firstUsedBucket..$])
    {
        while (e)
        {
            memcpy(&res[resi * keysize], cast(byte*)(e + 1), keysize);
            // TODO: no postblit here?
            resi++;
            e = e.next;
        }
    }
    assert(resi == len);

    Array a;
    a.length = len;
    a.ptr = res;
    return *cast(inout ArrayRet_t*)(&a);
}

pure nothrow unittest
{
    int[string] aa;

    aa["hello"] = 3;
    assert(aa["hello"] == 3);
    aa["hello"]++;
    assert(aa["hello"] == 4);

    assert(aa.length == 1);

    string[] keys = aa.keys;
    assert(keys.length == 1);
    assert(memcmp(keys[0].ptr, cast(char*)"hello", 5) == 0);

    int[] values = aa.values;
    assert(values.length == 1);
    assert(values[0] == 4);

    aa.rehash;
    assert(aa.length == 1);
    assert(aa["hello"] == 4);

    aa["foo"] = 1;
    aa["bar"] = 2;
    aa["batz"] = 3;

    assert(aa.keys.length == 4);
    assert(aa.values.length == 4);

    foreach(a; aa.keys)
    {
        assert(a.length != 0);
        assert(a.ptr != null);
        //printf("key: %.*s -> value: %d\n", a.length, a.ptr, aa[a]);
    }

    foreach(v; aa.values)
    {
        assert(v != 0);
        //printf("value: %d\n", v);
    }
}

unittest // Test for Issue 10381
{
    alias II = int[int];
    II aa1 = [0: 1];
    II aa2 = [0: 1];
    II aa3 = [0: 2];
    assert(aa1 == aa2); // Passes
    assert( typeid(II).equals(&aa1, &aa2));
    assert(!typeid(II).equals(&aa1, &aa3));
}


/**********************************************
 * 'apply' for associative arrays - to support foreach
 */
// dg is D, but _aaApply() is C
extern (D) alias int delegate(void *) dg_t;

int _aaApply(AA aa, in size_t keysize, dg_t dg)
{
    auto impl = cast(Impl*) aa;
    if (impl is null)
    {
        return 0;
    }

    immutable alignsize = aligntsize(keysize);
    //printf("_aaApply(aa = x%llx, keysize = %d, dg = x%llx)\n", aa.impl, keysize, dg);

    foreach (e; impl.buckets[impl.firstUsedBucketCache .. $])
    {
        while (e)
        {
            auto result = dg(cast(void *)(e + 1) + alignsize);
            if (result)
                return result;
            e = e.next;
        }
    }
    return 0;
}

// dg is D, but _aaApply2() is C
extern (D) alias int delegate(void *, void *) dg2_t;

int _aaApply2(AA aa, in size_t keysize, dg2_t dg)
{
    auto impl = cast(Impl*) aa;
    if (impl is null)
    {
        return 0;
    }

    //printf("_aaApply(aa = x%llx, keysize = %d, dg = x%llx)\n", aa.impl, keysize, dg);

    immutable alignsize = aligntsize(keysize);

    foreach (e; impl.buckets[impl.firstUsedBucketCache..$])
    {
        while (e)
        {
            auto result = dg(e + 1, cast(void *)(e + 1) + alignsize);
            if (result)
                return result;
            e = e.next;
        }
    }

    return 0;
}


/***********************************
 * Construct an associative array of type ti from
 * length pairs of key/value pairs.
 */
AA _d_assocarrayliteralTX(const TypeInfo_AssociativeArray ti, void[] keys, void[] values)
{
    const valuesize = ti.next.tsize;             // value size
    const keyti = ti.key;
    const keysize = keyti.tsize;                 // key size
    const length = keys.length;
    Impl* result;

    //printf("_d_assocarrayliteralT(keysize = %d, valuesize = %d, length = %d)\n", keysize, valuesize, length);
    //printf("tivalue = %.*s\n", typeid(ti.next).name);
    assert(length == values.length);
    if (length == 0 || valuesize == 0 || keysize == 0)
    {
    }
    else
    {
        result = new Impl();
        result._keyti = cast() keyti;

        size_t i;
        for (i = 0; i < prime_list.length - 1; i++)
        {
            if (length <= prime_list[i])
                break;
        }
        auto len = prime_list[i];
        result.buckets = newBuckets(len);
        result.firstUsedBucket = result.buckets.length;

        size_t keytsize = aligntsize(keysize);

        for (size_t j = 0; j < length; j++)
        {
            auto pkey = keys.ptr + j * keysize;
            auto pvalue = values.ptr + j * valuesize;
            Entry* e;

            auto key_hash = keyti.getHash(pkey);
            //printf("hash = %d\n", key_hash);
            i = key_hash % len;
            if (i < result.firstUsedBucket) result.firstUsedBucket = i;
            auto pe = &result.buckets[i];
            while (1)
            {
                e = *pe;
                if (!e)
                {
                    // Not found, create new elem
                    //printf("create new one\n");
                    e = cast(Entry *) GC.malloc(Entry.sizeof + keytsize + valuesize); // TODO: needs typeid(Entry+)
                    memcpy(e + 1, pkey, keysize);
                    e.next = null;
                    e.hash = key_hash;
                    *pe = e;
                    result.nodes++;
                    break;
                }
                if (key_hash == e.hash)
                {
                    if (keyti.equals(pkey, e + 1))
                        break;
                }
                pe = &e.next;
            }
            memcpy(cast(void *)(e + 1) + keytsize, pvalue, valuesize);
        }
    }
    return result;
}


const(TypeInfo_AssociativeArray) _aaUnwrapTypeInfo(const(TypeInfo) tiRaw) pure nothrow @nogc
{
    const(TypeInfo)* p = &tiRaw;
    TypeInfo_AssociativeArray ti;
    while (true)
    {
        if ((ti = cast(TypeInfo_AssociativeArray)*p) !is null)
            break;

        if (auto tiConst = cast(TypeInfo_Const)*p) {
            // The member in object_.d and object.di differ. This is to ensure
            //  the file can be compiled both independently in unittest and
            //  collectively in generating the library. Fixing object.di
            //  requires changes to std.format in Phobos, fixing object_.d
            //  makes Phobos's unittest fail, so this hack is employed here to
            //  avoid irrelevant changes.
            static if (is(typeof(&tiConst.base) == TypeInfo*))
                p = &tiConst.base;
            else
                p = &tiConst.next;
        } else
            assert(0);  // ???
    }

    return ti;
}


/***********************************
 * Compare AA contents for equality.
 * Returns:
 *      1       equal
 *      0       not equal
 */
int _aaEqual(in TypeInfo tiRaw, in AA e1, in AA e2)
{
    //printf("_aaEqual()\n");
    //printf("keyti = %.*s\n", typeid(ti.key).name);
    //printf("valueti = %.*s\n", typeid(ti.next).name);

    auto impl1 = cast(const(Impl*)) e1;
    auto impl2 = cast(const(Impl*)) e2;
    if (impl1 is impl2)
        return 1;

    size_t len = _aaLen(e1);
    if (len != _aaLen(e2))
        return 0;

    // Bug 9852: at this point, e1 and e2 have the same length, so if one is
    // null, the other must either also be null or have zero entries, so they
    // must be equal. We check this here to avoid dereferencing null later on.
    if (impl1 is null || impl2 is null)
        return 1;

    // Check for Bug 5925. ti_raw could be a TypeInfo_Const, we need to unwrap
    //   it until reaching a real TypeInfo_AssociativeArray.
    const TypeInfo_AssociativeArray ti = _aaUnwrapTypeInfo(tiRaw);

    /* Algorithm: Visit each key/value pair in e1. If that key doesn't exist
     * in e2, or if the value in e1 doesn't match the one in e2, the arrays
     * are not equal, and exit early.
     * After all pairs are checked, the arrays must be equal.
     */

    const keyti = ti.key;
    const valueti = ti.next;
    const keysize = aligntsize(keyti.tsize);

    assert(impl2 !is null);
    const len2 = impl2.buckets.length;

    int _aaKeys_x(const(Entry)* e)
    {
        do
        {
            auto pkey = cast(void*)(e + 1);
            auto pvalue = pkey + keysize;
            //printf("key = %d, value = %g\n", *cast(int*)pkey, *cast(double*)pvalue);

            // We have key/value for e1. See if they exist in e2

            auto key_hash = keyti.getHash(pkey);
            //printf("hash = %d\n", key_hash);
            const i = key_hash % len2;
            const(Entry)* f = impl2.buckets[i];
            while (1)
            {
                //printf("f is %p\n", f);
                if (f is null)
                    return 0;                   // key not found, so AA's are not equal
                if (key_hash == f.hash)
                {
                    //printf("hash equals\n");
                    if (keyti.equals(pkey, f + 1))
                    {
                        // Found key in e2. Compare values
                        //printf("key equals\n");
                        auto pvalue2 = cast(void *)(f + 1) + keysize;
                        if (valueti.equals(pvalue, pvalue2))
                        {
                            //printf("value equals\n");
                            break;
                        }
                        else
                            return 0;           // values don't match, so AA's are not equal
                    }
                }
                f = f.next;
            }

            // Look at next entry in e1
            e = e.next;
        } while (e !is null);
        return 1;                       // this subtree matches
    }

    // note, cannot use firstUsedBucketCache here, e1 is const
    foreach (e; impl1.buckets[impl1.firstUsedBucket..$])
    {
        if (e)
        {
            if (_aaKeys_x(e) == 0)
                return 0;
        }
    }

    return 1;           // equal
}


/*****************************************
 * Computes a hash value for the entire AA
 * Returns:
 *      Hash value
 */
hash_t _aaGetHash(in AA* aa, in TypeInfo tiRaw) nothrow
{
    import rt.util.hash;

    auto impl = cast(const(Impl*)) *aa;
    if (impl is null)
        return 0;

    hash_t h = 0;
    const TypeInfo_AssociativeArray ti = _aaUnwrapTypeInfo(tiRaw);
    const keyti = ti.key;
    const valueti = ti.next;
    const keysize = aligntsize(keyti.tsize);

    // note, can't use firstUsedBucketCache here, aa is const
    foreach (const(Entry)* e; impl.buckets[impl.firstUsedBucket..$])
    {
        while (e)
        {
            auto pkey = cast(void*)(e + 1);
            auto pvalue = pkey + keysize;

            // Compute a hash for the key/value pair by hashing their
            // respective hash values.
            hash_t[2] hpair;
            hpair[0] = e.hash;
            hpair[1] = valueti.getHash(pvalue);

            // Combine the hash of the key/value pair with the running hash
            // value using an associative operator (+) so that the resulting
            // hash value is independent of the actual order the pairs are
            // stored in (important to ensure equality of hash value for two
            // AA's containing identical pairs but with different hashtable
            // sizes).
            h += hashOf(hpair.ptr, hpair.length * hash_t.sizeof);

            e = e.next;
        }
    }

    return h;
}

pure nothrow unittest
{
    string[int] key1 = [1: "true", 2: "false"];
    string[int] key2 = [1: "false", 2: "true"];

    // AA lits create a larger hashtable
    int[string[int]] aa1 = [key1: 100, key2: 200];

    // Ensure consistent hash values are computed for key1
    assert((key1 in aa1) !is null);

    // Manually assigning to an empty AA creates a smaller hashtable
    int[string[int]] aa2;
    aa2[key1] = 100;
    aa2[key2] = 200;

    assert(aa1 == aa2);

    // Ensure binary-independence of equal hash keys
    string[int] key2a;
    key2a[1] = "false";
    key2a[2] = "true";

    assert(aa1[key2a] == 200);
}

// Issue 9852
pure nothrow unittest
{
    // Original test case (revised, original assert was wrong)
    int[string] a;
    a["foo"] = 0;
    a.remove("foo");
    assert(a == null);  // should not crash

    int[string] b;
    assert(b is null);
    assert(a == b);     // should not deref null
    assert(b == a);     // ditto

    int[string] c;
    c["a"] = 1;
    assert(a != c);     // comparison with empty non-null AA
    assert(c != a);
    assert(b != c);     // comparison with null AA
    assert(c != b);
}


/**
 * _aaRange implements a ForwardRange
 */
struct Range
{
    Impl* impl;
    Entry* current;
}


Range _aaRange(AA aa) pure nothrow @nogc
{
    typeof(return) res;
    auto impl = cast(Impl*) aa;
    if (impl is null)
        return res;

    res.impl = impl;
    foreach (entry; impl.buckets[impl.firstUsedBucketCache .. $] )
    {
        if (entry !is null)
        {
            res.current = entry;
            break;
        }
    }
    return res;
}


bool _aaRangeEmpty(Range r) pure nothrow @nogc
{
    return r.current is null;
}


void* _aaRangeFrontKey(Range r) pure nothrow @nogc
in
{
    assert(r.current !is null);
}
body
{
    return cast(void*)r.current + Entry.sizeof;
}


void* _aaRangeFrontValue(Range r) pure nothrow @nogc
in
{
    assert(r.current !is null);
    assert(r.impl.keyti !is null); // set on first insert
}
body
{
    return cast(void*)r.current + Entry.sizeof + aligntsize(r.impl.keyti.tsize);
}


void _aaRangePopFront(ref Range r) pure nothrow @nogc
{
    if (r.current.next !is null)
    {
        r.current = r.current.next;
    }
    else
    {
        immutable idx = r.current.hash % r.impl.buckets.length;
        r.current = null;
        foreach (entry; r.impl.buckets[idx + 1 .. $])
        {
            if (entry !is null)
            {
                r.current = entry;
                break;
            }
        }
    }
}

// Bugzilla 14104
unittest
{
    import core.stdc.stdio;
    alias K = const(ubyte)*;
    size_t[K] aa;
    immutable key = cast(K)(cast(size_t)uint.max + 1);
    aa[key] = 12;
    assert(key in aa);
}
