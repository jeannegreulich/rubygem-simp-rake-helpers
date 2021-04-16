# This file provided many common build-related tasks and helper methods from
# the SIMP Rakefile ecosystem.

require 'fileutils'

module Simp; end
  class Gpgkeys

    def initialize( gpgkeys_dir , default_dir = 'simp')

      @gpgkey_dir =  ENV['SIMP_GPGKEYS_dir'] || gpgkeys_dir
      if ! File.exists?(@gpgkey_dir)
          fail("Error: Could not find gpgkey directory #{@gpgkey_dir}")
      end

      temp_gpg_dir = Dir.mktmpdir
      @gpgkey_hash = load_gpgkeys(gpgkeys_dir,tmp_dir)
      fail("Error: Could not load GPG keys for repos in SIMP GPG directory #{@gpgkey_dir}") if @gpgkey_hash.empty? 
    end

    def load_gpgkeys( key_dir, tpm_dir)
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

    def  get_reponame(rpm)
      reponame = 'UNKNOWN'
      @gpgkey_hash.each {|repo, cmd|
        %x{#{cmd} --checksig #{rpm} > dev/null}
        if $?.status == 0
          reponame = repo
          break
        end
      }
    end

end
