#!/usr/bin/env ruby

require 'erb'
require 'yaml'

class Yarb
  def description
    "Use Yaml And RuBy to create simple command line tools quickly"
  end

  def usage
    <<~USAGE.chomp
      Usage:
        ~/yarb.rb [command] [arguments] [options]

      Commands:

        help             output this message
        man              complete manual
        eval             load the yml file and evaluate the ruby in the 'eval' key

      Arguments:

        The first arguement is the path to a yml file containing the variables

        The yml file can contain erb and use
          <%= args(n) %> to get the value of arguments at position n
          <%= opts(:key) %> to get the value of `--key value`
          <% if opts?(:key) %> that return true if `--key` is used

      Options:

        --dry-run        dry run the commands
        --verbose        verbose output
        --key value      options, if present `opts(:key)` will return `value`
        --key            flags, if present `flag?(:key)` will return true

      Synopsis

        ~/yarb.rb variables.yml test --dry-run
    USAGE
  end

  def self.command(command, &block)
    @@command[command.to_s] = block
  end

  @@command = {}

  command(:help) { |yarb| yarb.help }

  def help
    template = <<~HELP.chomp
      <%= description %>

      <%= usage %>
    HELP
    ERB.new(template).result(binding)
  end

  command(:man) { |yarb| yarb.manual }

  def manual
    template = <<~MANUAL.chomp
      # [ YARB! ](https://github.com/denislaliberte/yarb)

      <%= description %>

      ## usage

      ```
      <%= usage %>
      ```

      ## Installation

      YARB is a stand alone script using only the ruby standard librairy, install it with wget

      ```
      wget ~ https://raw.githubusercontent.com/denislaliberte/yarb/master/yarb.rb
      chmod -x ~/yarb.rb
      ~/yarb.rb --help
      ```

      ## License
      [MIT](https://choosealicense.com/licenses/mit/)
    MANUAL

    return ERB.new(template).result(binding)
  end

  def initialize(arguments, home)
    @home = home
    @arguments = arguments
    @config = DEFAULT_CONFIG
  end

  DEFAULT_CONFIG = {
    'default_command' => 'help',
  }

  def configure
    load_lib
    @config = override_configuration(@config)
    @arguments = override_arguments(@arguments, @config)
    @template = get_template(get_path(@arguments))
    @data = load_data(@template, @config)
    self
  end

  def execute
    configure
    if flag?(:dry_run)
      YAML.dump(@data).to_s
    else
      execute_command(args(0))
    end
  end

  def flag?(key)
    include?(key)
  end

  command(:eval) { |yarb| yarb.evaluate }

  def evaluate
    if flag?(:help)
      return @template if @data['help'].nil?
      return @data['help']
    end

    return "WARNING nothing to evaluate" if @data['eval'].nil?
    eval(@data['eval'])
  end

  def args(index, default: nil)
    argument = @arguments.reject { |arg| arg.match(/^-/)}.at(index)
    return default if argument.nil?
    argument
  end

  def opts(key, default: nil)
    return default unless include?(key)
    value = argument_value(key)

    if value.nil?
      default
    else
      value
    end
  end

  def config
    @config
  end

  def data
    @data
  end

  def verbose?
    flag?(:verbose)
  end

  def workspace
    "#{@home}/.yrb"
  end

  private

  def override_configuration(original)
    default_path = "#{workspace}/config.yml"
    if File.file?(default_path)
      log("Yarb#override_configuration default_path : #{default_path}")
      config = override(original, YAML.load_file(default_path))
    else
      log("Yarb#override_configuration DEFAULT_CONFIG")
      config = original
    end
    datalog(config: config)

    config
  end

  def log(message)
    puts message if verbose?
  end

  def datalog(data)
    puts YAML.dump(data) if verbose?
  end

  def override(original, override)
    original.merge(override) do |_key, original_value, value|
      value.is_a?(Hash) ? original_value.merge(value) : value
    end
  end

  def load_data(template, original_conf)
    if template
      yaml = ERB.new(template).result(binding)
      config = override(original_conf, YAML.load(yaml))
    else
      config = original_conf
    end
    datalog(config: config)

    config
  end

  def get_template(path)
    if path && File.file?(path)
      log("Yarb#get_template path: #{path}")
      @yaml_template = File.read(path)
    else
      log("Yarb#get_template path: #{path}")
    end
  end

  def get_path(arguments)
    return if arguments[1].nil? || !arguments[1].match(/\.yml$/)
    arguments[1]
  end

  def override_arguments(arguments, config)
    arguments = execute_hook(:before_override_arguments, {yarb: self, arguments: arguments})[:arguments]

    unless command?(arguments[0])
      log("Yarb#override_arguments default_command: #{config['default_command']}")
      arguments.unshift(config['default_command'])
    end

    arguments = execute_hook(:after_override_arguments, {yarb: self, arguments: arguments})[:arguments]

    datalog(arguments: arguments)

    arguments
  end

  @@hooks = Hash.new { |h, k| h[k] = [] }

  def self.register_hook(key, &block)
    @@hooks[key].concat(Array(block))
  end

  def self.clear_hook(key)
    @@hooks[key] = [ ]
  end

  def execute_hook(key, args)
    return args if @@hooks[key].empty?
    @@hooks[key].inject(args) {|arguments, hook| hook.call(arguments) }
  end

  def load_lib
    Dir["#{workspace}/lib/*.rb"].each { |file| require file }
  end

  def include?(key)
    @arguments.include?(string_key(key))
  end

  def string_key(symbol)
    "--#{symbol.to_s.gsub('_','-')}"
  end

  def command?(command)
    !@@command[command].nil?
  end

  def execute_command(command)
    return unless command?(command)
    @@command[command].call(self)
  end

  def argument_value(key)
    index = string_key(key)
    return nil if @arguments.index(index).nil?
    position = @arguments.index(index) + 1
    return nil if /^-/.match(@arguments[position])
    @arguments[position]
  end
end

if caller.length == 0
  puts Yarb.new(ARGV, ENV['HOME']).execute
end

