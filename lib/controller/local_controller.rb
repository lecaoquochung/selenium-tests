%w(jenkins_controller log_watcher).each { |f| require File.dirname(__FILE__)+"/"+f }

# Abstract base class for those JenkinsController that runs the JVM locally on
# the same box as the test harness
class LocalJenkinsController < JenkinsController
  attr_accessor :real_update_center

  # @param [Hash] opts
  #     :war  => specify the location of jenkins.war
  def initialize(opts)
    super()
    @war = opts[:war] || ENV['JENKINS_WAR'] || File.expand_path("#{WORKSPACE}/jenkins.war")
    raise "jenkins.war doesn't exist in #{@war}, maybe you forgot to set JENKINS_WAR env var?" if !File.exists?(@war)

    @tempdir = TempDir.create(:rootpath => WORKSPACE)

    # Chose a random port, just to be safe
    @real_update_center = opts[:real_update_center] || false

    # copy it into $JENKINS_HOME/plugins
    @path_element_hpi = download_path_element
    plugins_dir = @tempdir+'/plugins'
    Dir.mkdir plugins_dir

    if ENV['PLUGINS_DIR']
      FileUtils.cp_r Dir.glob(ENV['PLUGINS_DIR'] + '/*.[hj]pi'), plugins_dir
    end

    FileUtils.copy_file(@path_element_hpi,"#{plugins_dir}/path-element.hpi")
  end

  # to be supplied by subclass.
  # @return
  #   IO that represents the process
  def start_process
    raise "#{self.class} hasn't implemented start_process method"
  end

  def start!
    ENV["JENKINS_HOME"] = @tempdir
    puts
    print "    Bringing up a temporary Jenkins instance"
    @pipe = start_process
    @pid = @pipe.pid

    @log_watcher = LogWatcher.new(@pipe,@log)
    @log_watcher.wait_for_ready

    # still seeing occasional first page load problem. adding a bit more delay
    sleep 1
  end

  def teardown
    unless @log.nil?
      @log.close
      @log = nil
    end
    FileUtils.rm_rf(@tempdir)
  end

  def diagnose
    if ENV["INTERACTIVE"] == 'true'
      puts 'Commencing interactive debugging. Browser session was kept open.'
      puts 'Press return to proceed.'
      STDIN.getc
    else
      puts "It looks like the test failed/errored, so here's the console from Jenkins:"
      puts "--------------------------------------------------------------------------"
      File.open(JENKINS_DEBUG_LOG, 'r') do |fd|
        fd.each_line do |line|
          puts line
        end
      end
    end
  end

  protected
  # Get free random local port in specified range
  def random_local_port(opts = {})
    from = opts[:from] || 1024
    to = opts[:to] || 65535

    loop do
      candidate = rand(to - from) + from
      return candidate if port_free?(candidate)
      puts "Port #{candidate} is in use"
    end
  end

  def port_free?(port)
    TCPSocket.open("localhost", port).close
    false
  rescue Errno::ECONNREFUSED # No one is listening
    true
  end
end
