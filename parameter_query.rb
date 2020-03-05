#!/usr/bin/env ruby
require 'rubygems'
require 'ruby-osc'
require 'pp'
require 'socket'
require 'logger'
require 'strscan'

$logger = Logger.new(STDERR)
$logger.info "Starting up..."

$PARAMETER_COUNT = nil
$METER_COUNT = nil
$SS_COUNT = nil

class Console
  attr_accessor :ip

  def initialize(ip:)
    @ip = ip
    connect
  end

  def connect
    raise 'Already running a loop thread' if @connection_thread
    @connection_thread = Thread.new {
      loop do
        $logger.info "Connecting to #{ip}"
        @socket = TCPSocket.new @ip, 49280
        $logger.info "Connected to console #{ip}"
        while line = @socket.gets.chomp
          
          # OK get MIXER:Current/InCh/Label/Name 0 0 "Qlab L"
          # NOTIFY set MIXER:Current/InCh/Fader/Level 1 0 -2000 "-20.00"
          scanner = StringScanner.new line
          call = {}
          call[:type] = scanner.scan(/(OK|NOTIFY)/i)
          scanner.scan(/\s/)
          call[:command] = scanner.scan(/(\S+)/i)
          scanner.scan(/\s/)
          
          if call[:command] == 'prminfo'
            scanner.scan(/(\d+)\s\"(\S+)\"\s/i)
            call[:parameter_number] = scanner.captures[0]
            call[:path] = scanner.captures[1]
            call[:arguments] = scanner.rest.split(' ')
            File.write('new_.txt', "#{call[:parameter_number]},#{call[:path]},#{call[:arguments].join(',')}\r\n", mode: 'a')
          elsif call[:command] == 'prmnum'
            call[:parameter_count] = scanner.scan(/(\d+)/i).to_i
            $PARAMETER_COUNT = call[:parameter_count]
          elsif call[:command] == 'mtrnum'
            call[:meter_count] = scanner.scan(/(\d+)/i).to_i
            $METER_COUNT = call[:meter_count]
          elsif call[:command] == 'ssnum'
            call[:ss_count] = scanner.scan(/(\d+)/i).to_i
            $SS_COUNT = call[:ss_count]
          else
            call[:arguments] = scanner.rest.split(' ')
          end
          
          
          $logger.debug "TCP< #{line}"
          $logger.debug "Here: #{call}"

#$logger.debug "Parameter #{call[:param_number]} => #{call[:path]} (#{call[:args]})"
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
#    $logger.debug "TCP> #{message}"
    @socket.flush
  end

end


@console = Console.new( ip: '10.102.0.4' )
sleep 1
@console.send_raw("PRMNUM")
@console.send_raw("MTRNUM")
@console.send_raw("SSNUM")
sleep 1

if $PARAMETER_COUNT
  0.upto($PARAMETER_COUNT-1) do |i|
    @console.send_raw("PRMINFO #{i}")
    sleep 0.1
  end
else
  $logger.debug "did not get a valid parameter count back from the device"
end

if $METER_COUNT
  0.upto($METER_COUNT-1) do |i|
    @console.send_raw("MTRINFO #{i}")
    sleep 0.1
  end
else
  $logger.debug "did not get a valid meter count back from the device"
end

if $SS_COUNT
  0.upto($SS_COUNT-1) do |i|
    @console.send_raw("SSINFO #{i}")
    sleep 0.1
  end
else
  $logger.debug "did not get a valid ss count back from the device"
end

