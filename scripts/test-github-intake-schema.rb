#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
VALIDATOR = File.join(__dir__, "validate-github-intake.rb")
SOURCES = {
  bug: File.join(ROOT, ".github/ISSUE_TEMPLATE/bug.yml"),
  feature: File.join(ROOT, ".github/ISSUE_TEMPLATE/feature.yml"),
  config: File.join(ROOT, ".github/ISSUE_TEMPLATE/config.yml")
}.freeze

def safe_load(path)
  YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
end

def write_yaml(path, value)
  File.write(path, YAML.dump(value))
end

def mutate(path)
  value = safe_load(path)
  yield value
  write_yaml(path, value)
end

def body_item(form, id)
  form.fetch("body").find { |item| item["id"] == id }
end

def with_fixture
  Dir.mktmpdir("talkie-intake-schema.") do |directory|
    paths = {}
    SOURCES.each do |name, source|
      destination = File.join(directory, File.basename(source))
      FileUtils.cp(source, destination)
      paths[name] = destination
    end
    yield paths
  end
end

def validator_result(paths)
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    VALIDATOR,
    paths.fetch(:bug),
    paths.fetch(:feature),
    paths.fetch(:config)
  )
  [status.success?, "#{stdout}#{stderr}"]
end

failures = []
cases = 0

expect_valid = lambda do |name, &mutation|
  cases += 1
  with_fixture do |paths|
    mutation.call(paths) if mutation
    valid, output = validator_result(paths)
    failures << "#{name}: expected valid schema, got #{output.lines.first.to_s.strip}" unless valid
  end
end

expect_invalid = lambda do |name, expected_message, &mutation|
  cases += 1
  with_fixture do |paths|
    mutation.call(paths)
    valid, output = validator_result(paths)
    if valid
      failures << "#{name}: invalid schema was accepted"
    elsif !output.include?(expected_message)
      failures << "#{name}: expected #{expected_message.inspect}, got #{output.lines.first.to_s.strip.inspect}"
    end
  end
end

expect_valid.call("current repository forms")

expect_valid.call("official optional metadata formats") do |paths|
  mutate(paths.fetch(:bug)) do |form|
    form["labels"] = "bug, triage"
    form["assignees"] = "octocat, hubot"
    form["projects"] = "b1rd33/1"
    form["type"] = "Bug"
  end
end

expect_valid.call("official checkbox and upload elements") do |paths|
  mutate(paths.fetch(:feature)) do |form|
    form.fetch("body") << {
      "type" => "checkboxes",
      "id" => "confirmations",
      "attributes" => {
        "description" => "Optional confirmations.",
        "options" => [
          {"label" => "I checked existing requests", "required" => false},
          {"label" => "I reviewed the privacy impact", "required" => true}
        ]
      },
      "validations" => {"required" => false}
    }
    form.fetch("body") << {
      "type" => "upload",
      "id" => "supporting_files",
      "attributes" => {
        "label" => "Sanitized supporting files",
        "description" => "Optional non-private screenshots."
      },
      "validations" => {
        "required" => false,
        "accept" => ".png,.jpg,.log"
      }
    }
  end
end

expect_invalid.call("duplicate dropdown option", "dropdown options must be unique") do |paths|
  mutate(paths.fetch(:bug)) do |form|
    options = body_item(form, "architecture").fetch("attributes").fetch("options")
    options[1] = options[0]
  end
end

expect_invalid.call("reserved dropdown option", "reserved option") do |paths|
  mutate(paths.fetch(:bug)) do |form|
    body_item(form, "architecture").fetch("attributes").fetch("options")[0] = "None"
  end
end

expect_invalid.call("boolean dropdown option", "dropdown options must be non-empty strings") do |paths|
  mutate(paths.fetch(:bug)) do |form|
    body_item(form, "architecture").fetch("attributes").fetch("options")[0] = true
  end
end

expect_invalid.call("n/a option with a default", "cannot use n/a when a default is set") do |paths|
  mutate(paths.fetch(:bug)) do |form|
    attributes = body_item(form, "architecture").fetch("attributes")
    attributes["options"][0] = "n/a"
    attributes["default"] = 1
  end
end

expect_invalid.call("dropdown default out of bounds", "default must index an option") do |paths|
  mutate(paths.fetch(:bug)) do |form|
    body_item(form, "architecture").fetch("attributes")["default"] = 20
  end
end

expect_invalid.call("unknown top-level key", "unsupported top-level keys") do |paths|
  mutate(paths.fetch(:bug)) { |form| form["unexpected"] = true }
end

expect_invalid.call("duplicate top-level labels", "labels entries must be unique") do |paths|
  mutate(paths.fetch(:bug)) { |form| form["labels"] = ["bug", "bug"] }
end

expect_invalid.call("duplicate top-level assignees", "assignees entries must be unique") do |paths|
  mutate(paths.fetch(:bug)) { |form| form["assignees"] = ["octocat", "octocat"] }
end

expect_invalid.call("duplicate form names", "form names must be unique") do |paths|
  bug_name = safe_load(paths.fetch(:bug)).fetch("name")
  mutate(paths.fetch(:feature)) { |form| form["name"] = bug_name }
end

expect_invalid.call("unknown element key", "unsupported element keys") do |paths|
  mutate(paths.fetch(:bug)) { |form| body_item(form, "version")["unexpected"] = true }
end

expect_invalid.call("unknown element type", "unsupported type") do |paths|
  mutate(paths.fetch(:bug)) { |form| body_item(form, "version")["type"] = "slider" }
end

expect_invalid.call("invalid element id", "needs a valid id") do |paths|
  mutate(paths.fetch(:bug)) { |form| body_item(form, "version")["id"] = "bad id" }
end

expect_invalid.call("duplicate element labels", "field and option labels must be unique") do |paths|
  mutate(paths.fetch(:bug)) do |form|
    body_item(form, "actual").fetch("attributes")["label"] =
      body_item(form, "expected").fetch("attributes").fetch("label")
  end
end

expect_invalid.call("duplicate checkbox option labels", "field and option labels must be unique") do |paths|
  mutate(paths.fetch(:feature)) do |form|
    form.fetch("body") << {
      "type" => "checkboxes",
      "id" => "confirmations",
      "attributes" => {
        "label" => "Confirmations",
        "options" => [
          {"label" => "I checked"},
          {"label" => "I checked"}
        ]
      }
    }
  end
end

expect_invalid.call("unknown checkbox option key", "unsupported checkbox option keys") do |paths|
  mutate(paths.fetch(:feature)) do |form|
    form.fetch("body") << {
      "type" => "checkboxes",
      "id" => "confirmations",
      "attributes" => {
        "label" => "Confirmations",
        "options" => [
          {"label" => "I checked", "value" => "checked"}
        ]
      }
    }
  end
end

expect_invalid.call("markdown id", "markdown does not permit id") do |paths|
  mutate(paths.fetch(:bug)) { |form| form.fetch("body").first["id"] = "intro" }
end

expect_invalid.call("unknown markdown attribute", "unsupported markdown attributes") do |paths|
  mutate(paths.fetch(:bug)) { |form| form.fetch("body").first.fetch("attributes")["label"] = "Intro" }
end

expect_invalid.call("unknown input attribute", "unsupported input attributes") do |paths|
  mutate(paths.fetch(:bug)) { |form| body_item(form, "version").fetch("attributes")["render"] = "text" }
end

expect_invalid.call("non-string textarea render", "render must be a non-empty string") do |paths|
  mutate(paths.fetch(:feature)) { |form| body_item(form, "problem").fetch("attributes")["render"] = true }
end

expect_invalid.call("unknown validation key", "unsupported input validations") do |paths|
  mutate(paths.fetch(:bug)) { |form| body_item(form, "version").fetch("validations")["minimum"] = 1 }
end

expect_invalid.call("unknown upload attribute", "unsupported upload attributes") do |paths|
  mutate(paths.fetch(:feature)) do |form|
    form.fetch("body") << {
      "type" => "upload",
      "id" => "supporting_files",
      "attributes" => {
        "label" => "Sanitized supporting files",
        "placeholder" => "Choose a file"
      }
    }
  end
end

expect_invalid.call("unsupported upload extension", "unsupported upload extension") do |paths|
  mutate(paths.fetch(:feature)) do |form|
    form.fetch("body") << {
      "type" => "upload",
      "id" => "supporting_files",
      "attributes" => {"label" => "Sanitized supporting files"},
      "validations" => {"accept" => ".png,.exe"}
    }
  end
end

expect_invalid.call("unknown config key", "unsupported config keys") do |paths|
  mutate(paths.fetch(:config)) { |config| config["unexpected"] = true }
end

unless failures.empty?
  warn "GitHub intake schema tests failed (#{failures.length} of #{cases} case(s))"
  failures.each { |failure| warn " - #{failure}" }
  exit 1
end

puts "GitHub intake schema tests passed (#{cases} cases)."
