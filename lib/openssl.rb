require 'natalie/inline'
require 'openssl.cpp'

__ld_flags__ '-lcrypto'

module OpenSSL
  class OpenSSLError < StandardError; end

  module Random
    __bind_static_method__ :random_bytes, :OpenSSL_Random_random_bytes
  end

  class Digest
    attr_reader :name

    def self.digest(name, data)
      new(name).digest(data)
    end

    def self.base64digest(name, data)
      new(name).base64digest(data)
    end

    def self.hexdigest(name, data)
      new(name).hexdigest(data)
    end

    def base64digest(data)
      [digest(data)].pack('m0')
    end

    def hexdigest(data)
      digest(data).unpack1('H*')
    end

    def self.const_missing(name)
      normalized_name = new(name.to_s).name
      raise if name.to_s != normalized_name
      klass = Class.new(self) do
        define_method(:initialize) { |*args| super(normalized_name, *args) }
      end
      const_set(name, klass)
      klass
    rescue
      super
    end
  end

  module KDF
    class KDFError < OpenSSLError; end
  end
end
