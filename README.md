# huborg

Code: [![Version](https://badge.fury.io/rb/huborg.png)](http://badge.fury.io/rb/huborg)

Docs: [![Contribution Guidelines](http://img.shields.io/badge/CONTRIBUTING-Guidelines-blue.svg)](./CONTRIBUTING.md)
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
)
```

The above will create a pull request against all repositories in
"samvera" and "samvera-labs". That pull request will be to the file
named `repository` (in the directory `relative/path/in`). The file's
content will be from the file `/path/to/file/on/your/system`.

## Further Refinements

This example demonstrates the full parameter options:

```ruby
require 'huborg'
require 'logger'

client = Huborg::Client.new(
    org_names: ["samvera", "samvera-labs"]),
    logger: Logger.new(STDOUT),
    github_access_token: "my-super-secret-token",
    repository_pattern: %r{hyrax}i, # Limit to repositories with full name "hyrax"
)
client.push_template!(
  template: "/path/to/file/on/your/system",
  filename: "relative/path/in/repository",
  overwrite: true
)
```

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

## Todo

- [ ] Add method to clone repositories
- [ ] Add method to pull changes from upstream repositories
- [ ] Add method to run stats against local repositories

# Acknowledgments

This software has been developed by and is brought to you by the Samvera community.  Learn more at the
[Samvera website](http://samvera.org/).

![Samvera Logo](https://wiki.lyrasis.org/download/thumbnails/87459292/samvera-fall-font2-200w.png?version=1&modificationDate=1498550535816&api=v2)
