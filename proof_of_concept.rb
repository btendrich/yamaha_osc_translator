#!/usr/bin/env ruby
require 'rubygems'
require 'ruby-osc'
require 'pp'
require 'socket'
require 'logger'
require 'strscan'

$logger = Logger.new(STDERR)
$logger.info "Starting up..."


class Console
  attr_accessor :ip, :model, :retry, :input_channel_count

  MODELS = [:ql1, :ql5, :cl1, :cl3, :cl5]

  def initialize(ip:, model:, do_not_connect: nil, retry: nil)
    @ip = ip
    @model = model
    
    case model
    when :ql1
      @input_channel_count = 32
    when :ql5
      @input_channel_count = 64
    when :cl1
      @input_channel_count = 48
    when :cl3
      @input_channel_count = 64
    when :cl5
      @input_channel_count = 72
    end
    
    raise 'Unknown model type' unless MODELS.include? model
  
#    connect unless do_not_connect
  end

  def connect
    raise 'Already running a loop thread' if @connection_thread
    @connection_thread = Thread.new {
      loop do
        $logger.info "Connecting to #{ip}"
        @socket = TCPSocket.new @ip, 49280
        $logger.info "Connected to console #{ip} (#{model.to_s.upcase})"
        while line = @socket.gets.chomp
          # OK get MIXER:Current/InCh/Label/Name 0 0 "Qlab L"
          # NOTIFY set MIXER:Current/InCh/Fader/Level 1 0 -2000 "-20.00"
          $logger.debug "TCP< #{line}"
          scanner = StringScanner.new line
          call = {}
          call[:type] = scanner.scan(/(OK|NOTIFY)/i)
          scanner.scan(/\s/)
          call[:action] = scanner.scan(/(get|set)/i)
          scanner.scan(/\sMIXER:/i)
          call[:path] = scanner.scan(/\S+/i)
          
          $logger.debug "Here: #{call}"
        end
        s.close
        $logger.warn "Disconnected from console, waiting and reconnecting"
        sleep 5
        break if @retry.nil?
      end
    }
  end
  
  def send_raw(message)
    @socket.write("#{message}\n")
    $logger.debug "TCP> #{message}"
    @socket.flush
  end

end

def validate_level(value, default: "-30000")
  value = "-30000" if value =~ /\-inf/i
  value = value.to_f
  value = 10.0 if value > 10
  value = -999.0 if value < -138.0
  if (-138.0..10.0).include? value
    return (value*100).to_i
  else
    return default
  end
end

LEVEL_PATH_TRANSLATIONS = {
  'channel' => 'InCh',
  'stereo_input' => 'StIn',
  'mix' => 'Mix',
  'matrix' => 'Mtrx',
  'master' => 'St',
  'dca' => 'DCA',
}


include OSC

OSC.run do
  server = Server.new 4444

  @console = Console.new( ip: '10.102.0.4', model: :cl1 )
  @console.connect
  sleep 1

  server.add_pattern /.*/ do |*args|       # this will match any address
    $logger.debug "OSC< #{args.shift} #{args}"
  end

  server.add_pattern /(\w+)\/(\d+)\/level/i do |*args|
    path = args.shift
    type = path.match(/(\w+)/).to_s.downcase
    number = path.match(/(\d+)\/level/i)[1].to_i
    level = validate_level(args.shift.to_f)
    
    if LEVEL_PATH_TRANSLATIONS[type]
      $logger.info "Adjust #{type} number #{number} to level #{level}"
      @console.send_raw("set MIXER:Current/#{LEVEL_PATH_TRANSLATIONS[type]}/Fader/Level #{number-1} 0 #{level}")
    else
      $logger.fatal "Unknown level type '#{type}' for level path '#{path}'"
    end
    
#    @console.send_raw("set MIXER:Current/Mix/Fader/Level #{mix-1} 0 #{level}")
  end

end

abort

@console = Console.new( ip: '10.102.0.5', model: :ql1 )
@console.connect
sleep 1
0.upto(31) do |i|
  @console.send_raw("get MIXER:Current/InCh/Label/Name #{i} 0")
  sleep 1
  puts "get MIXER:Current/InCh/Label/Name #{i} 0"
end

loop do
  sleep 5
end