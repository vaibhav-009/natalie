require 'openssl'

module Digest
  SHA256 = OpenSSL::Digest::SHA256
  SHA384 = OpenSSL::Digest::SHA384
  SHA512 = OpenSSL::Digest::SHA512
end
