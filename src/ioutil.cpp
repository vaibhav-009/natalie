#include "natalie/ioutil.hpp"
#include "natalie.hpp"

namespace Natalie {

namespace ioutil {
    // If the `path` is not a string, but has #to_path, then
    // execute #to_path.  Otherwise if it has #to_str, then
    // execute #to_str.  Make sure the path or to_path result is a String
    // before continuing.
    // This is common to many functions in FileObject and DirObject
    StringObject *convert_using_to_path(Env *env, Value path) {
        if (!path->is_string() && path->respond_to(env, "to_path"_s))
            path = path->send(env, "to_path"_s);
        if (!path->is_string() && path->respond_to(env, "to_str"_s))
            path = path->send(env, "to_str"_s);
        path->assert_type(env, Object::Type::String, "String");
        return path->as_string();
    }

    // accepts io or io-like object for fstat
    // accepts path or string like object for stat
    int object_stat(Env *env, Value io, struct stat *sb) {
        if (io->is_io() || io->respond_to(env, "to_io"_s)) {
            auto file_desc = io->to_io(env)->fileno();
            return ::fstat(file_desc, sb);
        }

        io = convert_using_to_path(env, io);
        return ::stat(io->as_string()->c_str(), sb);
    }

    namespace {
        void parse_flags_obj(Env *env, flags_struct *self, Value flags_obj) {
            if (!flags_obj || flags_obj->is_nil())
                return;

            self->has_mode = true;

            if (!flags_obj->is_integer() && !flags_obj->is_string()) {
                if (flags_obj->respond_to(env, "to_str"_s)) {
                    flags_obj = flags_obj->to_str(env);
                } else if (flags_obj->respond_to(env, "to_int"_s)) {
                    flags_obj = flags_obj->to_int(env);
                }
            }

            switch (flags_obj->type()) {
            case Object::Type::Integer:
                self->flags = flags_obj->as_integer()->to_nat_int_t();
                break;
            case Object::Type::String: {
                auto colon = new StringObject { ":" };
                auto flagsplit = flags_obj->as_string()->split(env, colon, nullptr)->as_array();
                auto flags_str = flagsplit->fetch(env, IntegerObject::create(static_cast<nat_int_t>(0)), new StringObject { "" }, nullptr)->as_string()->string();
                auto extenc = flagsplit->ref(env, IntegerObject::create(static_cast<nat_int_t>(1)), nullptr);
                auto intenc = flagsplit->ref(env, IntegerObject::create(static_cast<nat_int_t>(2)), nullptr);
                if (!extenc->is_nil()) self->external_encoding = EncodingObject::find_encoding(env, extenc);
                if (!intenc->is_nil()) self->internal_encoding = EncodingObject::find_encoding(env, intenc);

                if (flags_str.length() < 1 || flags_str.length() > 3)
                    env->raise("ArgumentError", "invalid access mode {}", flags_str);

                // rb+ => 'r', 'b', '+'
                auto main_mode = flags_str.at(0);
                auto read_write_mode = flags_str.length() > 1 ? flags_str.at(1) : 0;
                auto binary_text_mode = flags_str.length() > 2 ? flags_str.at(2) : 0;

                // rb+ => r+b
                if (read_write_mode == 'b' || read_write_mode == 't')
                    std::swap(read_write_mode, binary_text_mode);

                if (binary_text_mode && binary_text_mode != 'b' && binary_text_mode != 't')
                    env->raise("ArgumentError", "invalid access mode {}", flags_str);

                if (binary_text_mode == 'b') {
                    self->read_mode = flags_struct::read_mode::binary;
                } else if (binary_text_mode == 't') {
                    self->read_mode = flags_struct::read_mode::text;
                }

                if (main_mode == 'r' && !read_write_mode)
                    self->flags = O_RDONLY;
                else if (main_mode == 'r' && read_write_mode == '+')
                    self->flags = O_RDWR;
                else if (main_mode == 'w' && !read_write_mode)
                    self->flags = O_WRONLY | O_CREAT | O_TRUNC;
                else if (main_mode == 'w' && read_write_mode == '+')
                    self->flags = O_RDWR | O_CREAT | O_TRUNC;
                else if (main_mode == 'a' && !read_write_mode)
                    self->flags = O_WRONLY | O_CREAT | O_APPEND;
                else if (main_mode == 'a' && read_write_mode == '+')
                    self->flags = O_RDWR | O_CREAT | O_APPEND;
                else
                    env->raise("ArgumentError", "invalid access mode {}", flags_str);
                break;
            }
            default:
                env->raise("TypeError", "no implicit conversion of {} into String", flags_obj->klass()->inspect_str());
            }
        }

        void parse_mode(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto mode = kwargs->remove(env, "mode"_s);
            if (!mode || mode->is_nil()) return;
            if (self->has_mode)
                env->raise("ArgumentError", "mode specified twice");
            parse_flags_obj(env, self, mode);
        }

        void parse_flags(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto flags = kwargs->remove(env, "flags"_s);
            if (!flags || flags->is_nil()) return;
            self->flags |= static_cast<int>(flags->to_int(env)->to_nat_int_t());
        }

        void parse_encoding(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto encoding = kwargs->remove(env, "encoding"_s);
            if (!encoding || encoding->is_nil()) return;
            if (self->external_encoding) {
                env->raise("ArgumentError", "encoding specified twice");
            } else if (kwargs->has_key(env, "external_encoding"_s)) {
                env->warn("Ignoring encoding parameter '{}', external_encoding is used", encoding);
            } else if (kwargs->has_key(env, "internal_encoding"_s)) {
                env->warn("Ignoring encoding parameter '{}', internal_encoding is used", encoding);
            } else if (encoding->is_encoding()) {
                self->external_encoding = encoding->as_encoding();
            } else {
                encoding = encoding->to_str(env);
                if (encoding->as_string()->include(":")) {
                    auto colon = new StringObject { ":" };
                    auto encsplit = encoding->to_str(env)->split(env, colon, nullptr)->as_array();
                    encoding = encsplit->ref(env, IntegerObject::create(static_cast<nat_int_t>(0)), nullptr);
                    auto internal_encoding = encsplit->ref(env, IntegerObject::create(static_cast<nat_int_t>(1)), nullptr);
                    self->internal_encoding = EncodingObject::find_encoding(env, internal_encoding);
                }
                self->external_encoding = EncodingObject::find_encoding(env, encoding);
            }
        }

        void parse_external_encoding(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto external_encoding = kwargs->remove(env, "external_encoding"_s);
            if (!external_encoding || external_encoding->is_nil()) return;
            if (self->external_encoding)
                env->raise("ArgumentError", "encoding specified twice");
            if (external_encoding->is_encoding()) {
                self->external_encoding = external_encoding->as_encoding();
            } else {
                self->external_encoding = EncodingObject::find_encoding(env, external_encoding->to_str(env));
            }
        }

        void parse_internal_encoding(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto internal_encoding = kwargs->remove(env, "internal_encoding"_s);
            if (!internal_encoding || internal_encoding->is_nil()) return;
            if (self->internal_encoding)
                env->raise("ArgumentError", "encoding specified twice");
            if (internal_encoding->is_encoding()) {
                self->internal_encoding = internal_encoding->as_encoding();
            } else {
                internal_encoding = internal_encoding->to_str(env);
                if (internal_encoding->as_string()->string() != "-") {
                    self->internal_encoding = EncodingObject::find_encoding(env, internal_encoding);
                    if (self->external_encoding == self->internal_encoding)
                        self->internal_encoding = nullptr;
                }
            }
        }

        void parse_textmode(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto textmode = kwargs->remove(env, "textmode"_s);
            if (!textmode || textmode->is_nil()) return;
            if (self->read_mode == flags_struct::read_mode::binary) {
                env->raise("ArgumentError", "both textmode and binmode specified");
            } else if (self->read_mode == flags_struct::read_mode::text) {
                env->raise("ArgumentError", "textmode specified twice");
            }
            if (textmode->is_truthy())
                self->read_mode = flags_struct::read_mode::text;
        }

        void parse_binmode(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto binmode = kwargs->remove(env, "binmode"_s);
            if (!binmode || binmode->is_nil()) return;
            if (self->read_mode == flags_struct::read_mode::binary) {
                env->raise("ArgumentError", "binmode specified twice");
            } else if (self->read_mode == flags_struct::read_mode::text) {
                env->raise("ArgumentError", "both textmode and binmode specified");
            }
            if (binmode->is_truthy())
                self->read_mode = flags_struct::read_mode::binary;
        }

        void parse_autoclose(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto autoclose = kwargs->remove(env, "autoclose"_s);
            if (!autoclose) return;
            self->autoclose = autoclose->is_truthy();
        }

        void parse_path(Env *env, flags_struct *self, HashObject *kwargs) {
            if (!kwargs) return;
            auto path = kwargs->remove(env, "path"_s);
            if (!path) return;
            self->path = convert_using_to_path(env, path);
        }
    };

    flags_struct::flags_struct(Env *env, Value flags_obj, HashObject *kwargs) {
        parse_flags_obj(env, this, flags_obj);
        parse_mode(env, this, kwargs);
        parse_flags(env, this, kwargs);
        flags |= O_CLOEXEC;
        parse_encoding(env, this, kwargs);
        parse_external_encoding(env, this, kwargs);
        parse_internal_encoding(env, this, kwargs);
        parse_textmode(env, this, kwargs);
        parse_binmode(env, this, kwargs);
        parse_autoclose(env, this, kwargs);
        parse_path(env, this, kwargs);
        if (!external_encoding) {
            if (read_mode == read_mode::binary) {
                external_encoding = EncodingObject::get(Encoding::ASCII_8BIT);
            } else if (read_mode == read_mode::text) {
                external_encoding = EncodingObject::get(Encoding::UTF_8);
            }
        }
        env->ensure_no_extra_keywords(kwargs);
    }

    mode_t perm_to_mode(Env *env, Value perm) {
        if (perm && !perm->is_nil())
            return IntegerObject::convert_to_int(env, perm);
        else
            return S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH; // 0660 default
    }
}

}
