#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline validator for the GitHub issue-form syntax documented at:
# https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms
# https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema
# The schema is in public preview, so adversarial fixtures cover the supported
# syntax snapshot used by this repository without adding a routine network call.

require "yaml"

ISSUE_TOP_LEVEL_KEYS = %w[
  name description body assignees labels title type projects
].freeze
ELEMENT_KEYS = %w[type id attributes validations].freeze
ELEMENT_TYPES = %w[checkboxes dropdown input markdown textarea upload].freeze
SUPPORTED_UPLOAD_EXTENSIONS = %w[
  .zip .gz .tar.gz
  .pdf .docx .xlsx .pptx
  .png .jpg .jpeg .gif .svg .webp
  .mp4 .mov .webm
  .json .py .js .ts .log .txt .csv
].freeze

def fail_schema(path, message)
  warn "#{path}: #{message}"
  exit 1
end

def load_yaml(path)
  YAML.safe_load(
    File.read(path),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
rescue Psych::Exception => error
  fail_schema(path, "invalid YAML: #{error.message.lines.first.strip}")
end

def require_mapping(path, context, value)
  fail_schema(path, "#{context} must be a mapping") unless value.is_a?(Hash)
  value
end

def validate_keys(path, context, mapping, allowed)
  non_string = mapping.keys.reject { |key| key.is_a?(String) }
  fail_schema(path, "#{context} keys must be strings") unless non_string.empty?
  unsupported = mapping.keys - allowed
  unless unsupported.empty?
    fail_schema(path, "unsupported #{context} keys: #{unsupported.join(", ")}")
  end
end

def require_non_empty_string(path, context, value)
  unless value.is_a?(String) && !value.strip.empty?
    fail_schema(path, "#{context} must be a non-empty string")
  end
  value
end

def validate_optional_strings(path, context, mapping, keys)
  keys.each do |key|
    next unless mapping.key?(key)
    require_non_empty_string(path, "#{context} #{key}", mapping[key])
  end
end

def validate_boolean(path, context, value)
  fail_schema(path, "#{context} must be boolean") unless [true, false].include?(value)
end

def metadata_entries(path, key, value)
  entries = case value
            when String
              value.split(",", -1).map(&:strip)
            when Array
              value
            else
              fail_schema(path, "#{key} must be an array or comma-delimited string")
            end
  unless entries.all? { |entry| entry.is_a?(String) && !entry.strip.empty? }
    fail_schema(path, "#{key} entries must be non-empty strings")
  end
  fail_schema(path, "#{key} entries must be unique") unless entries.uniq.length == entries.length
  entries
end

def validate_required_only(path, type, validations)
  validate_keys(path, "#{type} validations", validations, %w[required])
  return unless validations.key?("required")
  validate_boolean(path, "#{type} required validation", validations["required"])
end

def validate_label(path, context, attributes)
  require_non_empty_string(path, "#{context} label", attributes["label"])
end

def register_label(path, seen_labels, label)
  return if label.nil?
  fail_schema(path, "field and option labels must be unique") if seen_labels.include?(label)
  seen_labels << label
end

def validate_markdown(path, index, element, attributes)
  fail_schema(path, "markdown does not permit id") if element.key?("id")
  fail_schema(path, "markdown does not permit validations") if element.key?("validations")
  validate_keys(path, "markdown attributes", attributes, %w[value])
  require_non_empty_string(path, "markdown item #{index} value", attributes["value"])
end

def validate_input(path, attributes, validations)
  validate_keys(path, "input attributes", attributes, %w[label description placeholder value])
  validate_label(path, "input", attributes)
  validate_optional_strings(path, "input", attributes, %w[description placeholder value])
  validate_required_only(path, "input", validations)
end

def validate_textarea(path, attributes, validations)
  validate_keys(path, "textarea attributes", attributes, %w[label description placeholder value render])
  validate_label(path, "textarea", attributes)
  validate_optional_strings(path, "textarea", attributes, %w[description placeholder value render])
  validate_required_only(path, "textarea", validations)
end

def validate_dropdown(path, attributes, validations)
  validate_keys(path, "dropdown attributes", attributes, %w[label description multiple options default])
  validate_label(path, "dropdown", attributes)
  validate_optional_strings(path, "dropdown", attributes, %w[description])
  validate_boolean(path, "dropdown multiple attribute", attributes["multiple"]) if attributes.key?("multiple")

  options = attributes["options"]
  unless options.is_a?(Array) && !options.empty? &&
         options.all? { |option| option.is_a?(String) && !option.strip.empty? }
    fail_schema(path, "dropdown options must be non-empty strings")
  end
  fail_schema(path, "dropdown options must be unique") unless options.uniq.length == options.length
  if options.any? { |option| option.strip.casecmp("none").zero? }
    fail_schema(path, "dropdown contains reserved option none")
  end

  if attributes.key?("default")
    default = attributes["default"]
    unless default.is_a?(Integer) && default >= 0 && default < options.length
      fail_schema(path, "dropdown default must index an option")
    end
    if options.any? { |option| option.strip.casecmp("n/a").zero? }
      fail_schema(path, "dropdown cannot use n/a when a default is set")
    end
  end

  validate_required_only(path, "dropdown", validations)
end

def validate_checkboxes(path, attributes, validations, seen_labels)
  validate_keys(path, "checkboxes attributes", attributes, %w[label description options])
  if attributes.key?("label")
    label = require_non_empty_string(path, "checkboxes label", attributes["label"])
    register_label(path, seen_labels, label)
  end
  validate_optional_strings(path, "checkboxes", attributes, %w[description])

  options = attributes["options"]
  unless options.is_a?(Array) && !options.empty?
    fail_schema(path, "checkboxes options must be a non-empty array")
  end
  options.each_with_index do |option, option_index|
    require_mapping(path, "checkbox option #{option_index}", option)
    validate_keys(path, "checkbox option", option, %w[label required])
    label = require_non_empty_string(path, "checkbox option #{option_index} label", option["label"])
    register_label(path, seen_labels, label)
    if option.key?("required")
      validate_boolean(path, "checkbox option #{option_index} required", option["required"])
    end
  end

  validate_required_only(path, "checkboxes", validations)
end

def validate_upload(path, attributes, validations)
  validate_keys(path, "upload attributes", attributes, %w[label description])
  validate_label(path, "upload", attributes)
  validate_optional_strings(path, "upload", attributes, %w[description])
  validate_keys(path, "upload validations", validations, %w[required accept])
  if validations.key?("required")
    validate_boolean(path, "upload required validation", validations["required"])
  end
  return unless validations.key?("accept")

  accept = require_non_empty_string(path, "upload accept validation", validations["accept"])
  extensions = accept.split(",", -1).map(&:strip)
  if extensions.any?(&:empty?)
    fail_schema(path, "upload accept must be a comma-separated extension list")
  end
  fail_schema(path, "upload extensions must be unique") unless extensions.uniq.length == extensions.length
  unsupported = extensions - SUPPORTED_UPLOAD_EXTENSIONS
  unless unsupported.empty?
    fail_schema(path, "unsupported upload extension: #{unsupported.join(", ")}")
  end
end

def validate_form(path, required_ids)
  form = require_mapping(path, "top level", load_yaml(path))
  validate_keys(path, "top-level", form, ISSUE_TOP_LEVEL_KEYS)

  %w[name description].each do |key|
    require_non_empty_string(path, key, form[key])
  end
  validate_optional_strings(path, "top-level", form, %w[title type])

  %w[labels assignees].each do |key|
    metadata_entries(path, key, form[key]) if form.key?(key)
  end
  if form.key?("projects")
    projects = metadata_entries(path, "projects", form["projects"])
    invalid = projects.reject { |project| project.match?(/\A[A-Za-z0-9_.-]+\/[0-9]+\z/) }
    fail_schema(path, "projects entries must use OWNER/NUMBER") unless invalid.empty?
  end

  body = form["body"]
  fail_schema(path, "body must be a non-empty array") unless body.is_a?(Array) && !body.empty?
  unless body.any? { |item| item.is_a?(Hash) && item["type"] != "markdown" }
    fail_schema(path, "body must contain at least one non-markdown field")
  end

  seen_ids = []
  seen_labels = []
  body.each_with_index do |element, index|
    require_mapping(path, "body item #{index}", element)
    validate_keys(path, "element", element, ELEMENT_KEYS)

    type = element["type"]
    fail_schema(path, "body item #{index} has unsupported type") unless ELEMENT_TYPES.include?(type)
    attributes = require_mapping(path, "body item #{index} attributes", element["attributes"])

    if type == "markdown"
      validate_markdown(path, index, element, attributes)
      next
    end

    if element.key?("id")
      id = element["id"]
      unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9_-]+\z/)
        fail_schema(path, "body item #{index} needs a valid id")
      end
      fail_schema(path, "duplicate id #{id}") if seen_ids.include?(id)
      seen_ids << id
    end

    validations = element.fetch("validations", {})
    require_mapping(path, "#{type} validations", validations)
    case type
    when "input"
      validate_input(path, attributes, validations)
      register_label(path, seen_labels, attributes["label"])
    when "textarea"
      validate_textarea(path, attributes, validations)
      register_label(path, seen_labels, attributes["label"])
    when "dropdown"
      validate_dropdown(path, attributes, validations)
      register_label(path, seen_labels, attributes["label"])
    when "checkboxes"
      validate_checkboxes(path, attributes, validations, seen_labels)
    when "upload"
      validate_upload(path, attributes, validations)
      register_label(path, seen_labels, attributes["label"])
    end
  end

  missing = required_ids - seen_ids
  fail_schema(path, "missing required field ids: #{missing.join(", ")}") unless missing.empty?
  required_ids.each do |id|
    element = body.find { |item| item["id"] == id }
    fail_schema(path, "#{id} must be required") unless element.dig("validations", "required") == true
  end

  form
end

bug_path, feature_path, config_path = ARGV
unless bug_path && feature_path && config_path
  warn "usage: validate-github-intake.rb BUG_FORM FEATURE_FORM ISSUE_CONFIG"
  exit 2
end

bug_form = validate_form(
  bug_path,
  %w[version macos_version architecture engine_mode expected actual steps regression]
)
feature_form = validate_form(
  feature_path,
  %w[problem proposed_behavior privacy_impact local_offline_impact alternatives]
)
if bug_form["name"] == feature_form["name"]
  fail_schema(feature_path, "form names must be unique")
end

feature_ids = feature_form.fetch("body").map { |item| item["id"] }.compact
expected_order = %w[problem proposed_behavior privacy_impact local_offline_impact alternatives]
positions = expected_order.map { |id| feature_ids.index(id) }
unless positions == positions.sort
  fail_schema(feature_path, "feature questions must remain in problem-first order")
end

config = require_mapping(config_path, "config top level", load_yaml(config_path))
validate_keys(config_path, "config", config, %w[blank_issues_enabled contact_links])
fail_schema(config_path, "blank issues must be disabled") unless config["blank_issues_enabled"] == false
links = config["contact_links"]
unless links.is_a?(Array) && links.length == 2
  fail_schema(config_path, "contact_links must contain Discussions and private security guidance")
end
expected_urls = [
  "https://github.com/b1rd33/talkie/discussions",
  "https://github.com/b1rd33/talkie/security/policy"
]
links.each_with_index do |link, index|
  require_mapping(config_path, "contact link #{index}", link)
  validate_keys(config_path, "contact link", link, %w[name url about])
  %w[name url about].each do |key|
    require_non_empty_string(config_path, "contact link #{index} #{key}", link[key])
  end
end
actual_urls = links.map { |link| link["url"] }
unless actual_urls == expected_urls
  fail_schema(config_path, "contact links must use stable repository URLs")
end
security_link = links.last
unless security_link["name"].match?(/security|vulnerability/i) &&
       security_link["about"].match?(/private/i) &&
       !security_link["about"].match?(/public issue/i)
  fail_schema(config_path, "security contact must direct reporters to private vulnerability reporting")
end

[bug_path, feature_path].each do |path|
  content = File.read(path)
  forbidden_prompts = [
    /paste your API key here/i,
    /attach (?:your )?transcript/i,
    /upload (?:a |your )?recording/i,
    /provide (?:your )?clipboard contents/i
  ]
  if forbidden_prompts.any? { |pattern| content.match?(pattern) }
    fail_schema(path, "requests secrets or private content")
  end
end
