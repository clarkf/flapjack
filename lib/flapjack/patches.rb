#!/usr/bin/env ruby

require 'thin'
require 'resque'
require 'redis'

# we don't want to stop the entire EM reactor when we stop a web server
# & @connections data type changed in thin 1.5.1
module Thin

  # see https://github.com/flapjack/flapjack/issues/169
  class Request
    class EqlTempfile < ::Tempfile
      def eql?(obj)
        obj.equal?(self) && (obj == self)
      end
    end

    def move_body_to_tempfile
      current_body = @body
      current_body.rewind
      @body = Thin::Request::EqlTempfile.new(BODY_TMPFILE)
      @body.binmode
      @body << current_body.read
      @env[RACK_INPUT] = @body
    end
  end

  module Backends
    class Base
      def stop!
        @running  = false
        @stopping = false

        # EventMachine.stop if EventMachine.reactor_running?

        case @connections
        when Array
          @connections.each { |connection| connection.close_connection }
        when Hash
          @connections.each_value { |connection| connection.close_connection }
        end
        close
      end
    end
  end
end

# Resque is really designed around a multiprocess model, so we here we
# stub some that behaviour away.
module Resque

  class Worker

    def procline(string)
      # $0 = "resque-#{Resque::Version}: #{string}"
      # log! $0
    end

    # Redefining the entire method to stop the direct access to $0 :(
    def work(interval = 5.0, &block)
      interval = Float(interval)
      # $0 = "resque: Starting"
      startup

      loop do

        break if shutdown?

        if not paused? and job = reserve
          log "got: #{job.inspect}"
          job.worker = self
          run_hook :before_fork, job
          working_on job

          if @child = fork
            srand # Reseeding
            procline "Forked #{@child} at #{Time.now.to_i}"
            Process.wait(@child)
          else
            unregister_signal_handlers if !@cant_fork && term_child
            procline "Processing #{job.queue} since #{Time.now.to_i}"
            redis.client.reconnect if !@cant_fork # Don't share connection with parent
            perform(job, &block)
            exit! unless @cant_fork
          end

          done_working
          @child = nil
        else
          break if interval.zero?
          log! "Sleeping for #{interval} seconds"
          procline paused? ? "Paused" : "Waiting for #{@queues.join(',')}"
          sleep interval
        end
      end

      unregister_worker
    rescue Exception => exception
      unregister_worker(exception)
    end

  end
end

# As Redis::Future objects inherit from BasicObject, it's difficult to
# distinguish between them and other objects in collected data from
# pipelined queries.
#
# (One alternative would be to put other values in Futures ourselves, and
#  evaluate everything...)
class Redis
  class Future
    def class
      ::Redis::Future
    end
  end
end

module GLI
  class Command
    attr_accessor :passthrough
    def _action
      @action
    end
  end

  class GLIOptionParser
    class NormalCommandOptionParser
      def parse!(parsing_result)
        parsed_command_options = {}
        command = parsing_result.command
        arguments = nil

        loop do
          command._action.call if command.passthrough

          option_parser_factory       = OptionParserFactory.for_command(command,@accepts)
          option_block_parser         = CommandOptionBlockParser.new(option_parser_factory, self.error_handler)
          option_block_parser.command = command
          arguments                   = parsing_result.arguments

          arguments = option_block_parser.parse!(arguments)

          parsed_command_options[command] = option_parser_factory.options_hash_with_defaults_set!
          command_finder                  = CommandFinder.new(command.commands,command.get_default_command)
          next_command_name               = arguments.shift

          gli_major_version, gli_minor_version = GLI::VERSION.split('.')
          required_options = case
          when gli_major_version.to_i == 2 && gli_minor_version.to_i <= 10
            [command.flags, parsed_command_options[command]]
          else
            [command.flags, parsing_result.command, parsed_command_options[command]]
          end
          verify_required_options!(*required_options)

          begin
            command = command_finder.find_command(next_command_name)
          rescue AmbiguousCommand
            arguments.unshift(next_command_name)
            break
          rescue UnknownCommand
            arguments.unshift(next_command_name)
            # Although command finder could certainy know if it should use
            # the default command, it has no way to put the "unknown command"
            # back into the argument stack.  UGH.
            unless command.get_default_command.nil?
              command = command_finder.find_command(command.get_default_command)
            end
            break
          end
        end

        parsed_command_options[command] ||= {}
        command_options = parsed_command_options[command]

        this_command          = command.parent
        child_command_options = command_options

        while this_command.kind_of?(command.class)
          this_command_options = parsed_command_options[this_command] || {}
          child_command_options[GLI::Command::PARENT] = this_command_options
          this_command = this_command.parent
          child_command_options = this_command_options
        end

        parsing_result.command_options = command_options
        parsing_result.command = command
        parsing_result.arguments = Array(arguments.compact)
        parsing_result
      end
    end
  end
end
