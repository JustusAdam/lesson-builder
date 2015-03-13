require 'pathname'
require 'set'
require 'logger'
require 'fileutils'
require 'json'
require './gittools'


module BuildTools

  VALID_LATEX_COMMANDS = {:htlatex => 'html', :pdflatex => 'pdf'}

  module Compile

    # call a latex command with 'htlatex' as default
    def self.latex_to_html(source_file, command: :htlatex)
      latex source_file, command: command
    end

    # call a latex command and return useful information
    def self.latex(source_file, command: :pdflatex)

      command = command.to_sym

      return_type = VALID_LATEX_COMMANDS[command]

      raise "invalid latex command #{command}" if return_type.nil?

      c = "#{command} -halt-on-error #{source_file}"
      [system("#{c}"), construct_out_file_name(source_file, return_type)]
    end

    private

    # helper method clue is in the name
    def self.construct_out_file_name(path, type)
      path = Pathname path unless path.is_a? Pathname

      File.basename(path, '.*') + ".#{type}"
    end

  end

  module Build

    # build a single source file
    def self.build(source_file, source_dir, target_dir, command)

      source_dir = Pathname source_dir

      cdir = Pathname Dir.getwd

      Dir.chdir source_dir

      success, output_file_name = Compile.latex source_file, command: command

      Dir.chdir cdir

      FileUtils.cp(source_dir + output_file_name, target_dir) if success

      [success, output_file_name]
    end

    # build multiple source files
    def self.batch_build(source_files, source_dir, target_dir, command)

      source_dir = Pathname source_dir

      cdir = Pathname Dir.getwd

      Dir.chdir source_dir

      compile_result = source_files.map do |file|
        Compile.latex file, command: command
      end

      Dir.chdir cdir


      compile_result.zip(source_files).map do |result, source|
        success, file = result

        FileUtils.cp(source_dir + file, target_dir) if success

        [success, source_dir + source, target_dir + file]
      end

    end

    def self.build_include(conf)
      if conf.include? 'git_url'
        build_include_with_git conf
      else
        build_include_from_dir conf
      end
    end

    def self.build_include_with_git(conf)

      source_dir = Pathname conf.fetch('source_dir', self.folder_from_git_url(conf['git_url']))

      if File.exist? source_dir
        raise 'Not a repository' unless File.exist? (source_dir + '.git')
        Dir.chdir source_dir
        begin
          Git.pull
        rescue 'Pull failed'
          raise 'Source folder exists but pull failed, make sure the repository is configured properly'
        end
      else
        git.clone conf['git_url'], source_dir
      end

      build_directory source_dir, conf.fetch('target_dir', source_dir + 'build'), conf.fetch('build_includes', nil)
    end

    def self.build_include_from_dir(conf)
      source_dir = Pathname conf['source_dir']

      raise "source directory #{source_dir} for include #{conf['name']} does not exist" unless Dir.exist? source_dir

      build_directory source_dir, conf.fetch('target_dir', source_dir + 'build'), conf.fetch('build_includes', nil)
    end

    # Build all source files in a directory based on a build_conf.json in that directory
    def self.build_directory(source, target_dir, build_includes: nil)

      # read config
      source = Pathname source
      conf = read_conf source

      # make switches
      build_includes = conf.fetch('build_includes', true) if build_includes.nil?

      source = conf['source_dir'] if source.nil?

      target_dir = conf.fetch('target_dir', source + 'build') if target_dir.nil?
      target_dir = Pathname target_dir
      pdf_command = conf.fetch 'pdf_latex_command', 'pdflatex'
      html_command = conf.fetch 'html_latex_command', 'htlatex'


      if build_includes

        include_builds = conf.fetch('include', []).map &method(:build_include)

        included_html_builds, included_pdf_builds = include_builds.map do |r|
          [r[:html], r[:pdf]]
        end.transpose.map do |list|
          list.flatten
        end

      else
        included_html_builds, included_pdf_builds = [[],[]]
      end

      build_sources = conf.fetch 'files', []

      # filter for lessons that will be html built
      html_builds = build_sources.select do |source_file_conf|
        source_file_conf.fetch 'html', false
      end

      # filter for lessons that will be pdf built
      pdf_builds = build_sources.select do |source_file_conf|
        source_file_conf.fetch 'pdf', false
      end

      # get the file names
      html_builds = html_builds.map do |source_file|
        source_file.fetch 'source', "lesson_#{source_file['number']}.tex"
      end

      pdf_builds = pdf_builds.map do |source_file|
        source_file.fetch 'source', "lesson_#{source_file['number']}.tex"
      end

      # build html
      html_res = batch_build html_builds, source, target_dir, html_command

      # build pdf
      pdf_res = batch_build pdf_builds, source, target_dir, pdf_command

      { :html => html_res + included_html_builds, :pdf => pdf_res + included_pdf_builds }

    end

    # Same as build_directory but also prints some useful output to the console
    def self.build_dir_with_output(source, target)
      start_time = Time.new

      built = build_directory source, target

      puts "Built #{built[:html].length + built[:pdf].length} files in #{Time.new - start_time}"
      built.each do |_, list|
        list.each do |result, original, compiled|
          if result
            result = 'success'
          else
            result = 'errored'
          end

          puts "#{original}  ->  #{compiled}   #{result}"
        end
      end
    end

    private

    def self.folder_from_git_url(url)
      url.rpartition('/')[2].rpartition('.')[0]
    end

    def self.read_conf(source)
      JSON.parse File.read(source + CONFIG_NAME)
    end
  end
end