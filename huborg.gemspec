require_relative 'lib/huborg/version'

Gem::Specification.new do |spec|
  spec.name          = "huborg"
  spec.version       = Huborg::VERSION
  spec.authors       = ["Jeremy Friesen"]
  spec.email         = ["jeremy.n.friesen@gmail.com"]

  spec.summary       = %q{Make changes to Organization Repositories en-masse.}
  spec.description   = %q{Make changes to Organization Repositories en-masse.}
  spec.homepage      = "https://github.com/samvera-labs/huborg/"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/samvera-labs/huborg/"
  spec.metadata["changelog_uri"] = "https://github.com/samvera-labs/huborg/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_dependency "octokit", "~> 4.16"
end
