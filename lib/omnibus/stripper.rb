require "omnibus/sugarable"

module Omnibus
  class Stripper
    include Instrumentation
    include Logging
    include Util
    include Sugarable

    class << self
      # @see (stripper#new)
      def run!(project)
        new(project).run!
      end
    end

    #
    # The project to strip.
    #
    # @return [Project]
    #
    attr_reader :project

    #
    # Run the stripper against the given project. It is assumed that the
    # project has already been built.
    #
    # @param [Project] project
    #   the project to strip
    #
    def initialize(project)
      @project = project
    end

    #
    # Run the stripping operation. Stripping currently only available on windows.
    #
    # TODO: implement other platforms windows, macOS, etc
    #
    # @return [true]
    #   if the checks pass
    #
    def run!
      measure("Stripping time") do
        log.info(log_key) { "Running strip on #{project.name}" }
        # TODO: properly address missing platforms / linux
        case Ohai["platform"]
        when "mac_os_x"
          log.warn(log_key) { "Currently unsupported in macOS platforms." }
        when "aix"
          log.warn(log_key) { "Currently unsupported in AIX platforms." }
        when "windows"
          log.warn(log_key) { "Currently unsupported in windows platforms." }
        else
          strip_linux
        end
      end
    end

    def strip_linux
      path = project.install_dir
      log.info(log_key) { "Stripping ELF symbols for #{project.name}" }
      cmd = shellout("find #{path}/ -type f -exec file {} \\; | grep 'ELF' | cut -f1 -d:")
      cmd.stdout.each_line do |elf|
        log.debug(log_key) { "processing: #{elf}" }
        source = elf.strip
        writable(source) do
          shellout!("strip --strip-debug --strip-unneeded #{source}")
        end
      end
    end

    private
    def writable(source)
      mode = nil
      if ! File.writable?(source)
        mode = File.stat(source).mode
        File.chmod(mode | 0200, source)
      end
      yield
    ensure
      File.chmod(mode, source) unless mode.nil?
    end
  end
end
