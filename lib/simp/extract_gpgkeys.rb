require 'simp/command_utils'

module Simp
  class ExtractGpgKeys
    include FileUtils
    include Simp::CommandUtils

    # This module will extract the gpgkeys from the simp-gpgkeys to a temp directory.
    # The copy method will copy them to a user provided directory.
    # @param rpm [String] path to simp-gpgkeys rpm or path under which it resides.
    #        It looks for simp-gpgkeys*.noarch.rpm.  There must be only
    #        one RPM under the directory that fits that glob.
    #
    def initialize(rpm)
      begin
        @rpm = find_gpgkeys_rpm(rpm)
        @temp_keys_dir = Dir.mktmpdir
        at_exit { FileUtils.remove_entry(@temp_keys_dir) if File.exists?(@temp_keys_dir) }
        @gpgkey_dir = extract_gpgkeys(@rpm)
      rescue => e
        puts(<<-EOT)
          Unable to extract the gpgkeys from #{rpm}.
          Received the following error:
          #{e.message}
        EOT
        fail("Unable to get gpgkeys")
      end
    end

    def copy(dir)
      check_output_dir(dir)
      FileUtils.cp_r(@gpgkey_dir,dir)
    end

    private
    def extract_gpgkeys(rpm)
      dir = @temp_keys_dir
      gpgkey_dir = nil
      @@cpio_cmd = %x{which cpio}.strip
      raise(Error, "Error: Could not find 'cpio'. Please install and try again.")  if @@cpio_cmd.empty?
      @@rpm2cpio_cmd = %x{which rpm2cpio}.strip
      raise("Error: Could not find 'rpm2cpio'. Please install and try again.") if @@rpm2cpio_cmd.empty?
      Dir.chdir(dir) do
        %x{@@rpm2cpio_cmd rpm |  @@cpio -id}
        raise("Could not extract the gpgkeys from #{rpm}") if $?.exitstatus != 0
      end
      gpgkey_dir = File.join(dir,'usr','share','simp','GPGKEYS')
      raise("No GPGKEYS directory found in #{rpm}") unless File.directory?(gpgkey_dir)
      return gpgkey_dir
    end

    def find_gpgkeys_rpm(rpm_file)
      raise("Error:  #{rpm_file}") unless File.exists?(rpm_file)
      return rpm_file if File.file?(rpm_file)
      raise("Error: File #{rpm_file}  exists but is not a File or Directory.") unless File.directory?(rpm_file)
      rpms = Dir.glob(File.join(rpm_file,'**','simp-gpgkeys*.noarch.rpm'))
      raise("Error: More then one simp_gpgkeys RPM exists in directory #{rpm_file}") unless rpms.length == 1
      return rpms.first
    end

    def check_output_dir(dir)
      raise("Error: Output directory #{dir} is not a directory.") unless File.directory?(dir)
      raise("Error: Output directory #{dir} already contains GPGKEYS.") if File.exists?("#{dir}/GPGKEYS")
    end

  end

end
