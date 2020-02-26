require "huborg/version"
require 'octokit'

module Huborg
  class Error < RuntimeError; end

  # The class that interacts with organizational repositories
  class Client

    # Match all repositories
    DEFAULT_REPOSITORY_PATTERN = %r{\A.*\Z}

    # @param logger [Logger] used in logging output of processes
    # @param github_access_token [String] used to connect to the Oktokit::Client.
    #        The given token will need to have permission to interact with
    #        repositories. Defaults to ENV["GITHUB_ACCESS_TOKEN"]
    # @param org_names [Array<String>] used as the default list of Github organizations
    #        in which we'll interact.
    # @param repository_pattern [Regexp] limit the list of repositories to the given pattern; defaults to ALL
    #
    # @see https://github.com/octokit/octokit.rb#oauth-access-tokens
    def initialize(logger: default_logger, github_access_token: default_access_token, org_names:, repository_pattern: DEFAULT_REPOSITORY_PATTERN)
      @logger = logger
      @client = Octokit::Client.new(access_token: github_access_token)
      @org_names = Array(org_names)
      @repository_pattern = repository_pattern
    end
    attr_reader :client, :logger, :org_names, :repository_pattern

    private

    def default_logger
      require 'logger'
      Logger.new(STDOUT)
    end

    def default_access_token
      ENV.fetch('GITHUB_ACCESS_TOKEN')
    rescue KeyError => e
      $stderr.puts "You need to provide an OAuth Access Token.\nSee: https://github.com/octokit/octokit.rb#oauth-access-tokens"
      raise e
    end

    public

    # @api public
    #
    # Responsible for pushing the given template file to all of the
    # organizations repositories. As we are pushing changes to
    # repositories, this process will skip archived repositories.
    #
    # @note This skips archived repositories
    #
    # @param template [String] name of the template to push out to all
    #        repositories
    # @param filename [String] where in the repository should we write
    #        the template. This is a relative pathname, each directory
    #        and filename.
    # @param overwrite [Boolean] because sometimes you shouldn't
    #        overwrite what already exists. In the case of a LICENSE, we
    #        would not want to do that. In the case of a .mailmap, we
    #        would likely want to overwrite.
    # @todo  Verify that the template exists
    def push_template!(template:, filename:, overwrite: false)
      each_repository do |repo|
        push_template_to!(repo: repo, template: template, filename: filename, overwrite: overwrite)
      end
    end

    # @api private
    # @note API Private as this is not yet used.
    #
    # Fetch all of the repositories for the initialized :org_names that
    # match the initialized :repository_pattern
    #
    # @yield if given, yield a Oktokit::Repository object for each
    #        repository
    # @yieldparam A raw Oktokit::Repository object
    # @return [True]
    def each_repository(&block)
      # Collect all repositories
      repos = []
      org_names.each do |org_name|
        org = client.org(org_name)
        repos += fetch_rel_for(rel: :repos, org: org)
      end

      repos.each do |repo|
        block.call(repo) if repository_pattern.match?(repo.full_name)
      end
      return true
    end

    private

    # @note Due to an implementation detail in octokit.rb, refs sometimes
    # need to be "heads/master" and "refs/heads/master" as detailed
    # below
    # @param repo [#full_name, #archived] Likely the result of Octokit::Client#org
    # @param template [String] name of the template to push out to all
    #        repositories
    # @param filename [String] where in the repository should we write
    #        the template. This is a relative pathname, each directory
    #        and filename.
    # @param overwrite [Boolean] because sometimes you shouldn't
    #        overwrite what already exists. In the case of a LICENSE, we
    #        would not want to do that. In the case of a .mailmap, we
    #        would likely want to overwrite.
    def push_template_to!(repo:, template:, filename:, overwrite: false)
      return if repo.archived
      # Note: Sometimes I'm using "heads/master" and other times I'm using
      #       "refs/heads/master". There appears to be an inconsistency in
      #       the implementation of octokit.
      master = client.ref(repo.full_name, "heads/master")
      copy_on_master = begin
        # I have seen both a return value of nil or seen raised an Octokit::NotFound
        # exception (one for a file at root, the other for a file in a non-existent
        # directory)
        client.contents(repo.full_name, path: filename)
      rescue Octokit::NotFound
        nil
      end
      commit_message = "Adding #{filename}\n\nThis was uploaded via automation."
      logger.info("Creating pull request for #{filename} on #{repo.full_name}")
      target_branch_name = "refs/heads/autoupdate-#{Time.now.utc.to_s.gsub(/\D+/,'')}"
      if copy_on_master
        return unless overwrite
        branch = client.create_reference(repo.full_name, target_branch_name, master.object.sha)
        client.update_contents(
          repo.full_name,
          filename,
          commit_message,
          copy_on_master.sha,
          file: File.new(template, "r"),
          branch: target_branch_name
        )
        client.create_pull_request(repo.full_name, "refs/heads/master", target_branch_name, commit_message)
      else
        branch = client.create_reference(repo.full_name, target_branch_name, master.object.sha)
        client.create_contents(
          repo.full_name,
          filename,
          commit_message,
          file: File.new(template, "r"),
          branch: target_branch_name
        )
        client.create_pull_request(repo.full_name, "refs/heads/master", target_branch_name, commit_message)
      end
    end

    # Responsible for fetching an array of the given :rel
    #
    # @param rel [Symbol] The name of the related object(s) for the
    #        given org
    # @param org [Object] An Organization object (provided by Oktokit
    #        object) from which this method fetchs the related :rel

    # @return [Array<Object>]
    def fetch_rel_for(rel:, org:)
      # Build a list of repositories, note per Github's API, these are
      # paginated.
      logger.info "Fetching rels[#{rel.inspect}] for '#{org.login}' with pattern #{repository_pattern.inspect}"
      source = org.rels[rel].get
      rels = []
      while source
        rels += source.data
        if source.rels[:next]
          source = source.rels[:next].get
        else
          source = nil
        end
      end
      rels
      logger.info "Finished rels[#{rel.inspect}] for '#{org.login}' with pattern #{repository_pattern.inspect}"
      if block_given?
        rels
      else
        return rels
      end
    end
  end
end
