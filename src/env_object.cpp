#include "natalie.hpp"
#include "natalie/env.hpp"
#include "tm/vector.hpp"

extern char **environ;

namespace Natalie {

Value EnvObject::inspect(Env *env) {
    return this->to_hash(env)->as_hash()->inspect(env);
}

Value EnvObject::to_hash(Env *env) {
    HashObject *hash = new HashObject {};
    size_t i = 1;
    char *pair = *environ;
    if (!pair) return hash;
    for (; pair; i++) {
        char *eq = strchr(pair, '=');
        assert(eq);
        size_t index = eq - pair;
        StringObject *name = new StringObject { pair };
        name->truncate(index);
        hash->put(env, name, new StringObject { getenv(name->c_str()) });
        pair = *(environ + i);
    }
    return hash;
}

Value EnvObject::size(Env *env) const {
    size_t idx = 0;
    char *pair = *environ;
    if (!pair) return Value::integer(0); // paranoia, unsure if necessary
    for (; pair; idx++) {
        pair = *(environ + idx);
    }
    return IntegerObject::from_size_t(env, idx);
}

Value EnvObject::delete_key(Env *env, Value name) {
    name->assert_type(env, Object::Type::String, "String");
    auto namestr = name->as_string()->c_str();
    char *value = getenv(namestr);
    if (value) {
        ::unsetenv(namestr);
        return new StringObject { value };
    } else {
        return NilObject::the();
    }
}

Value EnvObject::assoc(Env *env, Value name) {
    StringObject *namestr;
    namestr = name->is_string() ? name->as_string() : name->to_str(env);
    char *value = getenv(namestr->c_str());
    if (value) {
        StringObject *valuestr = new StringObject { value };
        return new ArrayObject { { namestr, valuestr } };
    } else {
        return NilObject::the();
    }
}
Value EnvObject::ref(Env *env, Value name) {
    StringObject *namestr;
    namestr = name->is_string() ? name->as_string() : name->to_str(env);
    char *value = getenv(namestr->c_str());
    if (value) {
        return new StringObject { value };
    } else {
        return NilObject::the();
    }
}

Value EnvObject::fetch(Env *env, Value name) {
    name->assert_type(env, Object::Type::String, "String");
    char *value = getenv(name->as_string()->c_str());
    if (value) {
        return new StringObject { value };
    } else {
        env->raise("KeyError", "key not found: {}", name->as_string()->string());
    }
}

Value EnvObject::refeq(Env *env, Value name, Value value) {
    StringObject *namestr, *valuestr;
    namestr = name->is_string() ? name->as_string() : name->to_str(env);
    if (value->is_nil()) {
        unsetenv(namestr->c_str());
    } else {
        valuestr = value->is_string() ? value->as_string() : value->to_str(env);
        auto result = setenv(namestr->c_str(), valuestr->c_str(), 1);
        if (result == -1)
            env->raise_errno();
    }
    return value;
}

bool EnvObject::has_key(Env *env, Value name) {
    StringObject *namestr;
    namestr = name->is_string() ? name->as_string() : name->to_str(env);
    char *value = getenv(namestr->c_str());
    return (value != NULL);
}

Value EnvObject::to_s() const {
    return new StringObject { "ENV" };
}

Value EnvObject::rehash() const {
    return NilObject::the();
}
}
