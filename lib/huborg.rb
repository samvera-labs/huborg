# frozen_string_literal: true

require 'huborg/version'
require 'octokit'
require 'git'
require 'fileutils'
require 'set'

# A module for interacting with Github organizations
module Huborg
  # If there's a problem with Huborg, expect to see this error OR an
  # error from an underlying library.
  class Error < RuntimeError; end

  # The class that interacts with organizational repositories.
  #
  # * {#push_template!} - push a file to all repositories
  # * {#clone_and_rebase!} - download all repositories for the org
  # * {#audit_license} - tooling to check the licenses of your org
  # * {#synchronize_mailmap!} - ensure all git .mailmap files are
  #   synchronized

  # rubocop:disable Metrics/ClassLength
  class Client
    # When listing repositories, this callable will return all repositories.
    # @see #initialize `#initialize` for details on the repository filter.
    DEFAULT_REPOSITORY_FILTER = ->(_client, _repo) { true }

    # @since v0.1.0
    #
    # @param logger [Logger] used in logging output of processes
    # @param github_access_token [String] used to connect to the Octokit::Client.
    #        The given token will need to have permission to interact with
    #        repositories. Defaults to ENV["GITHUB_ACCESS_TOKEN"]
    # @param org_names [Array<String>, String] list of GitHub organizations
    #        Huborg will act on
    # @param repository_filter [Proc<Octokit::Client,Octokit::Repository>] filter
    #        the list of repositories to those for those which the callable returns
    #        true; defaults to ALL
    #
    # @example
    #   # Without configuration options. You'll want ENV["GITHUB_ACCESS_TOKEN"]
    #   # to be assigned.
    #   client = Huborg::Client.new(org_names: ["samvera", "samvera-labs"])
    #
    #   # With explicit configuration options. Note, we'll be interacting only
    #   # with repositories that contain the case-insensitive word "hyrax" (case-
    #   # insensitivity is declared as the `i` at the end of the regular
    #   # expression).
    #   client = Huborg::Client.new(
    #     logger: Logger.new(STDOUT),
    #     github_access_token: "40-random-characters-for-your-token",
    #     org_names: ["samvera", "samvera-labs"],
    #     repository_filter: ->(client, repo) { repo.full_name.match?(/.*hyrax.*/) }
    #   )
    #
    # rubocop:disable Layout/LineLength
    # @see https://github.com/octokit/octokit.rb#oauth-access-tokens Octokit's documentation for OAuth Tokens
    # @see https://developer.github.com/v3/repos/#list-organization-repositories Github's documentation for repository data structures
    # rubocop:enable Layout/LineLength

    def initialize(org_names:,
                   logger: default_logger,
                   github_access_token: default_access_token,
                   repository_filter: DEFAULT_REPOSITORY_FILTER)
      @org_names = Array(org_names)
      @logger = logger
      @client = Octokit::Client.new(access_token: github_access_token)
      @repository_filter = repository_filter
    end

    private

    attr_reader :client, :logger, :org_names, :repository_filter

    def default_logger
      require 'logger'
      Logger.new($stdout)
    end

    def default_access_token
      ENV.fetch('GITHUB_ACCESS_TOKEN')
    rescue KeyError
      message = "You need to provide an OAuth Access Token.\nSee: https://github.com/octokit/octokit.rb#oauth-access-tokens"
      warn message
      raise Error, message
    end

    public

    # @api public
    # @since v0.1.0
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
    # @since v0.2.0
    #
    # Responsible for logging (as an error) repositories that do not
    # have a license.
    #
    # @param skip_private [Boolean] do not check private repositories for a
    #        license
    # @param skip_archived [Boolean] do not check archived repositories
    #        for license
    # @param allowed_licenses [Array<String>, :all] the licenses which are
    #        allowed, in all other cases, log as an error. This checks
    #        the :key of a license object in Github's API (see
    #        https://api.github.com/licenses)
    #
    # @see https://api.github.com/licenses Github's documentation for a list of license keys
    # @return [True] the task completed without exception (there may be
    #         logged errors)

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/PerceivedComplexity
    def audit_license(skip_private: true, skip_archived: true, allowed_licenses: :all)
      license_list = Array(allowed_licenses)
      each_github_repository do |repo|
        next if skip_private && repo.private?
        next if skip_archived && repo.archived?

        if repo.license
          logger.info(%(#{repo.fullname} has "#{repo.license.key}"))
          next if allowed_licenses == :all
          next if license_list.include?(repo.license.key)

          logger.error(%(#{repo.full_name} has "#{repo.license.key}" which is not in #{license_list.inspect}))
        else
          logger.error("#{repo.full_name} is missing a license")
        end
      end
      true
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/PerceivedComplexity

    # @api public
    # @since v0.2.0
    #
    # Responsible for taking a template that confirms to Git's .mailmap
    # file format (e.g. https://github.com/samvera/maintenance/blob/master/templates/MAILMAP)
    # and adding in all .mailmap entries that exist within the
    # organizations repositories. This merged .mailmap is then pushed
    # out, via a pull request, to all of the non-archived repositories.
    #
    # @param template [String] path to the source template for .mailmap
    #        This does assume that there were prior efforts at
    #        consolidating a .mailmap file. If you don't have this,
    #        pass an empty file.
    # @param consolidated_template [String] path that we will write our
    #        changes, this file will be pushed to all non-archived
    #        repositories
    # @return [True] if successfully completed
    # @see https://www.git-scm.com/docs/git-check-mailmap Git's documentation
    #      for more on git's .mailmap file
    # @todo Ensure that this doesn't create a pull request if nothing
    #       has changed.

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def synchronize_mailmap!(template:, consolidated_template: template)
      mailmap_lines = Set.new
      File.read(template).split("\n").each do |line|
        mailmap_lines << line unless line.empty?
      end

      each_github_repository do |repo|
        mailmap = client.contents(repo.full_name, path: '.mailmap')
        lines = mailmap.rels[:download].get.data
        lines.split("\n").each do |line|
          mailmap_lines << line
        end
      rescue Octokit::NotFound
        next
      end

      # Write the contents to a file
      File.open(consolidated_template, 'w+') do |file|
        mailmap_lines.to_a.sort.each do |line|
          file.puts line
        end
      end

      each_github_repository do |repo|
        next if repo.archived?

        push_template_to!(filename: '.mailmap', template: consolidated_template, repo: repo, overwrite: true)
      end

      true
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    # @api public
    # @since v0.2.0
    #
    # Clone all repositories (that match the {#repository_filter} for
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
    # rubocop:disable Metrics/ParameterLists
    def clone_and_rebase!(directory:, skip_forked: false, skip_archived: false, skip_dirty: true, force: false,
                          shallow: false)
      each_github_repository do |repo|
        next if skip_archived && repo.archived?
        next if skip_forked && repo.fork?

        clone_and_rebase_one!(repo: repo, directory: directory, skip_dirty: skip_dirty, force: force, shallow: shallow)
      end
      true
    end
    # rubocop:enable Metrics/ParameterLists

    # @api public
    # @since v0.3.0
    #
    # Yield each pull request, and associated repository that matches the given
    # parameters
    #
    # @param skip_archived [Boolean] skip any archived projects
    # @param query [Hash] the query params to use when selecting pull requests
    #
    # @yieldparam [Octokit::PullRequest] responds to #created_at, #title, #html_url, etc
    # @yieldparam [Octokit::Repository] responds to #full_name
    #
    # @example
    #   require 'huborg'
    #   client = Huborg::Client.new(org_names: ["samvera", "samvera-labs"])
    #   File.open(File.join(ENV["HOME"], "/Desktop/pull-requests.tsv"), "w+") do |file|
    #     file.puts "REPO_FULL_NAME\tPR_CREATED_AT\tPR_URL\tPR_TITLE"
    #     client.each_pull_request_with_repo do |pull, repo|
    #       file.puts "#{repo.full_name}\t#{pull.created_at}\t#{pull.html_url}\t#{pull.title}"
    #     end
    #   end
    #
    # @see https://developer.github.com/v3/pulls/#list-pull-requests
    def each_pull_request_with_repo(skip_archived: true, query: { state: :open })
      each_github_repository do |repo|
        next if skip_archived && repo.archived?

        fetch_rel_for(rel: :pulls, from: repo, query: query).each do |pull|
          yield(pull, repo)
        end
      end
      true
    end

    # @api public
    # @since v0.4.0
    #
    # List every repository that will be acted upon. This is primarily to
    # provide extra assurance to the user.
    #
    # @yieldparam [Octokit::Repository] responds to #full_name
    #
    # @example
    #   require 'huborg'
    #   client = Huborg::Client.new(
    #     org_names: ["samvera", "samvera-labs"],
    #     repository_filter: ->(client, repo) {
    #       ['infrastructure', 'gem'].all? { |topic|
    #         client.topics(repo.full_name, accept: Octokit::Preview::PREVIEW_TYPES[:topics])[:names].include?(topic)
    #       }
    #     }
    #   )
    #   client.list_repositories do |repo|
    #     puts repo.full_name
    #   end
    #
    # @see https://developer.github.com/v3/repos/#list-organization-repositories
    #      for the response document
    #
    # @return [True]
    def list_repositories(&block)
      each_github_repository(&block)

      true
    end

    private

    # Fetch all of the repositories for the initialized :org_names for which
    # the initialized :repository_filter returns true
    #
    # @yield [Octokit::Repository] each repository will be yielded
    # @yieldparam [Octokit::Repository]
    # @see https://developer.github.com/v3/repos/#list-organization-repositories
    #      for the response document
    # @return [True]
    def each_github_repository(&block)
      # Collect all repositories
      repos = []
      org_names.each do |org_name|
        org = client.org(org_name)
        repos += fetch_rel_for(rel: :repos, from: org)
      end

      repos.each do |repo|
        next unless repository_filter.call(client, repo)

        block.call(repo)
      end

      true
    end

    # @note Due to an implementation detail in octokit.rb, refs sometimes
    #       need to be "heads/<branch>" and "refs/heads/<branch>" as detailed
    #       below
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

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def push_template_to!(repo:, template:, filename:, overwrite: false)
      return if repo.archived

      # NOTE: Sometimes I'm using "heads/<default>" and other times I'm using
      #       "refs/heads/<default>". There appears to be an inconsistency in
      #       the implementation of octokit.
      default_branch = client.ref(repo.full_name, "heads/#{repo.default_branch}")
      filename_ref_on_default_branch = begin
        # I have seen both a return value of nil or seen raised an Octokit::NotFound
        # exception (one for a file at root, the other for a file in a non-existent
        # directory)
        client.contents(repo.full_name, path: filename)
      rescue Octokit::NotFound
        nil
      end
      commit_message = "Adding/updating #{filename}\n\nThis was uploaded via automation."
      logger.info("Creating pull request for #{filename} on #{repo.full_name}")
      target_branch_name = "refs/heads/autoupdate-#{Time.now.utc.to_s.gsub(/\D+/, '')}"
      if filename_ref_on_default_branch
        return unless overwrite

        client.create_reference(repo.full_name, target_branch_name, default_branch.object.sha)
        client.update_contents(
          repo.full_name,
          filename,
          commit_message,
          filename_ref_on_default_branch.sha,
          file: File.new(template, 'r'),
          branch: target_branch_name
        )
      else
        client.create_reference(repo.full_name, target_branch_name, default_branch.object.sha)
        client.create_contents(
          repo.full_name,
          filename,
          commit_message,
          file: File.new(template, 'r'),
          branch: target_branch_name
        )
      end
      client.create_pull_request(repo.full_name, "refs/heads/#{repo.default_branch}", target_branch_name,
                                 commit_message)
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/PerceivedComplexity
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
        git.branch(repo.default_branch).checkout
        logger.info("Pulling down #{repo.default_branch} branch from origin for #{repo_path}")
        git.pull('origin', repo.default_branch)
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
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/PerceivedComplexity

    # Responsible for fetching an array of the given :rel
    #
    # @param rel [Symbol] The name of the related object(s) for the
    #        given org
    # @param from [Object] The receiver of the rels method call. This could be
    #        but is not limited to an Octokit::Organization or
    #        Octokit::Repository.
    #
    # @return [Array<Object>]

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def fetch_rel_for(rel:, from:, query: {})
      # Build a list of repositories, note per Github's API, these are
      # paginated.
      from_to_s = from.respond_to?(:name) ? from.name : from.to_s
      # rubocop:disable Layout/LineLength
      logger.info "Fetching rels[#{rel.inspect}] for '#{from_to_s}' with filter #{repository_filter.inspect}, and query #{query.inspect}"
      # rubocop:enable Layout/LineLength
      source = from.rels[rel].get(query)
      rels = []
      while source
        rels += source.data
        source = source.rels[:next]&.get(query)
      end
      # rubocop:disable Layout/LineLength
      logger.info "Finished fetching rels[#{rel.inspect}] for '#{from_to_s}' with filter #{repository_filter.inspect}, and query #{query.inspect}"
      # rubocop:enable Layout/LineLength
      return rels unless block_given?

      rels
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
  end
  # rubocop:enable Metrics/ClassLength
end
