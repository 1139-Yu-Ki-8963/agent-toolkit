#!/usr/bin/env ruby
# Parse safe YAML from stdin and serialize its complete data model as JSON.
require "json"
require "yaml"

begin
  value = YAML.safe_load(STDIN.read, permitted_classes: [], permitted_symbols: [], aliases: false)
  STDOUT.write(JSON.generate(value, allow_nan: false))
rescue Psych::Exception, JSON::GeneratorError => error
  warn(error.message)
  exit(2)
end
