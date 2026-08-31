#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"

KEEP_ANNOTATION = "helm.sh/resource-policy"
BUNDLE_ANNOTATION = "inference.networking.k8s.io/bundle-version"

options = {
  expected_version: nil,
  compare_to: nil,
  require_keep: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: validate_manifest.rb [options] MANIFEST"
  parser.on("--expected-version VERSION") { |value| options[:expected_version] = value }
  parser.on("--compare-to FILE") { |value| options[:compare_to] = value }
  parser.on("--require-keep") { options[:require_keep] = true }
end.parse!

manifest_path = ARGV.shift
abort "A manifest path is required" unless manifest_path
abort "Unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?

def safe_load_document(document, filename)
  YAML.safe_load(
    document,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false,
    filename: filename
  )
rescue ArgumentError
  # Compatibility with the positional API used by older Psych releases.
  YAML.safe_load(document, [], [], false, filename)
end

def load_documents(path)
  content = File.read(path)
  abort "#{path} is empty" if content.strip.empty?

  content.split(/^---[[:space:]]*$\n?/).map do |document|
    safe_load_document(document, path) unless document.strip.empty?
  end.compact
rescue Errno::ENOENT
  abort "Manifest not found: #{path}"
rescue Psych::Exception => error
  abort "Invalid YAML in #{path}: #{error.message}"
end

def validate_crds(documents, path, require_keep)
  abort "#{path} contains no YAML documents" if documents.empty?

  names = documents.each_with_index.map do |document, index|
    abort "#{path} document #{index + 1} is not a YAML object" unless document.is_a?(Hash)

    unless document["apiVersion"] == "apiextensions.k8s.io/v1" &&
           document["kind"] == "CustomResourceDefinition"
      abort "#{path} document #{index + 1} is not an apiextensions.k8s.io/v1 CustomResourceDefinition"
    end

    name = document.dig("metadata", "name")
    abort "#{path} document #{index + 1} has no metadata.name" unless name.is_a?(String) && !name.empty?

    versions = document.dig("spec", "versions")
    abort "#{path} CRD #{name} has no spec.versions" unless versions.is_a?(Array) && !versions.empty?

    if require_keep && document.dig("metadata", "annotations", KEEP_ANNOTATION) != "keep"
      abort "#{path} CRD #{name} does not have #{KEEP_ANNOTATION}: keep"
    end

    name
  end

  duplicates = names.group_by(&:itself).select { |_name, occurrences| occurrences.length > 1 }.keys
  abort "#{path} contains duplicate CRDs: #{duplicates.join(', ')}" unless duplicates.empty?

  names
end

documents = load_documents(manifest_path)
names = validate_crds(documents, manifest_path, options[:require_keep])

if options[:expected_version]
  bundle_versions = documents.map { |document| document.dig("metadata", "annotations", BUNDLE_ANNOTATION) }.compact.uniq
  unless bundle_versions.empty? || bundle_versions == [options[:expected_version]]
    warn "warning: embedded bundle version #{bundle_versions.join(', ')} does not match #{options[:expected_version]}"
  end
end

if options[:compare_to]
  upstream_documents = load_documents(options[:compare_to])
  upstream_names = validate_crds(upstream_documents, options[:compare_to], false)

  normalize = lambda do |document|
    copy = Marshal.load(Marshal.dump(document))
    annotations = copy.dig("metadata", "annotations")
    annotations.delete(KEEP_ANNOTATION) if annotations.is_a?(Hash)
    copy
  end

  rendered_by_name = documents.to_h { |document| [document.dig("metadata", "name"), normalize.call(document)] }
  upstream_by_name = upstream_documents.to_h { |document| [document.dig("metadata", "name"), normalize.call(document)] }

  abort "Rendered CRD names differ from upstream" unless names.sort == upstream_names.sort
  abort "Rendered CRDs differ from upstream beyond the keep annotation" unless rendered_by_name == upstream_by_name
end

puts "Validated #{documents.length} CRD(s): #{names.sort.join(', ')}"
