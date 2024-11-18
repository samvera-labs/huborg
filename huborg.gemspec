# frozen_string_literal: true

require_relative 'lib/huborg/version'

Gem::Specification.new do |spec|
  spec.name          = 'huborg'
  spec.version       = Huborg::VERSION
  spec.authors       = ['Jeremy Friesen']
  spec.email         = ['jeremy.n.friesen@gmail.com']

  spec.summary       = 'Make changes to Organization Repositories en-masse.'
  spec.description   = 'Make changes to Organization Repositories en-masse.'
  spec.homepage      = 'https://github.com/samvera-labs/huborg/'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.7')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/samvera-labs/huborg/'
  spec.metadata['changelog_uri'] = 'https://github.com/samvera-labs/huborg/blob/master/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://www.rubydoc.info/gems/huborg/'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.add_dependency 'git', '~> 1.6'
  spec.add_dependency 'octokit', '~> 4.16'
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'github_changelog_generator'
  spec.add_development_dependency 'rubocop'
end
