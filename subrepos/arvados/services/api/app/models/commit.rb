# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'request_error'

class Commit < ActiveRecord::Base
  extend CurrentApiClient

  class GitError < RequestError
    def http_status
      422
    end
  end

  def self.git_check_ref_format(e)
    if !e or e.empty? or e[0] == '-' or e[0] == '$'
      # definitely not valid
      false
    else
      `git check-ref-format --allow-onelevel #{e.shellescape}`
      $?.success?
    end
  end

  # Return an array of commits (each a 40-char sha1) satisfying the
  # given criteria.
  #
  # Return [] if the revisions given in minimum/maximum are invalid or
  # don't exist in the given repository.
  #
  # Raise ArgumentError if the given repository is invalid, does not
  # exist, or cannot be read for any reason. (Any transient error that
  # prevents commit ranges from resolving must raise rather than
  # returning an empty array.)
  #
  # repository can be the name of a locally hosted repository or a git
  # URL (see git-fetch(1)). Currently http, https, and git schemes are
  # supported.
  def self.find_commit_range repository, minimum, maximum, exclude
    if minimum and minimum.empty?
      minimum = nil
    end

    if minimum and !git_check_ref_format(minimum)
      logger.warn "find_commit_range called with invalid minimum revision: '#{minimum}'"
      return []
    end

    if maximum and !git_check_ref_format(maximum)
      logger.warn "find_commit_range called with invalid maximum revision: '#{maximum}'"
      return []
    end

    if !maximum
      maximum = "HEAD"
    end

    gitdir, is_remote = git_dir_for repository
    fetch_remote_repository gitdir, repository if is_remote
    ENV['GIT_DIR'] = gitdir

    commits = []

    # Get the commit hash for the upper bound
    max_hash = nil
    git_max_hash_cmd = "git rev-list --max-count=1 #{maximum.shellescape} --"
    IO.foreach("|#{git_max_hash_cmd}") do |line|
      max_hash = line.strip
    end

    # If not found, nothing else to do
    if !max_hash
      logger.warn "no refs found looking for max_hash: `GIT_DIR=#{gitdir} #{git_max_hash_cmd}` returned no output"
      return []
    end

    # If string is invalid, nothing else to do
    if !git_check_ref_format(max_hash)
      logger.warn "ref returned by `GIT_DIR=#{gitdir} #{git_max_hash_cmd}` was invalid for max_hash: #{max_hash}"
      return []
    end

    resolved_exclude = nil
    if exclude
      resolved_exclude = []
      exclude.each do |e|
        if git_check_ref_format(e)
          IO.foreach("|git rev-list --max-count=1 #{e.shellescape} --") do |line|
            resolved_exclude.push(line.strip)
          end
        else
          logger.warn "find_commit_range called with invalid exclude invalid characters: '#{exclude}'"
          return []
        end
      end
    end

    if minimum
      # Get the commit hash for the lower bound
      min_hash = nil
      git_min_hash_cmd = "git rev-list --max-count=1 #{minimum.shellescape} --"
      IO.foreach("|#{git_min_hash_cmd}") do |line|
        min_hash = line.strip
      end

      # If not found, nothing else to do
      if !min_hash
        logger.warn "no refs found looking for min_hash: `GIT_DIR=#{gitdir} #{git_min_hash_cmd}` returned no output"
        return []
      end

      # If string is invalid, nothing else to do
      if !git_check_ref_format(min_hash)
        logger.warn "ref returned by `GIT_DIR=#{gitdir} #{git_min_hash_cmd}` was invalid for min_hash: #{min_hash}"
        return []
      end

      # Now find all commits between them
      IO.foreach("|git rev-list #{min_hash.shellescape}..#{max_hash.shellescape} --") do |line|
        hash = line.strip
        commits.push(hash) if !resolved_exclude or !resolved_exclude.include? hash
      end

      commits.push(min_hash) if !resolved_exclude or !resolved_exclude.include? min_hash
    else
      commits.push(max_hash) if !resolved_exclude or !resolved_exclude.include? max_hash
    end

    commits
  end

  # Given a repository (url, or name of hosted repo) and commit sha1,
  # copy the commit into the internal git repo (if necessary), and tag
  # it with the given tag (typically a job UUID).
  #
  # The repo can be a remote url, but in this case sha1 must already
  # be present in our local cache for that repo: e.g., sha1 was just
  # returned by find_commit_range.
  def self.tag_in_internal_repository repo_name, sha1, tag
    unless git_check_ref_format tag
      raise ArgumentError.new "invalid tag #{tag}"
    end
    unless /^[0-9a-f]{40}$/ =~ sha1
      raise ArgumentError.new "invalid sha1 #{sha1}"
    end
    src_gitdir, _ = git_dir_for repo_name
    unless src_gitdir
      raise ArgumentError.new "no local repository for #{repo_name}"
    end
    dst_gitdir = Rails.configuration.git_internal_dir

    begin
      commit_in_dst = must_git(dst_gitdir, "log -n1 --format=%H #{sha1.shellescape}^{commit}").strip
    rescue GitError
      commit_in_dst = false
    end

    tag_cmd = "tag --force #{tag.shellescape} #{sha1.shellescape}^{commit}"
    if commit_in_dst == sha1
      must_git(dst_gitdir, tag_cmd)
    else
      # git-fetch is faster than pack-objects|unpack-objects, but
      # git-fetch can't fetch by sha1. So we first try to fetch a
      # branch that has the desired commit, and if that fails (there
      # is no such branch, or the branch we choose changes under us in
      # race), we fall back to pack|unpack.
      begin
        branches = must_git(src_gitdir,
                            "branch --contains #{sha1.shellescape}")
        m = branches.match(/^. (\w+)\n/)
        if !m
          raise GitError.new "commit is not on any branch"
        end
        branch = m[1]
        must_git(dst_gitdir,
                 "fetch file://#{src_gitdir.shellescape} #{branch.shellescape}")
        # Even if all of the above steps succeeded, we might still not
        # have the right commit due to a race, in which case tag_cmd
        # will fail, and we'll need to fall back to pack|unpack. So
        # don't be tempted to condense this tag_cmd and the one in the
        # rescue block into a single attempt.
        must_git(dst_gitdir, tag_cmd)
      rescue GitError
        must_pipe("echo #{sha1.shellescape}",
                  "git --git-dir #{src_gitdir.shellescape} pack-objects -q --revs --stdout",
                  "git --git-dir #{dst_gitdir.shellescape} unpack-objects -q")
        must_git(dst_gitdir, tag_cmd)
      end
    end
  end

  protected

  def self.remote_url? repo_name
    /^(https?|git):\/\// =~ repo_name
  end

  # Return [local_git_dir, is_remote]. If is_remote, caller must use
  # fetch_remote_repository to ensure content is up-to-date.
  #
  # Raises an exception if the latest content could not be fetched for
  # any reason.
  def self.git_dir_for repo_name
    if remote_url? repo_name
      return [cache_dir_for(repo_name), true]
    end
    repos = Repository.readable_by(current_user).where(name: repo_name)
    if repos.count == 0
      raise ArgumentError.new "Repository not found: '#{repo_name}'"
    elsif repos.count > 1
      logger.error "Multiple repositories with name=='#{repo_name}'!"
      raise ArgumentError.new "Name conflict"
    else
      return [repos.first.server_path, false]
    end
  end

  def self.cache_dir_for git_url
    File.join(cache_dir_base, Digest::SHA1.hexdigest(git_url) + ".git").to_s
  end

  def self.cache_dir_base
    Rails.root.join 'tmp', 'git-cache'
  end

  def self.fetch_remote_repository gitdir, git_url
    # Caller decides which protocols are worth using. This is just a
    # safety check to ensure we never use urls like "--flag" or wander
    # into git's hardlink features by using bare "/path/foo" instead
    # of "file:///path/foo".
    unless /^[a-z]+:\/\// =~ git_url
      raise ArgumentError.new "invalid git url #{git_url}"
    end
    begin
      must_git gitdir, "branch"
    rescue GitError => e
      raise unless /Not a git repository/ =~ e.to_s
      # OK, this just means we need to create a blank cache repository
      # before fetching.
      FileUtils.mkdir_p gitdir
      must_git gitdir, "init"
    end
    must_git(gitdir,
             "fetch --no-progress --tags --prune --force --update-head-ok #{git_url.shellescape} 'refs/heads/*:refs/heads/*'")
  end

  def self.must_git gitdir, *cmds
    # Clear token in case a git helper tries to use it as a password.
    orig_token = ENV['ARVADOS_API_TOKEN']
    ENV['ARVADOS_API_TOKEN'] = ''
    last_output = ''
    begin
      git = "git --git-dir #{gitdir.shellescape}"
      cmds.each do |cmd|
        last_output = must_pipe git+" "+cmd
      end
    ensure
      ENV['ARVADOS_API_TOKEN'] = orig_token
    end
    return last_output
  end

  def self.must_pipe *cmds
    cmd = cmds.join(" 2>&1 |") + " 2>&1"
    out = IO.read("| </dev/null #{cmd}")
    if not $?.success?
      raise GitError.new "#{cmd}: #{$?}: #{out}"
    end
    return out
  end
end
