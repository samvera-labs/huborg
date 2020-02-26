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
end
