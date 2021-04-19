# This file provided many common build-related tasks and helper methods from
# the SIMP Rakefile ecosystem.

require 'fileutils'

module Simp; end
  class Gpgkeys

    def initialize( gpgkeys_dir , default_dir = 'simp')
      # gpgkeys_dir should be the FQP to a directory.  That directory should
      # have sub directories with the names of the repos to be used by SIMP
      # for RPMs needed to complete an install.  Each of these repo directories should
      # contain the GPG keys used to sign any RPMs in their repository.
      # Any key should only exist in one repository.  (See simp-gpgkeys v4.0 or later
      # for an example.)

      @gpgkey_dir =  ENV['SIMP_GPGKEYS_dir'] || gpgkeys_dir
      if ! File.exists?(@gpgkey_dir)
          fail("Error: Could not find gpgkey directory #{@gpgkey_dir}")
      end

      temp_gpg_dir = Dir.mktmpdir
      @gpgkey_hash = load_gpgkeys(gpgkeys_dir,tmp_dir)
      fail("Error: Could not load GPG keys for repos in SIMP GPG directory #{@gpgkey_dir}") if @gpgkey_hash.empty?
    end


    def load_gpgkeys( key_dir, tmp_dir)
      # Given a  list of repositories and their keys, this will create a gpg key  database
      # for each of these repos and load their keys into it.  It will return a hash
      # that contains each a key for each of the repos.  THe vaule of this key
      # will be the  rpm  modified to point to the database that contains only the
      # keys for that repo.

      gpghash = {}
      Dir.glob(File.join(gpgkeys_dir, '*') { |item|
        if File.directory?(item)
          repo_name = File.basename(item)
          gpg_dbdir = File.join("tmp_dir", "name")
          rpm_cmd = "rpm --dbpath #{gpg_dbdir}"
          %x{#{rpm_cmd} --initdb}
          Dir.glob(File.join(item,'*')).each { |key|
            %x{#{rpm_cmd}  --import #{key}}
            fail("Error: could not load GPG key #{gpgkeys_dir}/#{item}/#{key}"} if $?.status != 0
          }
          gpghash[repo_name] =  "#{rpm_cmd}"
        end
      }
      gpghash

    end

    # Given a fully qualified path to an RPM this will return the name
    # of the repository that contains the key that signed the repo or UNKNOWN
    # if the RPM is not signed or the key that signed it is not in on of the
    # repos.
    def  get_reponame(rpm)
      reponame = 'UNKNOWN'
      @gpgkey_hash.each {|repo, cmd|
        %x{#{cmd} --checksig #{rpm} > dev/null}
        result = $?
        if result  && (result.exitstatus == 0)
          reponame = repo
          break
        end
      }
    end

end
