module Natalie
  class Compiler
    class MacroExpander
      include ComptimeValues

      class MacroError < StandardError; end
      class LoadPathMacroError < MacroError; end

      def initialize(path:, load_path:, interpret:, compiler_context:, log_load_error:)
        @path = path
        @load_path = load_path
        @interpret = interpret
        @compiler_context = compiler_context
        @inline_cpp_enabled = @compiler_context[:inline_cpp_enabled]
        @log_load_error = log_load_error
        @parsed_files = {}
      end

      attr_reader :node, :path, :load_path, :depth

      MACROS = %i[
        autoload
        eval
        include_str!
        load
        nat_ignore_require
        nat_ignore_require_relative
        require
        require_relative
      ].freeze

      def expand(call_node, depth:)
        if (macro_name = get_macro_name(call_node))
          run_macro(macro_name, call_node, current_path: call_node.file, depth: depth)
        else
          call_node
        end
      end

      private

      def get_macro_name(node)
        return get_macro_name_from_node(node) if node.is_a?(::Prism::Node)
        return false unless node.is_a?(Sexp)

        if node.sexp_type == :iter
          get_macro_name(node[1])
        else
          get_hidden_macro_name(node)
        end
      end

      def get_macro_name_from_node(node)
        if node.type == :call_node && node.receiver.nil?
          if MACROS.include?(node.name)
            node.name
          elsif @macros_enabled
            if node.name == :macro!
              node.name
            elsif @macros.key?(node.name)
              :user_macro
            end
          end
        elsif node.sexp_type == :iter
          get_macro_name(node[1])
        else
          get_hidden_macro_name(node)
        end
      end

      # "Hidden macros" are just regular-looking Ruby code we intercept at compile-time.
      # We will try to support common Ruby idioms here that cannot be done at runtime.
      def get_hidden_macro_name(node)
        if node.type == :call_node && node.receiver&.type == :global_variable_read_node && %i[$LOAD_PATH $:].include?(node.receiver.name) && %i[<< unshift].include?(node.name)
          :update_load_path
        end
      end

      def run_macro(macro_name, expr, current_path:, depth:)
        send("macro_#{macro_name}", expr: expr, current_path: current_path, depth: depth)
      end

      def macro_user_macro(expr:, current_path:)
        _, _, name = expr
        macro = @macros[name]
        VM.compile_and_run(macro, path: 'macro')
      end

      def macro_macro!(expr:, current_path:)
        _, call, _, block = expr
        _, name = call.last
        @macros[name] = block
        nothing(expr)
      end

      EXTENSIONS_TO_TRY = ['.rb', '.cpp', ''].freeze

      def macro_autoload(expr:, current_path:, depth:)
        args = expr.arguments&.arguments || []
        const_node, path_node = args
        const = comptime_symbol(const_node)
        begin
          path = comptime_string(path_node)
        rescue ArgumentError
          return drop_load_error "cannot load such file #{path_node.inspect} at #{expr.file}##{expr.line}"
        end

        full_path = EXTENSIONS_TO_TRY.lazy.filter_map do |ext|
          find_full_path(path + ext, base: Dir.pwd, search: true)
        end.first

        unless full_path
          return drop_load_error "cannot load such file #{path} at #{expr.file}##{expr.line}"
        end

        body = load_file(full_path, require_once: true, location: location(expr))
        Sexp.new(:autoload_const, const, path, body)
      end

      def macro_require(expr:, current_path:, depth:)
        args = expr.arguments&.arguments || []
        name = comptime_string(args.first)
        return nothing(expr) if name == 'tempfile' && interpret? # FIXME: not sure how to handle this actually
        if name == 'natalie/inline'
          @inline_cpp_enabled[current_path] = true
          return nothing(expr)
        end
        EXTENSIONS_TO_TRY.each do |extension|
          if (full_path = find_full_path(name + extension, base: Dir.pwd, search: true))
            return load_file(full_path, require_once: true, location: location(expr))
          end
        end
        drop_load_error "cannot load such file #{name} at #{expr.file}##{expr.line}"
      end

      def macro_require_relative(expr:, current_path:, depth:)
        args = expr.arguments&.arguments || []
        name = comptime_string(args.first)
        base = File.dirname(current_path)
        EXTENSIONS_TO_TRY.each do |extension|
          if (full_path = find_full_path(name + extension, base: base, search: false))
            lf = load_file(full_path, require_once: true, location: location(expr))
            return lf
          end
        end
        drop_load_error "cannot load such file #{name} at #{expr.file}##{expr.line}"
      end

      def macro_load(expr:, current_path:, depth:) # rubocop:disable Lint/UnusedMethodArgument
        args = expr.arguments&.arguments || []
        path = comptime_string(args.first)
        full_path = find_full_path(path, base: Dir.pwd, search: true)
        return load_file(full_path, require_once: false, location: location(expr)) if full_path
        drop_load_error "cannot load such file -- #{path}"
      end

      def macro_eval(expr:, current_path:, depth:)
        args = expr.arguments&.arguments || []
        node = args.first
        $stderr.puts 'FIXME: binding passed to eval() will be ignored.' if args.size > 1
        if node.sexp_type == :str
          begin
            Natalie::Parser.new(node[1], current_path).ast
          rescue SyntaxError => e
            drop_error(:SyntaxError, e.message)
          end
        else
          drop_error(:SyntaxError, 'eval() only works on static strings')
        end
      end

      def macro_nat_ignore_require(expr:, current_path:) # rubocop:disable Lint/UnusedMethodArgument
        false_node # Script has not been loaded
      end

      def macro_nat_ignore_require_relative(expr:, current_path:) # rubocop:disable Lint/UnusedMethodArgument
        false_node # Script has not been loaded
      end

      def macro_include_str!(expr:, current_path:)
        args = expr.arguments&.arguments || []
        name = comptime_string(args.first)
        if (full_path = find_full_path(name, base: File.dirname(current_path), search: false))
          s(:str, File.read(full_path))
        else
          raise IOError, "cannot find file #{name} at #{node.file}##{node.line}"
        end
      end

      # $LOAD_PATH << some_expression
      # $LOAD_PATH.unshift(some_expression)
      def macro_update_load_path(expr:, current_path:, depth:)
        if depth > 1
          if expr.is_a?(::Prism::Node)
            name = expr.receiver.name
          else
            name = expr.receiver[1] # receiver is $(gvar, :$LOAD_PATH)
          end
          return drop_error(:LoadError, "Cannot manipulate #{name} at runtime (#{expr.file}##{expr.line})")
        end

        path_to_add = VM.compile_and_run(
          ::Prism::StatementsNode.new(expr.arguments&.arguments, location(expr)),
          path: current_path
        )

        unless path_to_add.is_a?(String) && File.directory?(path_to_add)
          raise LoadPathMacroError, "#{path_to_add.inspect} is not a directory"
        end

        load_path << path_to_add
        Prism.nil_node
      end

      def interpret?
        !!@interpret
      end

      def find_full_path(path, base:, search:)
        if path.start_with?(File::SEPARATOR)
          path if File.file?(path)
        elsif path.start_with?('.' + File::SEPARATOR)
          path = File.expand_path(path, base)
          path if File.file?(path)
        elsif search
          find_file_in_load_path(path)
        else
          path = File.expand_path(path, base)
          path if File.file?(path)
        end
      end

      def find_file_in_load_path(path)
        load_path.map { |d| File.join(d, path) }.detect { |p| File.file?(p) }
      end

      def load_file(path, require_once:, location:)
        return load_cpp_file(path, require_once: require_once, location: location) if path =~ /\.cpp$/

        code = File.read(path)
        unless (ast = @parsed_files[path])
          ast = Natalie::Parser.new(code, path).ast
          @parsed_files[path] = ast
        end

        s(:with_filename, path, require_once, ast)
      end

      def load_cpp_file(path, require_once:, location:)
        name = File.split(path).last.split('.').first
        return false_node if @compiler_context[:required_cpp_files][path]
        @compiler_context[:required_cpp_files][path] = name
        cpp_source = File.read(path)
        init_function = "Value init(Env *env, Value self)"
        transformed_init_function = "Value init_#{name}(Env *env, Value self)"
        if cpp_source.include?(init_function);
          cpp_source.sub!(init_function, transformed_init_function)
        else
          $stderr.puts "Expected #{path} to contain function: `#{init_function}`\n" \
                       "...which will be rewritten to: `#{transformed_init_function}`"
          raise CompileError, "could not load #{name}"
        end
        ::Prism::StatementsNode.new(
          [
            Prism.call_node(
              receiver: nil,
              name: :__internal_inline_code__,
              arguments: [s(:str, cpp_source)]
            ),
            ::Prism.true_node
          ],
          location
        )
      end

      def drop_error(exception_class, message, print_warning: false)
        warn(message) if print_warning
        Prism.call_node(
          receiver: nil,
          name: :raise,
          arguments: [
            s(:const, exception_class),
            s(:str, message)
          ]
        )
      end

      def drop_load_error(message)
        drop_error(:LoadError, message, print_warning: @log_load_error)
      end

      def s(*items)
        sexp = Sexp.new
        items.each { |item| sexp << item }
        sexp
      end

      def false_node
        ::Prism::FalseNode.new(nil)
      end

      def nothing(expr)
        ::Prism::StatementsNode.new([], location(expr))
      end

      def location(expr)
        case expr
        when ::Prism::Node
          expr.location
        when Sexp
          ::Prism::Location.new(::Prism::Source.new(expr.file), 0, 0)
        else
          raise "unknown node type: #{expr.inspect}"
        end
      end
    end
  end
end
