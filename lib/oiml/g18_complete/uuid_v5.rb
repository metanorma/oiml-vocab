# frozen_string_literal: true

require "digest"

module Oiml
  module G18Complete
    module UuidV5
      # Pure-stdlib RFC 4122 §4.3 (SHA-1, version 5) UUID generator.
      #
      # Ruby's stdlib has no UUID v5 outside of ActiveSupport's Digest::UUID.
      # Rather than pull in a gem, implement the ~20 lines of RFC directly.
      module_function

      def generate(namespace_uuid, name)
        hash = Digest::SHA1.digest(namespace_bytes(namespace_uuid) + name.to_s)
        bytes = hash.bytes.first(16)

        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        hex = bytes.map { |b| format("%02x", b) }
        "#{hex[0..3].join}-#{hex[4..5].join}-#{hex[6..7].join}-#{hex[8..9].join}-#{hex[10..15].join}"
      end

      def namespace_bytes(uuid_str)
        parts = uuid_str.split("-")
        raise ArgumentError, "invalid UUID: #{uuid_str}" unless parts.size == 5

        hex = parts.join
        raise ArgumentError, "invalid UUID hex: #{uuid_str}" unless hex.match?(/\A[0-9a-fA-F]{32}\z/)

        # Pack as raw 16-byte binary string so it concatenates cleanly with
        # the name string passed to Digest::SHA1.digest.
        [hex].pack("H*")
      end
    end
  end
end
