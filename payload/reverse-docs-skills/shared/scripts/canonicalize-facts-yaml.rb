#!/usr/bin/env ruby
# Canonicalize a facts.yml document by parsing YAML and emitting deterministic JSON.
require "json"
require "yaml"

def reject_unsafe(value, path = "$")
  case value
  when Hash
    value.each { |key, child| reject_unsafe(key, "#{path}.<key>"); reject_unsafe(child, "#{path}.#{key}") }
  when Array
    value.each_with_index { |child, index| reject_unsafe(child, "#{path}[#{index}]") }
  when String
    abort("unsafe control character at #{path}") if value.each_codepoint.any? { |code| code.zero? || (code < 0x20 && ![9, 10, 13].include?(code)) }
  when NilClass, TrueClass, FalseClass, Integer, Float
  else
    abort("unsupported YAML type at #{path}: #{value.class}")
  end
end

begin
  document = YAML.safe_load(STDIN.read, permitted_classes: [], permitted_symbols: [], aliases: false)
  abort("facts root must be a mapping") unless document.is_a?(Hash)
  document = document.dup
  document.delete("run_id")
  reject_unsafe(document)
  STDOUT.write(JSON.generate(document, allow_nan: false))
  STDOUT.write("\n")
rescue Psych::Exception, JSON::GeneratorError => error
  warn("invalid facts YAML: #{error.message}")
  exit(2)
end
