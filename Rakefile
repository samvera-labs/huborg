require "bundler/gem_tasks"

namespace :test do
  desc "Push template to organization (set ENV[GITHUB_ACCESS_TOKEN] and ENV[GITHUB_ORG_NAME])"
  task :push_template do
    require 'huborg'
    client = Huborg::Client.new(
      github_access_token: ENV.fetch("GITHUB_ACCESS_TOKEN"),
      org_names: ENV.fetch("GITHUB_ORG_NAME")
    )
    client.push_template!(
      template: __FILE__,
      filename: "disposable-#{Time.now.utc.to_s.gsub(/\D+/,'')}.rake"
    )
  end

  task :clone_and_rebase do
    require 'huborg'
    client = Huborg::Client.new(
      github_access_token: ENV.fetch("GITHUB_ACCESS_TOKEN"),
      org_names: ENV.fetch("GITHUB_ORG_NAME")
    )
    directory = ENV.fetch("DIRECTORY") { File.join(ENV.fetch("HOME"), "git") }
    client.clone_and_rebase!(directory: directory)
  end

  task :audit_license do
    require 'huborg'
    client = Huborg::Client.new(
      github_access_token: ENV.fetch("GITHUB_ACCESS_TOKEN"),
      org_names: ENV.fetch("GITHUB_ORG_NAME")
    )
    client.audit_license
  end

  task :mailmap do
    require 'huborg'
    client = Huborg::Client.new(
      github_access_token: ENV.fetch("GITHUB_ACCESS_TOKEN"),
      org_names: ENV.fetch("GITHUB_ORG_NAME")
    )
    client.synchronize_mailmap!(template: ENV.fetch("MAILMAP_TEMPLATE_FILENAME"))
  end
end


require 'github_changelog_generator/task'
desc "Generate CHANGELOG.md based on lib/huborg/version.md (change that to the new version before you run rake changelog)"
GitHubChangelogGenerator::RakeTask.new :changelog do |config|
  begin
    ENV.fetch("CHANGELOG_GITHUB_TOKEN")
  rescue KeyError
    $stderr.puts %(To run `rake changelog` you need to have a CHANGELOG_GITHUB_TOKEN)
    $stderr.puts %(set in ENV. (`export CHANGELOG_GITHUB_TOKEN="«your-40-digit-github-token»"`))
    exit!(1)
  end
  config.user = 'samvera-labs'
  config.project = 'huborg'
  config.since_tag = 'v0.1.0' # The changes before v0.1.0 were not as helpful
  config.future_release = %(v#{ENV.fetch("FUTURE_RELEASE", Huborg::VERSION)})
  config.base = 'CHANGELOG.md'
end
