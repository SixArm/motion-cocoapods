require File.expand_path('../spec_helper', __FILE__)

module Motion; module Project;
  class Vendor
    attr_reader :opts
  end

  class Config
    attr_writer :project_dir
  end
end; end

describe "motion-cocoapods" do
  extend SpecHelper::TemporaryDirectory

  def podfile=(podfile); @podfile = podfile; end
  def installer=(installer); @installer = installer; end
  def installer_rep_from_post_install_hook=(installer); @installer_rep_from_post_install_hook = installer; end

  before do
    unless @ran_install
      teardown_temporary_directory
      setup_temporary_directory

      Pod::Config.instance.silent = true
      #Pod::Config.instance.verbose = true

      context = self

      @config = App.config
      @config.project_dir = temporary_directory.to_s
      @config.deployment_target = '5.0'
      @config.instance_eval do
        pods do
          context.podfile = @podfile

          pod 'AFNetworking', '1.3.2'
          pod 'AFIncrementalStore', '0.5.1' # depends on AFNetworking ~> 1.3.2, but 1.3.3 exists.
          pod 'AFKissXMLRequestOperation'

          post_install do |installer|
            context.installer_rep_from_post_install_hook = installer
          end

          context.installer = pods_installer
        end
      end
    end
  end

  it "pods deployment target should equal to project deployment target" do
    @podfile.target_definition_list.first.platform.deployment_target.to_s.should == '5.0'
  end

  before do
    unless @ran_install
      Rake::Task['pod:install'].invoke
      @config.pods.configure_project
      @ran_install = true
    end
  end

  it "adds all the required frameworks and libraries" do
    @config.frameworks.sort.should == %w{ CoreData CoreGraphics Foundation MobileCoreServices Security SystemConfiguration UIKit }
    @config.libs.sort.should == %w{ /usr/lib/libxml2.dylib }
  end

  it "installs the Pods to vendor/Pods" do
    (Pathname.new(@config.project_dir) + 'vendor/Pods/AFNetworking').should.exist
    (Pathname.new(@config.project_dir) + 'vendor/Pods/AFIncrementalStore').should.exist
    (Pathname.new(@config.project_dir) + 'vendor/Pods/AFKissXMLRequestOperation').should.exist
  end

  it "configures CocoaPods to resolve dependency files for the iOS platform" do
    @podfile.target_definition_list.first.platform.should == :ios
  end

  it "writes Podfile.lock to vendor/" do
    (Pathname.new(@config.project_dir) + 'vendor/Podfile.lock').should.exist
  end

  it "adds Pods.xcodeproj as a vendor project" do
    project = @config.vendor_projects.last
    project.path.should == 'vendor/Pods'
    project.opts[:headers_dir].should == 'Headers'
    project.opts[:products].should == %w{ libPods.a }
  end

  it "runs the post_install hook" do
    @installer_rep_from_post_install_hook.pods.map(&:name).should == [
      "AFIncrementalStore",
      "AFKissXMLRequestOperation",
      "AFNetworking",
      "InflectorKit",
      "KissXML",
      "TransformerKit"
    ]
  end

  it "removes Pods.bridgesupport whenever the PODS section of Podfile.lock changes" do
    bs_file = @config.pods.bridgesupport_file
    bs_file.open('w') { |f| f.write 'ORIGINAL CONTENT' }
    lock_file = @installer.config.lockfile

    # Even if another section changes, it doesn't remove Pods.bridgesupport
    lockfile_data = lock_file.to_hash
    lockfile_data['DEPENDENCIES'] = []
    Pod::Lockfile.new(lockfile_data).write_to_disk(@installer.config.sandbox.manifest.defined_in_file)
    @config.pods.install!(false)
    bs_file.read.should == 'ORIGINAL CONTENT'

    # If the PODS section changes, then Pods.bridgesupport is removed
    lockfile_data = lock_file.to_hash
    lockfile_data['PODS'] = []
    Pod::Lockfile.new(lockfile_data).write_to_disk(@installer.config.sandbox.manifest.defined_in_file)
    @installer.config.instance_variable_set(:@lockfile, nil)
    @config.pods.install!(false)
    bs_file.should.not.exist
  end
end
