#pragma once

#include "tm/macros.hpp"
#include "tm/vector.hpp"
#include <stddef.h>

namespace Natalie {

class ArrayObject;
class Env;
class Value;

class Args {
public:
    Args() { }

    Args(size_t size, const Value *data, bool has_keyword_hash = false)
        : m_size { size }
        , m_data { data }
        , m_has_keyword_hash { has_keyword_hash } { }

    Args(TM::Vector<Value> vec)
        : m_size { vec.size() }
        , m_data { vec.data() } { }

    Args(ArrayObject *array, bool has_keyword_hash = false);

    Args(std::initializer_list<Value> args, bool has_keyword_hash = false)
        : m_size { args.size() }
        , m_data { std::data(args) }
        , m_has_keyword_hash { has_keyword_hash } { }

    Args(const Args &other);

    Args(Args &&other)
        : m_size { other.m_size }
        , m_data { other.m_data } {
        other.m_size = 0;
        other.m_data = nullptr;
    }

    Args &operator=(const Args &other);

    static Args shift(Args &args);

    Value operator[](size_t index) const;

    Value at(size_t index) const;
    Value at(size_t index, Value default_value) const;

    ArrayObject *to_array() const;
    ArrayObject *to_array_for_block(Env *env, ssize_t min_count, ssize_t max_count) const;

    void ensure_argc_is(Env *env, size_t expected) const;
    void ensure_argc_between(Env *env, size_t expected_low, size_t expected_high) const;
    void ensure_argc_at_least(Env *env, size_t expected) const;

    size_t size() const { return m_size; }

    const Value *data() const { return m_data; }

    bool has_keyword_hash() const { return m_has_keyword_hash; }

private:
    // Args cannot be heap-allocated, because the GC is not aware of it.
    void *operator new(size_t size) { TM_UNREACHABLE(); };

    void array_pointer_accessor_so_clang_does_not_complain() const {
        (void)m_array_pointer_so_the_gc_does_not_collect_it;
    }

    size_t m_size { 0 };
    const Value *m_data { nullptr };
    bool m_has_keyword_hash { false };

    // NOTE: We need to hold onto this pointer so the GC does not collect the
    // ArrayObject holding our data. We don't actually use it, but just it
    // being here means this pointer stays on the stack for as long as this
    // Args object is in scope, which means the GC continues to see the
    // ArrayObject* as reachable. :-)
    const ArrayObject *m_array_pointer_so_the_gc_does_not_collect_it { nullptr };
};
};