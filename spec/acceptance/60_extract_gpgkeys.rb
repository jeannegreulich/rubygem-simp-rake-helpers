require 'spec_helper_acceptance'
require_relative 'support/build_user_helpers'
require_relative 'support/build_project_helpers'
require 'lib/simp/extract_gpgkeys'

RSpec.configure do |c|
  c.include Simp::BeakerHelpers::SimpRakeHelpers::BuildUserHelpers
  c.extend  Simp::BeakerHelpers::SimpRakeHelpers::BuildUserHelpers
end

# options to be applied to each on() operation
def run_opts
  # WARNING: If you set run_in_parallel to true, tests will fail
  # when run in a GitHub action.
  { run_in_parallel: false }
end

describe 'Simp::ExtractGpgKeys' do

    before(:all) do

      on(hosts, %(#{run_cmd} "yum install cpio"))
      on(hosts, %(#{run_cmd} "yum install rpm"))
      on(hosts, %(#{run_cmd} "yum install https://download.simp-project.com/simp-release-community.rpm"))


    end

    let(:rpms_dir) { /tmp/rpms__dir }


    it 'download simp-gpgkeys' do
      hosts.each do |host|
        on(host, %(#{run_cmd} "yum install --downloadonly --downloaddir=#{rpms_dir} --disablerepo='*' --enablerepo=simp-community-simp simp-gpgkeys))
      end
    end

end

#  describe 'when packages are already signed' do
#    let(:keysdir)  { "#{test_dir}/.dev_gpgkeys" }
#
#    include_context('a freshly-scaffolded test project', 'force')
#
#    context 'initial package signing' do
#      include_examples('it begins with unsigned RPMs')
#      include_examples('it creates GPG dev signing key and signs packages')
#    end
#
#    context 'when force is disabled' do
#      before :each do
#        # remove the initial signing key
#        on(hosts, %(#{run_cmd} 'rm -rf #{keysdir}'))
#      end
#
#      it 'creates new GPG signing key but does not resign RPMs' do
#        hosts.each do |host|
#          # force defaults to false
#          on(host, %(#{run_cmd} "cd '#{test_dir}'; bundle exec rake pkg:signrpms[dev,'#{rpms_dir}']"), run_opts)
#
#          result = on(host, "rpm -qip '#{test_rpm}' | grep ^Signature", run_opts)
#          expect(result.stdout).to match rpm_signed_regex
#          signed_rpm_data = rpm_signed_regex.match(result.stdout)
#
#          # verify RPM is not signed with the new signing key
#          expect(signed_rpm_data[:key_id]).to_not eql dev_signing_key_id(host, dev_keydir, run_opts)
#        end
#      end
#
#      it 'does not verify RPM signatures with the new key' do
#        public_gpgkeys_dir = 'src/assets/gpgkeys/GPGKEYS'
#        hosts.each do |host|
#          # mock out the simp-gpgkeys project checkout so that the pkg:checksig
#          # doesn't fail before reading in the new generated 'dev' GPGKEY
#          on(host, %(#{run_cmd} "cd '#{test_dir}'; mkdir -p #{public_gpgkeys_dir}"), run_opts)
#          on(host, %(#{run_cmd} "cd '#{test_dir}'; touch #{public_gpgkeys_dir}/RPM-GPG-KEY-empty"), run_opts)
#          result = on(host, %(#{run_cmd} "cd '#{test_dir}'; #{checksig_cmd}"),
#            :acceptable_exit_codes => [1]
#          )
#
#          expect(result.stderr).to match('ERROR: Untrusted RPMs found in the repository')
#        end
#      end
#    end
#
#    context 'when force is enabled' do
#      before :each do
#        # remove the initial signing key
#        on(hosts, %(#{run_cmd} 'rm -rf #{keysdir}'))
#      end
#
#      it 'creates new GPG signing key and resigns RPMs' do
#        hosts.each do |host|
#          on(host, %(#{run_cmd} "cd '#{test_dir}'; bundle exec rake pkg:signrpms[dev,'#{rpms_dir}',true]"), run_opts)
#
#          result = on(host, "rpm -qip '#{test_rpm}' | grep ^Signature", run_opts)
#          expect(result.stdout).to match rpm_signed_regex
#          signed_rpm_data = rpm_signed_regex.match(result.stdout)
#
#          # verify RPM is signed with the new signing key
#          expect(signed_rpm_data[:key_id]).to eql dev_signing_key_id(host, dev_keydir, run_opts)
#        end
#      end
#    end
#  end
#
#  describe 'when SIMP_PKG_build_keys_dir is set' do
#    opts = { :gpg_keysdir => '/home/build_user/.dev_gpgpkeys' }
#    include_context('a freshly-scaffolded test project', 'custom-keys-dir', opts)
#    include_examples('it begins with unsigned RPMs')
#    include_examples('it creates GPG dev signing key and signs packages')
#  end
#
#  describe 'when digest algorithm is specified' do
#    opts = { :digest_algo => 'sha384' }
#    include_context('a freshly-scaffolded test project', 'custom-digest-algo', opts)
#    include_examples('it begins with unsigned RPMs')
#    include_examples('it creates GPG dev signing key and signs packages')
#    include_examples('it verifies RPM signatures')
#  end
#
#  describe 'when some rpm signing fails' do
#    include_context('a freshly-scaffolded test project', 'signing-failure')
#    include_examples('it begins with unsigned RPMs')
#
#    it 'should create a malformed RPM' do
#      on(hosts, %(#{run_cmd} "echo 'OOPS' > #{rpms_dir}/oops-test.rpm"))
#    end
#
#    it 'should sign all valid RPMs before failing' do
#      hosts.each do |host|
#        result = on(host,
#          %(#{run_cmd} "cd '#{test_dir}'; SIMP_PKG_verbose="yes" #{signrpm_cmd}"),
#         :acceptable_exit_codes => [1]
#        )
#
#        expect(result.stderr).to match('ERROR: Failed to sign some RPMs')
#
#        signature_check = on(host, "rpm -qip '#{test_rpm}' | grep ^Signature", run_opts)
#        expect(signature_check.stdout).to match rpm_signed_regex
#      end
#    end
#  end
#
#  describe 'when wrong keyword password is specified' do
#    include_context('a freshly-scaffolded test project', 'wrong-password')
#    include_examples('it creates a new GPG dev signing key')
#
#    it 'should corrupt the password of new key' do
#      key_gen_file = File.join(dev_keydir, 'gengpgkey')
#      on(hosts, "sed -i -e \"s/^Passphrase: /Passphrase: OOPS/\" #{key_gen_file}")
#    end
#
#    include_examples('it begins with unsigned RPMs')
#
#    it 'should fail to sign any rpms and notify user of each failure' do
#      hosts.each do |host|
#        result = on(host,
#          %(#{run_cmd} "cd '#{test_dir}'; SIMP_PKG_verbose="yes" #{signrpm_cmd}"),
#         :acceptable_exit_codes => [1]
#        )
#
#        err_msg = %r(Error occurred while attempting to sign #{test_rpm})
#        expect(result.stderr).to match(err_msg)
#
#        signature_check = on(host, "rpm -qip '#{test_rpm}' | grep ^Signature", run_opts)
#        expect(signature_check.stdout).to match rpm_unsigned_regex
#      end
#    end
#  end
#
#  hosts.each do |host|
#    os_major =  fact_on(host,'operatingsystemmajrelease')
#    if os_major > '7'
#      # this problem only happens on EL > 7 in a docker container
#      describe "when gpg-agent's socket path is too long on #{host}" do
#        opts = { :gpg_keysdir => '/home/build_user/this/results/in/a/gpg_agent/socket/path/that/is/longer/than/one/hundred/eight/characters' }
#        include_context('a freshly-scaffolded test project', 'long-socket-path', opts)
#
#        context 'when the gpg key needs to be created ' do
#          it 'should fail to sign any rpms' do
#            on(host,
#               %(#{run_cmd} "cd '#{test_dir}'; SIMP_PKG_verbose="yes" #{signrpm_cmd}"),
#              :acceptable_exit_codes => [1]
#            )
#          end
#        end
#
#        context 'when the gpg key already exists' do
#          # This would be when a GPG key dir was populated with keys generated elsewhere.
#          # Reuse the keys from an earlier test.
#          it 'should copy existing key files into the gpg key dir' do
#            source_dir = '/home/build_user/test-create-key/.dev_gpgkeys/dev'
#            on(host, %(#{run_cmd} "cp -r #{source_dir}/* #{dev_keydir}"))
#          end
#
#          include_examples('it begins with unsigned RPMs')
#
#          it 'should fail to sign any rpms and notify user of each failure' do
#            # For rpm-sign-4.14.2-11.el8_0, 'rpm --resign' hangs instead of failing
#            # when gpg-agent fails to start.
#            # Set the default smaller than the 30 second default, so that we don't
#            # wait so long for the failure.
#            result = on(host,
#              %(#{run_cmd} "cd '#{test_dir}'; SIMP_PKG_rpmsign_timeout=5 SIMP_PKG_verbose="yes" #{signrpm_cmd}"),
#              :acceptable_exit_codes => [1]
#            )
#
#            err_msg = %r(Failed to sign #{test_rpm} in 5 seconds)
#            expect(result.stderr).to match(err_msg)
#
#            signature_check = on(host, "rpm -qip '#{test_rpm}' | grep ^Signature", run_opts)
#            expect(signature_check.stdout).to match rpm_unsigned_regex
#          end
#        end
#      end
#    end
#  end
#end
