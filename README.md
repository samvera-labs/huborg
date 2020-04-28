# huborg

Code: [![Version](https://badge.fury.io/rb/huborg.svg)](https://rubygems.org/gems/huborg)

Docs: [![Code Documentation](https://img.shields.io/badge/CODE-Documentation-blue.svg)](https://www.rubydoc.info/gems/huborg/) [![Contribution Guidelines](http://img.shields.io/badge/CONTRIBUTING-Guidelines-blue.svg)](./CONTRIBUTING.md)
[![Apache 2.0 License](http://img.shields.io/badge/APACHE2-license-blue.svg)](./LICENSE)

Jump in: [![Slack Status](http://slack.samvera.org/badge.svg)](http://slack.samvera.org/)

# What is huborg?

The `huborg` gem is a set of Ruby classes that help script interactions with
repositories within an organization (or organizations).

## Product Owner & Maintenance

The `huborg` gem is **NOT** a Core Component of the Samvera community. The documentation for
what we mean by Core Component can be found
[here](http://samvera.github.io/core_components.html#requirements-for-a-core-component).

### Product Owner

[jeremyf](https://github.com/jeremyf)

# Help

The Samvera community is here to help. Please see our [support guide](./SUPPORT.md).

# Getting Started

You'll need the `huborg` gem:

* Install via `gem install huborg` **or**
* Add it to your Gemfile: `gem "huborg"`

## The Basics

```ruby
require 'huborg'

# NOTE: You will need to include GITHUB_ACCESS_TOKEN in your ENV
client = Huborg::Client.new(org_names: ["samvera", "samvera-labs"])
# This command will push the given template to each repository in the above
# organizations. By default it will not overwrite existing files.
client.push_template!(
  template: "/path/to/file/on/your/system",
  filename: "relative/path/in/repository"

# This will clone all repositories from samvera and samvera-labs.
# You can expect to see something in `~/git/samvera/hyrax` and
# `~/git/samvera-labs/huborg`
client.clone_and_rebase!(
  directory: File.join(ENV["HOME"], "git")
)
```

The above will create a pull request against all repositories in
"samvera" and "samvera-labs". That pull request will be to the file
named `repository` (in the directory `relative/path/in`). The file's
content will be from the file `/path/to/file/on/your/system`.

```ruby
require 'huborg'

# NOTE: You will need to include GITHUB_ACCESS_TOKEN in your ENV
client = Huborg::Client.new(org_names: ["samvera", "samvera-labs"])
client.clone_and_rebase!(
  directory: File.join(ENV["HOME"], "git")
)
```

The above will clone and rebase all repositories from samvera and
samvera-labs. The script will skip existing repositories. You can
expect to see [Hyrax](https://github.com/samvera/hyrax) cloned into
`~/git/samvera/hyrax` and [Huborg](https://github.com/samvera-labs/huborg)
cloned into `~/git/samvera-labs/huborg`

```ruby
require 'huborg'
# NOTE: You will need to include GITHUB_ACCESS_TOKEN in your ENV
client = Huborg::Client.new(org_names: ["samvera"])
client.audit_license
```

The above script leverages Github's API to check each repository's
license. Log as an error each repository that does not have a license.

```ruby
require 'huborg'
# NOTE: You will need to include GITHUB_ACCESS_TOKEN in your ENV
client = Huborg::Client.new(org_names: ["samvera"])
client.synchronize_mailmap!(template: '/path/to/my/MAILMAP_TEMPLATE')
```

The above will take the given template (which confirms to [Git's .mailmap
file format](https://www.git-scm.com/docs/git-check-mailmap), then
iterates on all of the repositories, adding any non-duplicates, then
writing back to the template before creating pull requests against
each of the organization's non-archived repositories.

```ruby
require 'huborg'
# NOTE: You will need to include GITHUB_ACCESS_TOKEN in your ENV
client = Huborg::Client.new(org_names: ["samvera", "samvera-labs"])
File.open(File.join(ENV["HOME"], "/Desktop/pull-requests.tsv"), "w+") do |file|
  file.puts "REPO_FULL_NAME\tPR_CREATED_AT\tPR_URL\tPR_TITLE"
  client.each_pull_request_with_repo do |pull, repo|
    file.puts "#{repo.full_name}\t#{pull.created_at}\t#{pull.html_url}\t#{pull.title}"
  end
end
```

The above will write a tab separated file of all of the open pull requests for
the non-archived samvera and samvera-labs repositories.

**All of the commands have several parameters, many set to default values.**

## Prerequisites

You'll want to have created a [Github OAuth Access Token](https://github.com/octokit/octokit.rb#oauth-access-tokens).

## Hey, Where Are The Repository Tests?

Great question. The product owner has chosen not to write the tests as the
tests would be a preposterous amount of mocks and stubs. The product owner
recommends that you, intrepid developer, create a Github organization of your
own and add a few repositories to play against. That is what the product owner
did, and will be how they test the `huborg` gem going forward.

You, dear intrepid developer, can use the rake task `test:push_template` and
look at your organization's repositories to see the pull request. The product
owner used the following:

```console
$ export GITHUB_ACCESS_TOKEN=their-github-token
$ export GITHUB_ORG_NAME=their-organization
$ bundle exec rake test:push_template
```

## Documentation

The product owner encourages you to clone this repository and generate the
documentation.

- [ ] `git clone https://github.com/samvera-labs/huborg`
- [ ] `cd huborg`
- [ ] `git checkout master && git pull --rebase`
- [ ] `gem install yard`
- [ ] `yard`

The above process will generate documentation in `./doc`. Open `./doc/index.html`
in your browser. (On OSX, try `open ./doc/index.html`).

## Releasing Huborg

Huborg uses [Semantic Versioning](https://semver.org/).

Below is the checklist:

- [ ] An internet connection
- [ ] A [Github Access Token](https://developer.github.com/apps/building-oauth-apps/authorizing-oauth-apps/)
- [ ] Your access token exported to `ENV["CHANGELOG_GITHUB_TOKEN"]`
- [ ] Verify you are a [huborg gem owner](https://rubygems.org/gems/huborg). If not, Samvera uses
      [`grant_revoke_gem_authority`](https://github.com/samvera/maintenance/blob/master/script/grant_revoke_gem_authority.rb)
      to manage the gem owners.
- [ ] Verify that you can push changes to https://github.com/samvera-labs/huborg
- [ ] Check that you have a clean git index
- [ ] Pull down the latest version of master
- [ ] Update the Huborg::VERSION (in ./lib/huborg/version.rb); Remember, huborg
      uses [Semantic Versioning](https://semver.org). (_**NOTE:** Do not commit the version change_)
      - [ ] To give some insight on what version to use, you can use `yard diff`. With a clean master branch, run `yard`. Then run `yard diff huborg-<Huborg::VERSION> .yardoc` (where Huborg::VERSION is something like 0.1.0 and `.yarddoc` is the output directory of `yard`).
- [ ] Run `bundle exec rake changelog` to generate [CHANGELOG.md](./CHANGELOG.md)
- [ ] Review the new Huborg::VERSION CHANGELOG.md entries as they might prompt
      you to consider a different version (e.g. what you thought was a bug fix
      release is in fact a minor version release). Look at the changelog from
      the perspective of a person curious about using this gem.
- [ ] Commit your changes with a simple message: "Bumping to v#{Huborg::VERSION}"
- [ ] Run `bundle exec rake release`

# Acknowledgments

This software has been developed by and is brought to you by the Samvera community.  Learn more at the
[Samvera website](http://samvera.org/).

![Samvera Logo](https://wiki.lyrasis.org/download/thumbnails/87459292/samvera-fall-font2-200w.png?version=1&modificationDate=1498550535816&api=v2)
