#!/usr/bin/rake -T

require 'yaml'

class R10KHelper
  attr_accessor :puppetfile
  attr_accessor :modules
  attr_accessor :basedir

  require 'r10k/puppetfile'

  # Horrible, but we need to be able to manipulate the cache
  class R10K::Git::ShellGit::ThinRepository
    def cache_repo
      @cache_repo
    end

    # Return true if the repository has local modifications, false otherwise.
    def dirty?
      repo_status = false

      return repo_status unless File.directory?(path)

      Dir.chdir(path) do
        %x(git update-index -q --ignore-submodules --refresh)
        repo_status = "Could not update git index for '#{path}'" unless $?.success?

        unless repo_status
          %x(git diff-files --quiet --ignore-submodules --)
          repo_status = "'#{path}' has unstaged changes" unless $?.success?
        end

        unless repo_status
          %x(git diff-index --cached --quiet HEAD --ignore-submodules --)
          repo_status = "'#{path}' has uncommitted changes" unless $?.success?
        end

        unless repo_status
          # Things that may be out of date but which should stop the updating
          # of the git repo
          our_exclusions=[
            'build/rpm_metadata',
            'dist/'
          ]

          untracked_files = %x(git ls-files -o -d --exclude-standard --exclude=#{our_exclusions.join(' --exclude=')})

          if $?.success?
            unless untracked_files.empty?
              untracked_files.strip!

              if untracked_files.lines.count > 0
                repo_status = "'#{path}' has untracked files"
              end
            end
          else
            # We should never get here
            raise Error, "Failure running 'git ls-files -o -d --exclude-standard' at '#{path}'"
          end
        end
      end

      repo_status
    end
  end

  def initialize(puppetfile)
    @modules = []
    @basedir = File.dirname(File.expand_path(puppetfile))

    Dir.chdir(@basedir) do

      R10K::Git::Cache.settings[:cache_root] = File.join(@basedir,'.r10k_cache')

      unless File.directory?(R10K::Git::Cache.settings[:cache_root])
        FileUtils.mkdir_p(R10K::Git::Cache.settings[:cache_root])
      end

      r10k = R10K::Puppetfile.new(Dir.pwd, nil, puppetfile)
      r10k.load!

      @modules = r10k.modules.collect do |mod|
        mod_status = mod.repo.repo.dirty?

        mod = {
          :name        => mod.name,
          :path        => mod.path.to_s,
          :remote      => mod.repo.instance_variable_get('@remote'),
          :desired_ref => mod.desired_ref,
          :git_source  => mod.repo.repo.origin,
          :git_ref     => mod.repo.head,
          :module_dir  => mod.basedir,
          :status      => mod_status ? mod_status : :known,
          :r10k_module => mod,
          :r10k_cache  => mod.repo.repo.cache_repo
        }
      end
    end

    module_dirs = @modules.collect do |mod|
      mod = mod[:module_dir]
    end

    module_dirs.uniq!

    module_dirs.each do |module_dir|
      known_modules = @modules.select do |mod|
        mod[:module_dir] == module_dir
      end

      known_modules.map! do |mod|
        mod = mod[:name]
      end

      current_modules = Dir.glob(File.join(module_dir,'*')).map do |mod|
        mod = File.basename(mod)
      end

      (current_modules - known_modules).each do |mod|
        # Did we find random git repos in our module spaces?
        if File.exist?(File.join(module_dir, mod, '.git'))
          @modules << {
            :name        => mod,
            :path        => File.join(module_dir, mod),
            :module_dir  => module_dir,
            :status      => :unknown,
          }
        end
      end
    end
  end

  def puppetfile
    last_module_dir = nil
    pupfile = Array.new

    @modules.each do |mod|
      module_dir = mod[:path].split(@basedir.to_s).last.split('/')[1..-2].join('/')

      next unless mod[:r10k_module]

      if last_module_dir != module_dir
        pupfile << "moduledir '#{module_dir}'\n"
        last_module_dir = module_dir
      end

      pupfile << "mod '#{mod[:r10k_module].title}',"
      pupfile << "  :git => '#{mod[:git_source]}',"
      pupfile << "  :ref => '#{mod[:r10k_module].repo.head}'\n"
    end

    pupfile << '# vim: ai ts=2 sts=2 et sw=2 ft=ruby'

    pupfile.join("\n")
  end

  def each_module(&block)
    Dir.chdir(@basedir) do
      @modules.each do |mod|
        # This works for Puppet Modules

        block.call(mod)
      end
    end
  end

  def unknown_modules
    @modules.select do |mod|
      mod[:status] == :unknown
    end.map do |mod|
      mod = mod[:name]
    end
  end
end

module Simp; end
module Simp::Rake; end
module Simp::Rake::Build

  class Deps < ::Rake::TaskLib
    require 'pager'
    include Pager

    def initialize( base_dir )
      @base_dir = base_dir
      @verbose = ENV.fetch('SIMP_PKG_verbose','no') == 'yes'
      define_tasks
    end

    def define_tasks
      namespace :deps do
        desc <<-EOM
        Checks out all dependency repos.

        This task used R10k to update all dependencies.

        Arguments:
          * :method  => The update method to use (Default => 'tracking')
               tracking => checks out each dep (by branch) according to Puppetfile.tracking
               stable   => checks out each dep (by ref) according to in Puppetfile.stable
        EOM
        task :checkout, [:method] do |t,args|
          args.with_defaults(:method => 'tracking')

          r10k_helper = R10KHelper.new("Puppetfile.#{args[:method]}")

          r10k_issues = Parallel.map(
            Array(r10k_helper.modules),
            :in_processes => get_cpu_limit,
            :progress => 'Submodule Checkout'
          ) do |mod|
            issues = []

            Dir.chdir(@base_dir) do
              unless File.directory?(mod[:path])
                FileUtils.mkdir_p(mod[:path])
              end

              # Only for known modules...
              unless mod[:status] == :unknown
                # Since r10k is destructive, we're enumerating all valid states
                if [
                    :absent,
                    :mismatched,
                    :outdated,
                    :insync,
                    :dirty
                ].include?(mod[:r10k_module].status)
                  unless mod[:r10k_cache].synced?
                    mod[:r10k_cache].sync
                  end

                  if mod[:status] == :known
                    mod[:r10k_module].sync
                  else
                    # If we get here, the module was dirty and should be skipped
                    issues << "#{mod[:name]}: Skipped - #{mod[:status]}"
                    next
                  end
                else
                  issues << "#{mod[:name]}: Skipped - Unknown status type #{mod[:r10k_module].status}"
                end
              end
            end

            issues
          end

          r10k_issues.flatten!

          unless r10k_issues.empty?
            $stderr.puts('='*80)

            unless @verbose
              $stderr.puts('Warning: Some repositories were skipped!')
              $stderr.puts('  * If this is a fresh build, this could be an issue')
              $stderr.puts('  * This is expected if re-running a build')
              $stderr.puts('  * Run with SIMP_PKG_verbose=yes for full details')
            else
              $stderr.puts("R10k Checkout Issues:")
              r10k_issues.each do |issue|
                $stderr.puts("  * #{issue}")
              end
            end

            $stderr.puts('='*80)
          end
        end

        desc <<-EOM
        Get the status of the project Git repositories

        Arguments:
          * :method  => The update method to use (Default => 'tracking')
               tracking => checks out each dep (by branch) according to Puppetfile.tracking
               stable   => checks out each dep (by ref) according to in Puppetfile.stable
        EOM
        task :status, [:method] do |t,args|
          args.with_defaults(:method => 'tracking')
          @dirty_repos = nil

          r10k_helper = R10KHelper.new("Puppetfile.#{args[:method]}")

          mods_with_changes = {}

          r10k_helper.each_module do |mod|
            unless File.directory?(mod[:path])
              $stderr.puts("Warning: '#{mod[:path]}' is not a module...skipping") if File.exist?(mod[:path])
              next
            end

            if mod[:status] != :known
              # Clean up the path a bit for printing
              dirty_path = mod[:path].split(r10k_helper.basedir.to_s).last
              if dirty_path[0].chr == File::SEPARATOR
                dirty_path[0] = ''
              end

              mods_with_changes[mod[:name]] = dirty_path
            end
          end

          if mods_with_changes.empty?
            puts "No repositories have changes."
            @dirty_repos = false
          else
            puts "The following repositories have changes:"
            puts mods_with_changes.map{|k,v| "  + #{k} => #{v}"}.join("\n")

            @dirty_repos = true
          end

          unknown_mods = r10k_helper.unknown_modules
          unless unknown_mods.empty?
            puts "The following modules were unknown:"
            puts unknown_mods.map{|k,v| "  ? #{k}"}.join("\n")
          end
        end

        desc <<-EOM
        Records the current dependencies into Puppetfile.stable.

        Arguments:
          * :method    => Save to Puppetfile.[method] (Default => 'stable')
          * :reference => Use Puppetfile.[reference] to reference which repos
                          should be recorded (Default => 'tracking')
        EOM
        task :record, [:method,:reference] do |t,args|
          args.with_defaults(:method => 'stable')
          args.with_defaults(:reference => 'tracking')

          r10k_helper = R10KHelper.new("Puppetfile.#{args[:reference]}")
          File.open("Puppetfile.#{args[:method]}",'w'){|f| f.puts r10k_helper.puppetfile }
        end

        desc <<-EOM
        Provide a log of changes to all modules since a previous release of SIMP.
        It prints out both CHANGELOG and Git Logs.
        At the end it prints out a summary of versions compared in comma deliminated
        format.

        Arguments:
          * :old_ver => The previous release of SIMP to compare against. Make sure
               this is a valid branch or tag.
          * :source => The source Puppetfile to use (Default => 'tracking')
        EOM

        task :changelog2, [:old_ver] do |t,args|
          require 'fileutils'
          require 'tempfile'
          args.with_defaults(:source => 'tracking')
          r10k_helper = R10KHelper.new("Puppetfile.#{args[:source]}")

          git_logs = Hash.new

          Dir.chdir(r10k_helper.basedir) do
            # Get the Puppetfile from the previous release and write it out to a file.
            pf_old_file = "Puppetfile.tmp.#{args[:source]}"
            pf_old_data = %x(git show '#{args[:old_ver]}':Puppetfile.'#{args[:source]}')
            return_status = "Could not retrieve Puppetfile.#{args[:source]} from branch #{args[:old_ver]}." unless $?.success?
            File.delete("#{Dir.pwd}/#{pf_old_file}") if File.exists?("#{Dir.pwd}/#{pf_old_file}")
            File.open("#{Dir.pwd}/#{pf_old_file}",'w'){ |f|
              f.write(pf_old_data)
            }

            require 'pry-byebug'
            # Read in the new file in Puppetfile format.
            prev_r10k = R10K::Puppetfile.new(Dir.pwd, nil, pf_old_file)
            prev_r10k.load!
            old_modules = Hash.new
            git_logs = Hash.new
            prev_r10k.modules.each do |mod|
              old_modules[mod.name] = {
                :name        => mod.name,
                :path        => mod.path.to_s,
                :desired_ref => mod.desired_ref,
                :git_source  => mod.repo.repo.origin,
                :git_ref     => mod.repo.head,
                :module_dir  => mod.basedir,
              }
            end

            #Go through each Module
            r10k_helper.each_module do |mod|
              git_logs[mod[:name]] = Hash.new
              git_logs[mod[:name]][:curver] = mod[:desired_ref]
              git_logs[mod[:name]][:prevver] = "No Previous Module Data"
              if File.directory?(mod[:path])
                Dir.chdir(mod[:path]) do
                  # Compare Changelogs
                  changelog =  "No CHANGELOG"
                  if old_modules.has_key?(mod[:name])
                    old_mod = old_modules[mod[:name]]
                    if old_mod[:desired_ref] == mod[:desired_ref]
                      changelog = "No Modules Changes"
                      log_output = "No Module Changes"
                    else
                      git_logs[mod[:name]][:prevver] = old_mod[:desired_ref]
                      if File.exists?("./CHANGELOG")
                        logout = %x(git diff '#{old_mod[:desired_ref]}' CHANGELOG).split("\n")
                        changelog = logout.collect{ |x| x[1..-1] if x.start_with?("+") && ! x.start_with?("+++") }.compact.join("\n")
                      end
                      log_output = %x(git log "#{old_mod[:desired_ref]}..#{mod[:desired_ref]}" --stat --reverse).chomp
                    end
                  else
                    if File.exists?("./CHANGELOG")
                      changelog = File.read("./CHANGELOG")
                    end
                    log_output = "Module did not exist in previous version of SIMP"
                    #%x(git log #{mod[:desired_ref]}" --stat --reverse).chomp
                  end
                  # Get the GIT log
                  git_logs[mod[:name]][:changelog] = changelog
                  git_logs[mod[:name]][:log] = log_output unless log_output.strip.empty?
                end
              else
                git_logs[mod[:name]] = {
                  :changelog => 'No DATA',
                  :log       => 'No DATA'
                }
              end

            end
            version_info = ["Module Name, Current Version, Previous Version"]
            git_logs.keys.sort.each do |mod_name|
              version_info << "#{mod_name},#{git_logs[mod_name][:curver]},#{git_logs[mod_name][:prevver]}"
              puts <<-EOM
========
#{mod_name}:

Current  Version: #{git_logs[mod_name][:curver]}
Previous Version: #{git_logs[mod_name][:prevver]}
-----------
CHANGELOG

#{git_logs[mod_name][:changelog].gsub(/^/,'  ')}

-----------
GIT LOG
#{git_logs[mod_name][:log].gsub(/^/,'  ')}
-----------
              EOM
            end

          puts <<-EOM
=====================================================================================
List of Versions
----------------
#{version_info.join("\n")}
=====================================================================================
          EOM
          end

        # end task changelog2
        end

        desc <<-EOM
        Provide a log of changes to all modules from the given top level Git reference.

        Arguments:
          * :ref => The top level git ref to use as the oldest point for all logs.
          * :source => The source Puppetfile to use (Default => 'tracking')
        EOM

        task :changelog, [:ref] do |t,args|
          args.with_defaults(:source => 'tracking')

          r10k_helper = R10KHelper.new("Puppetfile.#{args[:source]}")

          git_logs = Hash.new

          Dir.chdir(r10k_helper.basedir) do
            ref = args[:ref]
            refdate = nil
            begin
              refdate = %x(git log -1 --format=%ai '#{ref}')
              refdate = nil unless $?.success?
            rescue Exception
              #noop
            end

            fail("You must specify a valid reference") unless ref
            fail("Could not find a Git log for #{ref}") unless refdate

            mods_with_changes = {}

            log_output = %x(git log --since='#{refdate}' --stat --reverse).chomp
            git_logs['__SIMP CORE__'] = log_output unless log_output.strip.empty?

            r10k_helper.each_module do |mod|
              if File.directory?(mod[:path])
                Dir.chdir(mod[:path]) do
                  log_output = %x(git log --since='#{refdate}' --stat --reverse).chomp
                  git_logs[mod[:name]] = log_output unless log_output.strip.empty?
                end
              end
            end

            if git_logs.empty?
              puts( "No changes found for any components since #{refdate}")
            else
              page

              git_logs.keys.sort.each do |mod_name|
                puts <<-EOM
  ========
  #{mod_name}:

  #{git_logs[mod_name].gsub(/^/,'  ')}

                EOM
              end
            end
          end
        end
      end
    end
  end
end


# vim: ai ts=2 sts=2 et sw=2 ft=ruby
