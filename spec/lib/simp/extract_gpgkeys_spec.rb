require 'simp/extract_gpgkeys'
require 'spec_helper'
require 'fileutils'
require 'tmpdir'

describe Simp::ExtractGpgKeys do
  let(:rpmok_dir) { File.join(File.join( File.dirname(__FILE__), 'files','gpgtest_dir', 'ok'))}
  let(:rpmnotok_dir) { File.join(File.join( File.dirname(__FILE__), 'files','gpgtest_dir', 'notok'))}
  let(:gpgrpm) { File.join(File.join( File.dirname(__FILE__), 'files','gpgtest_dir', 'ok','simp-gpgkeys-3.1.2-0.noarch.rpm')) }


  context 'if passed a directory it should find the rpm' do

    it 'should return the rpm if only one is found and nil otherwise' do
      obj = described_class.new(rpmok_dir)
      expect(obj).to receive(:`).with("which cpio").and_return("/bin/cpio")
      expect(obj).to receive(:`).with("which rpm2cpio").and_return("/bin/rpm2cpio")
      allow(obj).to receive(:`).with("/bin/rpm2cpio #{gpgrpm} | /bin/cpio -id") {

        expect($?).to receive(:exitstatus).returns(0)
      }
      returned_rpm = obj.send(:find_gpgkeys_rpm,rpmok_dir)
      expect(returned_rpm).to  eq gpgrpm
    end
    it 'should return nil if more than one is found' do
      expect{described_class.new(rpmnotok_dir)}.to raise_error(/Unable to determine Simp_gpgkeys/)
    end

  end
end
