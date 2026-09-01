#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "yaml"

manifest_path, chart_path = ARGV
abort "Usage: split_manifest.rb MANIFEST CHART_DIRECTORY" unless manifest_path && chart_path && ARGV.length == 2

def safe_load_document(document, filename)
  YAML.safe_load(
    document,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false,
    filename: filename
  )
rescue ArgumentError
  YAML.safe_load(document, [], [], false, filename)
end

documents = File.read(manifest_path).split(/^---[[:space:]]*$\n?/).reject { |document| document.strip.empty? }
abort "#{manifest_path} contains no YAML documents" if documents.empty?

crds_directory = File.join(chart_path, "crds")
FileUtils.mkdir_p(crds_directory)

documents.each_with_index do |document, index|
  resource = safe_load_document(document, manifest_path)
  name = resource.is_a?(Hash) ? resource.dig("metadata", "name") : nil
  abort "#{manifest_path} document #{index + 1} has no metadata.name" unless name.is_a?(String) && !name.empty?

  safe_name = name.gsub(/[^0-9A-Za-z.-]/, "-")
  basename = format("%03d-%s.yaml", index + 1, safe_name)
  File.write(File.join(crds_directory, basename), "#{document.rstrip}\n")
end

puts "Generated #{documents.length} individual CRD file(s)"
