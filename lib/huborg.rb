require "huborg/version"
require 'octokit'
require 'git'
require 'fileutils'

module Huborg
  class Error < RuntimeError; end

  # The class that interacts with organizational repositories.
  #
  # * {#push_template!} - push a file to all repositories
  # * {#clone_and_rebase!} - download all repositories for the org
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
    # @see https://github.com/octokit/octokit.rb#oauth-access-tokens for OAuth Tokens
    # @see https://developer.github.com/v3/repos/#list-organization-repositories for repository data structures
    def initialize(logger: default_logger, github_access_token: default_access_token, org_names:, repository_pattern: DEFAULT_REPOSITORY_PATTERN)
      @logger = logger
      @client = Octokit::Client.new(access_token: github_access_token)
      @org_names = Array(org_names)
      @repository_pattern = repository_pattern
    end

    private

    attr_reader :client, :logger, :org_names, :repository_pattern

    def default_logger
      require 'logger'
      Logger.new(STDOUT)
    end

    def default_access_token
      ENV.fetch('GITHUB_ACCESS_TOKEN')
    rescue KeyError => e
      message = "You need to provide an OAuth Access Token.\nSee: https://github.com/octokit/octokit.rb#oauth-access-tokens"
      $stderr.puts message
      raise Error.new(message)
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
    #
    # @example
    #    client = Huborg::Client.new(
    #      github_access_token: ENV.fetch("GITHUB_ACCESS_TOKEN"),
    #      org_names: ENV.fetch("GITHUB_ORG_NAME")
    #    )
    #    client.push_template!(
    #      template: "/path/to/file/on/your/system",
    #      filename: "relative/path/in/repository"
    #    )
    # @return [True] if successfully completed
    def push_template!(template:, filename:, overwrite: false)
      each_github_repository do |repo|
        push_template_to!(repo: repo, template: template, filename: filename, overwrite: overwrite)
      end
      true
    end

    # @api public
    #
    # Clone all repositories (that match the {#repository_pattern} for
    # the given organization(s). Then and rebase any existing repositories.
    #
    # @param directory [String] the directory in which to clone the repositories
    #        (as a sub-directory)
    # @param skip_dirty [Boolean] if the repository already exists there, don't
    #        clone or pull down changes
    # @param force [Boolean] if we want to obliterate any changes in an existing
    #        repository
    # @param shallow [Boolean] when true, instead of cloning into a
    #        subdirectory of `org/repo`, clone into `repo`.
    # @param skip_forked [Boolean] when true, don't clone a repository that is
    #        a fork of some other repository.
    # @param skip_archived [Boolean] when true, don't clone a repository that is
    #        archived on Github.
    # @note The Product Owner decided to set `shallow: false` as the default, as
    #       other local scripts run by them made use of those directory
    #       structures.
    #
    # @example
    #    client = Huborg::Client.new(
    #      github_access_token: ENV.fetch("GITHUB_ACCESS_TOKEN"),
    #      org_names: ENV.fetch("GITHUB_ORG_NAME")
    #    )
    #    directory = ENV.fetch("DIRECTORY") { File.join(ENV.fetch("HOME"), "git") }
    #    client.clone_and_rebase!(directory: directory)
    #
    # Let's say we have a Github Organization "penguin" which has the
    # repositories "paradigm" and "raft". In the above example, if we
    # specified the `DIRECTORY` as "/Iceflow", we would end up with the
    # following local directory tree within /Iceflow:
    #    .
    #    └── penguin
    #        ├── paradigm
    #        └── raft
    #
    # In the case of `shallow: true`, we would have the following tree within
    # /Iceflow:
    #    .
    #    ├── paradigm
    #    └── raft
    #
    # @return [True] if successfully completed
    def clone_and_rebase!(directory:, skip_forked: false, skip_archived: false, skip_dirty: true, force: false, shallow: false)
      each_github_repository do |repo|
        next if skip_archived && repo.archived?
        next if skip_forked && repo.fork?
        clone_and_rebase_one!(repo: repo, directory: directory, skip_dirty: skip_dirty, force: force, shallow: shallow)
      end
      true
    end

    private

    # Fetch all of the repositories for the initialized :org_names that
    # match the initialized :repository_pattern
    #
    # @yield [Oktokit::Repository] each repository will be yielded
    # @yieldparam [Oktokit::Repository]
    # @see https://developer.github.com/v3/repos/#list-organization-repositories
    #      for the response document
    # @return [True]
    def each_github_repository(&block)
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

    def clone_and_rebase_one!(repo:, directory:, skip_dirty: true, force: false, shallow: false)
      repo_path = shallow ? File.join(directory, repo.name) : File.join(directory, repo.full_name)
      if File.directory?(repo_path)
        # We already have a directory (hopefully its a git repository)
        git = Git.open(repo_path)
        if force
          logger.info("Forcing and reseting to a clean #{repo_path}")
          # force clean and remove whole directories that are untracked
          git.clean(force: true, d: true)
          # reset any changed files to original state
          git.reset(hard: true)
        elsif git.status.changed.any? || git.status.added.any? || git.status.deleted.any?
          # The repository is dirty but should we skip dirty
          if skip_dirty
            logger.info("Skipping #{repo.full_name} as it has a dirty git index")
            return
          else
            logger.info("Staching changes on #{repo_path}")
            # We'll offer a kindness and stash everything
            git.add('.', all: true)
            git.branch.stashes.save("Stashing via #{self.class}#clone_and_rebase!")
          end
        end
        git.branch("master").checkout
        logger.info("Pulling down master branch from origin for #{repo_path}")
        git.pull("origin", "master")
      else
        parent_directory = File.dirname(repo_path)
        logger.info("Creating #{parent_directory}")
        FileUtils.mkdir_p(parent_directory)
        # We don't have a repository in the given path, so make one
        logger.info("Cloning #{repo.name} into #{parent_directory}")
        Git.clone(repo.clone_url, repo.name, path: parent_directory)
        logger.info("Finished cloning #{repo.name} into #{parent_directory}")
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
