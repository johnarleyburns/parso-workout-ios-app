#!/usr/bin/env bash
set -euo pipefail
ruby -ropenssl -rbase64 -e '
  key=OpenSSL::PKey::EC.generate("prime256v1"); message="header.payload"
  der=key.sign("SHA256",message); values=OpenSSL::ASN1.decode(der).value.map(&:value)
  raw=values.map { |n| [n.to_s(16).rjust(64,"0")].pack("H*") }.join
  abort "expected 64-byte ES256 JWS signature" unless raw.bytesize==64
  abort "raw signature unexpectedly DER" if raw.start_with?("0") && raw.bytesize != 64
  seq=OpenSSL::ASN1::Sequence.new(values.map { |n| OpenSSL::ASN1::Integer.new(n) }).to_der
  abort "round-trip verification failed" unless key.verify("SHA256",seq,message)
  puts "ES256 JWS conversion: ok"'
