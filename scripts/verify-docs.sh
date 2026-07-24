#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

ruby <<'RUBY'
require "uri"

public_documents = %w[
  README.md
  PRIVACY.md
  CONTRIBUTING.md
  SECURITY.md
  SUPPORT.md
  CHANGELOG.md
  docs/install-free.md
  docs/testing-matrix.md
]

def anchor_for(heading)
  heading
    .downcase
    .gsub(/<[^>]+>/, "")
    .gsub(/[^\p{Alnum}\p{M}\s_-]/, "")
    .tr(" ", "-")
    .gsub(/-+/, "-")
end

def headings(path)
  File.readlines(path, chomp: true).filter_map do |line|
    match = line.match(/^(?:\#){1,6}\s+(.+?)\s*(?:\#)*\s*$/)
    anchor_for(match[1]) if match
  end
end

failures = []
public_documents.each do |document|
  body = File.read(document)
  body.scan(/!?\[[^\]]*\]\(([^)]+)\)/).flatten.each do |raw_target|
    target = raw_target.strip.sub(/\A<(.+)>\z/, '\1')
    next if target.match?(/\A(?:https?:|mailto:)/)

    path_part, fragment = target.split("#", 2)
    linked_path = if path_part.empty?
      document
    else
      File.expand_path(path_part, File.dirname(document))
    end
    unless File.exist?(linked_path)
      failures << "#{document}: missing target #{target}"
      next
    end
    next if fragment.nil? || fragment.empty? || !File.file?(linked_path)

    decoded_fragment = URI.decode_www_form_component(fragment).downcase
    unless headings(linked_path).include?(decoded_fragment)
      failures << "#{document}: missing anchor ##{fragment} in #{linked_path}"
    end
  end
end

required_headings = [
  "# Talkie",
  "## Requirements",
  "## Install",
  "## Core workflows",
  "## Data flow",
  "## Build, test, and contribute",
  "## Project status and known limitations",
]
readme_lines = File.readlines("README.md", chomp: true)
positions = required_headings.map do |heading|
  index = readme_lines.index(heading)
  failures << "README.md: missing required heading #{heading}" unless index
  index
end
if positions.all? && positions != positions.sort
  failures << "README.md: required headings are out of order"
end

public_documents.each do |document|
  File.readlines(document, chomp: true).each_with_index do |line, index|
    if line.match?(/\bfree (?:build|version)\b/i)
      failures << "#{document}:#{index + 1}: stale pricing/status terminology"
    end
  end
end

{
  "docs/images/talkie-settings.png" => [680, 360],
  "docs/images/talkie-pill.png" => [300, 80],
}.each do |path, minimum|
  unless File.file?(path)
    failures << "#{path}: screenshot is missing"
    next
  end
  data = File.binread(path)
  unless data.start_with?("\x89PNG\r\n\x1a\n".b)
    failures << "#{path}: not a PNG"
    next
  end
  width, height = data.byteslice(16, 8).unpack("NN")
  if width < minimum[0] || height < minimum[1]
    failures << "#{path}: #{width}x#{height} is below #{minimum.join('x')}"
  end

  chunks = []
  offset = 8
  while offset + 12 <= data.bytesize
    length = data.byteslice(offset, 4).unpack1("N")
    type = data.byteslice(offset + 4, 4)
    chunks << type
    offset += length + 12
    break if type == "IEND"
  end
  metadata_chunks = chunks & %w[tEXt zTXt iTXt eXIf tIME]
  unless metadata_chunks.empty?
    failures << "#{path}: contains metadata chunks #{metadata_chunks.join(', ')}"
  end
end

abort failures.join("\n") unless failures.empty?
puts "Documentation checks passed."
RUBY
