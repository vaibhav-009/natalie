module Natalie
  class Compiler
    class ConstPrepper
      def initialize(node, pass:)
        @private = true
        case node.type
        when :constant_read_node, :constant_target_node
          @name = node.name
          @namespace = PushSelfInstruction.new
        when :constant_path_node, :constant_path_target_node
          raise 'unexpected child here' if node.child.type != :constant_read_node
          @name = node.child.name
          if node.parent
            @namespace = pass.transform_expression(node.parent, used: true)
            @private = false
          else
            @namespace = PushObjectClassInstruction.new
          end
        else
          raise "Unknown constant name type #{node.inspect} #{node.location.path}##{node.location.start_line}"
        end
      end

      attr_reader :name, :namespace

      def private?
        @private
      end
    end
  end
end
