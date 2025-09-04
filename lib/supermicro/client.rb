# frozen_string_literal: true

require 'faraday'
require 'faraday/multipart'
require 'nokogiri'
require 'base64'
require 'uri'
require 'httparty'
require 'json'
require 'colorize'

module Supermicro
  class Client
    attr_reader :host, :username, :password, :port, :use_ssl, :verify_ssl, :session, :host_header
    attr_accessor :direct_mode, :verbosity, :retry_count, :retry_delay
    
    include Power
    include Debuggable
    include Jobs
    include Storage
    include System
    include VirtualMedia
    include Boot
    include Bios
    include SystemConfig
    include Utility
    include License
    include Tasks
    include Network

    def initialize(host:, username:, password:, port: 443, use_ssl: true, verify_ssl: false, direct_mode: false, retry_count: 3, retry_delay: 1, host_header: nil)
      @host = host
      @username = username
      @password = password
      @port = port
      @use_ssl = use_ssl
      @verify_ssl = verify_ssl
      @direct_mode = direct_mode
      @host_header = host_header
      @verbosity = 0
      @retry_count = retry_count
      @retry_delay = retry_delay
      
      @session = Session.new(self)
      
      ObjectSpace.define_finalizer(self, self.class.finalizer(@session))
    end

    def self.finalizer(session)
      proc do
        begin
          session.delete if session.x_auth_token
        rescue
        end
      end
    end

    def self.connect(host:, username:, password:, **options)
      client = new(host: host, username: username, password: password, **options)
      return client unless block_given?
      
      begin
        client.login
        yield client
      ensure
        client.logout
      end
    end

    def connection
      @connection ||= Faraday.new(url: base_url, ssl: { verify: verify_ssl }) do |faraday|
        faraday.request :multipart
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
        if @verbosity > 0
          faraday.response :logger, Logger.new(STDOUT), bodies: @verbosity >= 2 do |logger|
            logger.filter(/(Authorization: Basic )([^,\n]+)/, '\1[FILTERED]')
            logger.filter(/(Password"=>"?)([^,"]+)/, '\1[FILTERED]')
          end
        end
      end
    end

    def login
      if @direct_mode
        debug "Using direct mode (Basic Auth) for all requests", 1, :light_yellow
        return true
      end
      
      if session.create
        debug "Successfully logged in to Supermicro BMC using Redfish session", 1, :green
        return true
      else
        debug "Failed to create Redfish session, falling back to direct mode", 1, :light_yellow
        @direct_mode = true
        return true
      end
    end

    def logout
      session.delete if session.x_auth_token
      debug "Logged out from Supermicro BMC", 1, :green
      return true
    end

    def authenticated_request(method, path, body: nil, headers: {}, timeout: nil, open_timeout: nil, **options)
      request_options = {
        body: body,
        headers: headers,
        timeout: timeout,
        open_timeout: open_timeout
      }.merge(options).compact
      
      with_retries do
        _perform_authenticated_request(method, path, request_options)
      end
    end

    def get(path:, headers: {})
      with_retries do
        _perform_get(path: path, headers: headers)
      end
    end

    def base_url
      protocol = use_ssl ? 'https' : 'http'
      "#{protocol}://#{host}:#{port}"
    end

    def redfish_version
      response = authenticated_request(:get, "/redfish/v1")
      if response.status == 200
        data = JSON.parse(response.body)
        data["RedfishVersion"]
      else
        raise Error, "Failed to get Redfish version: #{response.status} - #{response.body}"
      end
    end

    def get_firmware_version
      response = authenticated_request(:get, "/redfish/v1/Managers/1?$select=FirmwareVersion")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          return data["FirmwareVersion"]
        rescue JSON::ParserError
          raise Error, "Failed to parse firmware version response: #{response.body}"
        end
      else
        response = authenticated_request(:get, "/redfish/v1/Managers/1")
        
        if response.status == 200
          begin
            data = JSON.parse(response.body)
            return data["FirmwareVersion"]
          rescue JSON::ParserError
            raise Error, "Failed to parse firmware version response: #{response.body}"
          end
        else
          raise Error, "Failed to get firmware version. Status code: #{response.status}"
        end
      end
    end

    def with_retries(max_retries = nil, initial_delay = nil, error_classes = nil)
      max_retries ||= @retry_count
      initial_delay ||= @retry_delay
      error_classes ||= [StandardError]
      
      retries = 0
      begin
        yield
      rescue *error_classes => e
        retries += 1
        if retries <= max_retries
          delay = initial_delay * (retries ** 1.5).to_i
          debug "RETRY: #{e.message} - Attempt #{retries}/#{max_retries}, waiting #{delay}s", 1, :yellow
          sleep delay
          retry
        else
          debug "MAX RETRIES REACHED: #{e.message} after #{max_retries} attempts", 1, :red
          raise e
        end
      end
    end

    def wait_for_task(task_id)
      task = nil
      
      begin
        loop do
          task_response = authenticated_request(:get, "/redfish/v1/TaskService/Tasks/#{task_id}")
          
          case task_response.status
          when 200..299
            task = JSON.parse(task_response.body)

            if task["TaskState"] != "Running"
              break
            end
            
            percent_complete = nil
            if task["Oem"] && task["Oem"]["Supermicro"] && task["Oem"]["Supermicro"]["PercentComplete"]
              percent_complete = task["Oem"]["Supermicro"]["PercentComplete"]
              debug "Task progress: #{percent_complete}% complete", 1
            end
            
            debug "Waiting for task to complete...: #{task["TaskState"]} #{task["TaskStatus"]}", 1
            sleep 5
          else
            return { 
              status: :failed, 
              error: "Failed to check task status: #{task_response.status} - #{task_response.body}" 
            }
          end
        end
        
        if task["TaskState"] == "Completed" && task["TaskStatus"] == "OK"
          return { status: :success }
        else
          debug task.inspect, 1, :yellow
          
          messages = []
          if task["Messages"] && task["Messages"].is_a?(Array)
            messages = task["Messages"].map { |m| m["Message"] }.compact
          end
          
          return { 
            status: :failed, 
            task_state: task["TaskState"], 
            task_status: task["TaskStatus"],
            messages: messages,
            error: messages.first || "Task failed with state: #{task["TaskState"]}"
          }
        end
      rescue => e
        return { status: :error, error: "Exception monitoring task: #{e.message}" }
      end
    end

    def handle_response(response)
      if response.headers["location"]
        return handle_location(response.headers["location"])
      end

      if response.status.between?(200, 299)
        return response.body
      else
        raise Error, "Failed to #{response.status} - #{response.body}"
      end
    end

    def handle_location(location)
      return nil if location.nil? || location.empty?
      
      id = location.split("/").last
      
      if location.include?("/TaskService/Tasks/")
        wait_for_task(id)
      else
        wait_for_job(id) if respond_to?(:wait_for_job)
      end
    end

    private
    
    def _perform_authenticated_request(method, path, options = {}, retry_count = 0)
      if retry_count >= @retry_count
        debug "Maximum retry count reached", 1, :red
        raise Error, "Failed to authenticate after #{@retry_count} retries"
      end
      
      debug "Authenticated request: #{method.to_s.upcase} #{path}", 1
      
      body = options[:body]
      headers = options[:headers] || {}
      timeout = options[:timeout]
      open_timeout = options[:open_timeout]
      
      headers['User-Agent'] ||= 'Supermicro Ruby Client'
      headers['Accept'] ||= 'application/json'
      headers['Host'] = @host_header if @host_header
      
      if body && @verbosity >= 2
        debug "Request body: #{body}", 2
      end
      
      if @direct_mode
        headers['Authorization'] = "Basic #{Base64.strict_encode64("#{username}:#{password}")}"
        debug "Using Basic Auth for request (direct mode)", 2
      elsif session.x_auth_token
        headers['X-Auth-Token'] = session.x_auth_token
        debug "Using X-Auth-Token for authentication", 2
      end
      
      response = make_request_with_timeouts(method, path, body, headers, timeout, open_timeout)
      
      case response.status
      when 301, 302, 303, 307, 308
        # Handle redirects
        if response.headers['location']
          new_path = response.headers['location']
          # If it's a relative path, keep it as is; if absolute URL, extract the path
          if new_path.start_with?('http')
            new_path = URI.parse(new_path).path
          end
          debug "Redirecting to: #{new_path}", 2
          return _perform_authenticated_request(method, new_path, options, retry_count)
        else
          response
        end
      when 401, 403
        handle_auth_failure(method, path, options, retry_count)
      else
        debug "Response status: #{response.status}", 2
        response
      end
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
      handle_connection_error(e, method, path, options, retry_count)
    rescue => e
      handle_general_error(e, method, path, options, retry_count)
    end
    
    def make_request_with_timeouts(method, path, body, headers, timeout, open_timeout)
      conn = session.connection
      original_timeout = conn.options.timeout
      original_open_timeout = conn.options.open_timeout
      
      begin
        conn.options.timeout = timeout if timeout
        conn.options.open_timeout = open_timeout if open_timeout
        
        conn.run_request(method, path, body, headers)
      ensure
        conn.options.timeout = original_timeout
        conn.options.open_timeout = original_open_timeout
      end
    end
    
    def handle_auth_failure(method, path, options, retry_count)
      if @direct_mode
        debug "Authentication failed in direct mode, retrying...", 1, :light_yellow
        sleep(retry_count + 1)
        return _perform_authenticated_request(method, path, options, retry_count + 1)
      else
        debug "Session expired, creating new session...", 1, :light_yellow
        session.delete if session.x_auth_token
        
        if session.create
          debug "New session created, retrying request...", 1, :green
          return _perform_authenticated_request(method, path, options, retry_count + 1)
        else
          debug "Session creation failed, falling back to direct mode...", 1, :light_yellow
          @direct_mode = true
          return _perform_authenticated_request(method, path, options, retry_count + 1)
        end
      end
    end
    
    def handle_connection_error(error, method, path, options, retry_count)
      debug "Connection error: #{error.message}", 1, :red
      sleep(retry_count + 1)
      
      if @direct_mode || session.x_auth_token
        return _perform_authenticated_request(method, path, options, retry_count + 1)
      elsif session.create
        debug "Created new session after connection error", 1, :green
        return _perform_authenticated_request(method, path, options, retry_count + 1)
      else
        @direct_mode = true
        return _perform_authenticated_request(method, path, options, retry_count + 1)
      end
    end
    
    def handle_general_error(error, method, path, options, retry_count)
      debug "Error during request: #{error.message}", 1, :red
      
      if @direct_mode
        raise Error, "Error during authenticated request: #{error.message}"
      elsif session.create
        debug "Created new session after error, retrying...", 1, :green
        return _perform_authenticated_request(method, path, options, retry_count + 1)
      else
        @direct_mode = true
        return _perform_authenticated_request(method, path, options, retry_count + 1)
      end
    end

    def _perform_get(path:, headers: {})
      debug "GET request to #{base_url}/#{path}", 1
      
      headers_to_use = {
        "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36",
        "Accept-Encoding" => "deflate, gzip"
      }
      headers_to_use["Host"] = @host_header if @host_header
      
      if @direct_mode
        headers_to_use["Authorization"] = "Basic #{Base64.strict_encode64("#{username}:#{password}")}"
        debug "Using Basic Auth for GET request", 2
      elsif session.x_auth_token
        headers_to_use["X-Auth-Token"] = session.x_auth_token
        debug "Using X-Auth-Token for GET request", 2
      end
      
      debug "Request headers: #{headers_to_use.merge(headers).inspect}", 3
      
      response = HTTParty.get(
        "#{base_url}/#{path}",
        headers: headers_to_use.merge(headers),
        verify: false
      )
      
      debug "Response status: #{response.code}", 1
      debug "Response headers: #{response.headers.inspect}", 2
      debug "Response body: #{response.body.to_s[0..500]}#{response.body.to_s.length > 500 ? '...' : ''}", 3 if response.body
      
      response
    end
  end
end