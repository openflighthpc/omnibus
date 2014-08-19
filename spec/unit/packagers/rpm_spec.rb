require 'spec_helper'

module Omnibus
  describe Packager::RPM do
    let(:project) do
      Project.new.tap do |project|
        project.name('project')
        project.homepage('https://example.com')
        project.install_dir('/opt/project')
        project.build_version('1.2.3')
        project.build_iteration('2')
        project.maintainer('Chef Software')
      end
    end

    subject { described_class.new(project) }

    let(:project_root) { "#{tmp_path}/project/root" }
    let(:package_dir)  { "#{tmp_path}/package/dir" }
    let(:staging_dir)  { "#{tmp_path}/staging/dir" }

    before do
      Config.project_root(project_root)
      Config.package_dir(package_dir)

      allow(subject).to receive(:staging_dir).and_return(staging_dir)
      create_directory(staging_dir)
      create_directory("#{staging_dir}/BUILD")
      create_directory("#{staging_dir}/RPMS")
      create_directory("#{staging_dir}/SRPMS")
      create_directory("#{staging_dir}/SOURCES")
      create_directory("#{staging_dir}/SPECS")
    end

    describe 'DSL' do
      it 'exposes :signing_passphrase' do
        expect(subject).to have_exposed_method(:signing_passphrase)
      end
    end

    describe '#id' do
      it 'is :rpm' do
        expect(subject.id).to eq(:rpm)
      end
    end

    describe '#package_name' do
      before do
        allow(subject).to receive(:safe_architecture).and_return('x86_64')
      end

      it 'includes the name, version, and build iteration' do
        expect(subject.package_name).to eq('project-1.2.3-2.x86_64.rpm')
      end
    end

    describe '#build_dir' do
      it 'is nested inside the staging_dir' do
        expect(subject.build_dir).to eq("#{staging_dir}/BUILD")
      end
    end

    describe '#write_rpm_spec' do
      before do
        allow(subject).to receive(:safe_architecture).and_return('x86_64')
      end

      let(:spec_file) { "#{staging_dir}/SPECS/project-1.2.3-2.x86_64.rpm.spec" }

      it 'generates the file' do
        subject.write_rpm_spec
        expect(spec_file).to be_a_file
      end

      it 'has the correct content' do
        subject.write_rpm_spec
        contents = File.read(spec_file)

        expect(contents).to include("Name: project")
        expect(contents).to include("Version: 1.2.3")
        expect(contents).to include("Release: 2")
        expect(contents).to include("Summary:  The full stack of project")
        expect(contents).to include("BuildArch: x86_64")
        expect(contents).to include("AutoReqProv: no")
        expect(contents).to include("BuildRoot: %buildroot")
        expect(contents).to include("Prefix: /")
        expect(contents).to include("Group: default")
        expect(contents).to include("License: unknown")
        expect(contents).to include("Vendor: Omnibus <omnibus@getchef.com>")
        expect(contents).to include("URL: https://example.com")
        expect(contents).to include("Packager: Chef Software")
      end

      context 'when scripts are given' do
        before do
          Packager::RPM::SCRIPTS.each do |name|
            create_file("#{project_root}/package-scripts/project/#{name}") do
              "Contents of #{name}"
            end
          end
        end

        it 'writes the scripts into the spec' do
          subject.write_rpm_spec
          contents = File.read(spec_file)

          expect(contents).to include("%pre")
          expect(contents).to include("Contents of pre")
          expect(contents).to include("%post")
          expect(contents).to include("Contents of post")
          expect(contents).to include("%preun")
          expect(contents).to include("Contents of preun")
          expect(contents).to include("%postun")
          expect(contents).to include("Contents of postun")
          expect(contents).to include("%verifyscript")
          expect(contents).to include("Contents of verifyscript")
          expect(contents).to include("%pretans")
          expect(contents).to include("Contents of pretans")
          expect(contents).to include("%posttrans")
          expect(contents).to include("Contents of posttrans")
        end
      end

      context 'when files and directories are present' do
        before do
          create_file("#{staging_dir}/BUILD/.file1")
          create_file("#{staging_dir}/BUILD/file2")
          create_directory("#{staging_dir}/BUILD/.dir1")
          create_directory("#{staging_dir}/BUILD/dir2")
        end

        it 'writes them into the spec' do
          subject.write_rpm_spec
          contents = File.read(spec_file)

          expect(contents).to include("/.dir1")
          expect(contents).to include("/.file1")
          expect(contents).to include("/dir2")
          expect(contents).to include("/file2")
        end
      end
    end

    describe '#create_rpm_file' do
      before do
        allow(subject).to receive(:shellout!)
        allow(Dir).to receive(:chdir) { |_, &b| b.call }
      end

      it 'logs a message' do
        output = capture_logging { subject.create_rpm_file }
        expect(output).to include('Creating .rpm file')
      end

      it 'uses the correct command' do
        expect(subject).to receive(:shellout!)
          .with(/rpmbuild -bb --buildroot/)
        subject.create_rpm_file
      end

      context 'when RPM signing is enabled' do
        before do
          subject.signing_passphrase('foobar')
          allow(Dir).to receive(:mktmpdir).and_return(tmp_path)
        end

        it 'signs the rpm' do
          expect(subject).to receive(:shellout!)
            .with(/sign\-rpm/, kind_of(Hash))
          subject.create_rpm_file
        end
      end
    end

    describe '#spec_file' do
      before do
        allow(subject).to receive(:package_name).and_return('package_name')
      end

      it 'includes the package_name' do
        expect(subject.spec_file).to eq("#{staging_dir}/SPECS/package_name.spec")
      end
    end

    describe '#rpm_safe' do
      it 'adds quotes when required' do
        expect(subject.rpm_safe('file path')).to eq('"file path"')
      end

      it 'escapes [' do
        expect(subject.rpm_safe('[foo')).to eq('[\\[]foo')
      end

      it 'escapes *' do
        expect(subject.rpm_safe('*foo')).to eq('[*]foo')
      end

      it 'escapes ?' do
        expect(subject.rpm_safe('?foo')).to eq('[?]foo')
      end

      it 'escapes %' do
        expect(subject.rpm_safe('%foo')).to eq('[%]foo')
      end
    end

    describe '#safe_project_name' do
      context 'when the project name is "safe"' do
        it 'returns the value without logging a message' do
          expect(subject.safe_project_name).to eq('project')
          expect(subject).to_not receive(:log)
        end
      end

      context 'when the project name has invalid characters' do
        before { project.name("Pro$ject123.for-realz_2") }

        it 'returns the value while logging a message' do
          output = capture_logging do
            expect(subject.safe_project_name).to eq('pro-ject123.for-realz-2')
          end

          expect(output).to include("The `name' compontent of RPM package names can only include")
        end
      end
    end

    describe '#safe_build_iteration' do
      it 'returns the build iternation' do
        expect(subject.safe_build_iteration).to eq(project.build_iteration)
      end
    end

    describe '#safe_version' do
      context 'when the project build_version is "safe"' do
        it 'returns the value without logging a message' do
          expect(subject.safe_version).to eq('1.2.3')
          expect(subject).to_not receive(:log)
        end
      end

      context 'when the project build_version has invalid characters' do
        before { project.build_version("1.2$alpha.##__2") }

        it 'returns the value while logging a message' do
          output = capture_logging do
            expect(subject.safe_version).to eq('1.2-alpha.-2')
          end

          expect(output).to include("The `version' compontent of RPM package names can only include")
        end
      end
    end

    describe '#safe_architecture' do
      before do
        stub_ohai(platform: 'ubuntu', version: '12.04') do |data|
          data['kernel']['machine'] = 'i386'
        end
      end

      it 'returns the value from Ohai' do
        expect(subject.safe_architecture).to eq('i386')
      end
    end
  end
end