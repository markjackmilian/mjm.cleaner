#!/usr/bin/env ruby

require "yaml"

root = File.expand_path("../..", __dir__)
workflow = YAML.load_file(File.join(root, ".github/workflows/release-macos.yml"))
triggers = workflow["on"] || workflow[true]
jobs = workflow.fetch("jobs")

raise "workflow_dispatch trigger missing" unless triggers.key?("workflow_dispatch")

release_tag = triggers.fetch("workflow_dispatch")
                      .fetch("inputs")
                      .fetch("release_tag")
raise "release_tag must be required" unless release_tag["required"] == true

raise "contents write permission missing" unless workflow.dig("permissions", "contents") == "write"

release = jobs.fetch("release")
raise "release must wait for both packages" unless release["needs"] == "package"

steps = release.fetch("steps")
raise "release artifact download missing" unless steps.any? do |step|
  step["uses"]&.start_with?("actions/download-artifact@")
end

publish = steps.find { |step| step["name"] == "Publish GitHub release" }
raise "release publishing step missing" unless publish
raise "GH_TOKEN missing" unless publish.dig("env", "GH_TOKEN")
raise "GH_REPO missing" unless publish.dig("env", "GH_REPO")
raise "release command missing" unless publish["run"]&.include?("gh release")

puts "release workflow tests: PASS"
