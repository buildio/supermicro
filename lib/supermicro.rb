# frozen_string_literal: true

require 'httparty'
require 'nokogiri'
require 'faraday'
require 'faraday/multipart'
require 'base64'
require 'uri'
require 'colorize'
require 'active_support'
require 'active_support/core_ext'
require 'debug' if ENV['RUBY_ENV'] == 'development'

module Supermicro
  module Debuggable
    def debug(message, level = 1, color = :light_cyan)
      return unless respond_to?(:verbosity) && verbosity >= level
      color_method = color.is_a?(Symbol) && String.method_defined?(color) ? color : :to_s
      puts message.send(color_method)
      
      if respond_to?(:verbosity) && verbosity >= 3 && caller.length > 1
        puts "  Called from:".light_yellow
        caller[1..3].each do |call|
          puts "    #{call}".light_yellow
        end
      end
    end
  end

  class Error < StandardError; end
  
  def self.new(options = {})
    Client.new(options)
  end
  
  def self.connect(**options, &block)
    Client.connect(**options, &block)
  end
end

require 'supermicro/version'
require 'supermicro/error'
require 'supermicro/session'
require 'supermicro/spinner'
require 'supermicro/power'
require 'supermicro/jobs'
require 'supermicro/storage'
require 'supermicro/system'
require 'supermicro/tasks'
require 'supermicro/virtual_media'
require 'supermicro/boot'
require 'supermicro/system_config'
require 'supermicro/utility'
require 'supermicro/license'
require 'supermicro/network'
require 'supermicro/client'