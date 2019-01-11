# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'request_error'

class Blob
  extend DbCurrentTime

  def initialize locator
    @locator = locator
  end

  def empty?
    !!@locator.match(/^d41d8cd98f00b204e9800998ecf8427e(\+.*)?$/)
  end

  # In order to get a Blob from Keep, you have to prove either
  # [a] you have recently written it to Keep yourself, or
  # [b] apiserver has recently decided that you should be able to read it
  #
  # To ensure that the requestor of a blob is authorized to read it,
  # Keep requires clients to timestamp the blob locator with an expiry
  # time, and to sign the timestamped locator with their API token.
  #
  # A signed blob locator has the form:
  #     locator_hash +A blob_signature @ timestamp
  # where the timestamp is a Unix time expressed as a hexadecimal value,
  # and the blob_signature is the signed locator_hash + API token + timestamp.
  #
  class InvalidSignatureError < RequestError
  end

  # Blob.sign_locator: return a signed and timestamped blob locator.
  #
  # The 'opts' argument should include:
  #   [required] :api_token - API token (signatures only work for this token)
  #   [optional] :key       - the Arvados server-side blobstore key
  #   [optional] :ttl       - number of seconds before signature should expire
  #   [optional] :expire    - unix timestamp when signature should expire
  #
  def self.sign_locator blob_locator, opts
    # We only use the hash portion for signatures.
    blob_hash = blob_locator.split('+').first

    # Generate an expiry timestamp (seconds after epoch, base 16)
    if opts[:expire]
      if opts[:ttl]
        raise "Cannot specify both :ttl and :expire options"
      end
      timestamp = opts[:expire]
    else
      timestamp = db_current_time.to_i +
        (opts[:ttl] || Rails.configuration.blob_signature_ttl)
    end
    timestamp_hex = timestamp.to_s(16)
    # => "53163cb4"
    blob_signature_ttl = Rails.configuration.blob_signature_ttl.to_s(16)

    # Generate a signature.
    signature =
      generate_signature((opts[:key] or Rails.configuration.blob_signing_key),
                         blob_hash, opts[:api_token], timestamp_hex, blob_signature_ttl)

    blob_locator + '+A' + signature + '@' + timestamp_hex
  end

  # Blob.verify_signature
  #   Safely verify the signature on a blob locator.
  #   Return value: true if the locator has a valid signature, false otherwise
  #   Arguments: signed_blob_locator, opts
  #
  def self.verify_signature(*args)
    begin
      self.verify_signature!(*args)
      true
    rescue Blob::InvalidSignatureError
      false
    end
  end

  # Blob.verify_signature!
  #   Verify the signature on a blob locator.
  #   Return value: true if the locator has a valid signature
  #   Arguments: signed_blob_locator, opts
  #   Exceptions:
  #     Blob::InvalidSignatureError if the blob locator does not include a
  #     valid signature
  #
  def self.verify_signature! signed_blob_locator, opts
    blob_hash = signed_blob_locator.split('+').first
    given_signature, timestamp = signed_blob_locator.
      split('+A').last.
      split('+').first.
      split('@')

    if !timestamp
      raise Blob::InvalidSignatureError.new 'No signature provided.'
    end
    unless timestamp =~ /^[\da-f]+$/
      raise Blob::InvalidSignatureError.new 'Timestamp is not a base16 number.'
    end
    if timestamp.to_i(16) < (opts[:now] or db_current_time.to_i)
      raise Blob::InvalidSignatureError.new 'Signature expiry time has passed.'
    end
    blob_signature_ttl = Rails.configuration.blob_signature_ttl.to_s(16)

    my_signature =
      generate_signature((opts[:key] or Rails.configuration.blob_signing_key),
                         blob_hash, opts[:api_token], timestamp, blob_signature_ttl)

    if my_signature != given_signature
      raise Blob::InvalidSignatureError.new 'Signature is invalid.'
    end

    true
  end

  def self.generate_signature key, blob_hash, api_token, timestamp, blob_signature_ttl
    OpenSSL::HMAC.hexdigest('sha1', key,
                            [blob_hash,
                             api_token,
                             timestamp,
                             blob_signature_ttl].join('@'))
  end
end
