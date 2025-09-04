# frozen_string_literal: true

require_relative 'spinner'

module Supermicro
  module Tasks
    include SpinnerHelper
    
    def poll_task(task_location, timeout: 30, show_progress: true)
      debug "Polling task: #{task_location}", 2
      
      start_time = Time.now
      last_percent = 0
      task_name = task_location.split('/').last
      
      # Use spinner if not in verbose mode
      if show_progress && (!respond_to?(:verbosity) || verbosity == 0)
        spinner = Spinner.new("Processing task #{task_name}", type: :dots, color: :cyan)
        spinner.start
      else
        spinner = nil
      end
      
      begin
        while (Time.now - start_time) < timeout
          task_response = authenticated_request(:get, task_location)
          
          # TaskMonitor returns 202 while running, then eventually returns the actual task
          if task_response.status == 202
            # Try to parse the 202 response for any status info
            begin
              if task_response.body && !task_response.body.empty?
                monitor_data = JSON.parse(task_response.body)
                if monitor_data['TaskState']
                  # We got task info even with 202
                  task_info = monitor_data
                  # Process it below
                else
                  spinner&.update("Waiting for task to start...")
                  debug "  Task pending (202 status)...", 3
                  sleep 1
                  next
                end
              else
                spinner&.update("Task initializing...")
                debug "  Task still initializing...", 3
                sleep 1
                next
              end
            rescue JSON::ParserError
              spinner&.update("Task running...")
              debug "  Task running (202)...", 3
              sleep 1
              next
            end
          elsif task_response.status == 200
            begin
              task_info = JSON.parse(task_response.body)
            rescue JSON::ParserError => e
              debug "Could not parse task response: #{e.message}", 2, :yellow
              sleep 1
              next
            end
          elsif task_response.status == 404
            # TaskMonitor endpoint not found - this is an error
            spinner&.stop("Task endpoint not found", success: false)
            debug "Task endpoint returned 404 - cannot monitor task", 1, :red
            return { success: false, error: 'task_endpoint_not_found' }
          elsif task_response.status == 400
            # 400 can indicate task completion with error details in body
            begin
              if task_response.body && !task_response.body.empty?
                task_info = JSON.parse(task_response.body)
                
                # Check if this is a completed task with error
                if task_info['TaskState'] == 'Exception'
                  spinner&.stop("Task failed: #{task_info['Message']}", success: false)
                  debug "✗ Task failed: #{task_info['Message']}", 1, :red
                  return { success: false, task: task_info, error: task_info['Message'] }
                elsif task_info['TaskState'] == 'Completed'
                  spinner&.stop("Task completed", success: true)
                  debug "✓ Task completed", 2, :green
                  return { success: true, task: task_info }
                else
                  # Unknown 400 response
                  debug "Unexpected 400 response with TaskState: #{task_info['TaskState']}", 2, :yellow
                  sleep 1
                  next
                end
              end
            rescue JSON::ParserError
              debug "400 response but couldn't parse body: #{task_response.body}", 1, :red
              return { success: false, error: 'bad_request' }
            end
          else
            debug "Unexpected task response: #{task_response.status}", 2, :yellow
            sleep 1
            next
          end
          
          # Process task_info if we have it
          if defined?(task_info) && task_info && task_info['TaskState']
            percent = task_info['PercentComplete'] || 0
            if percent > 0 && percent != last_percent
              spinner&.update("Task progress: #{percent}%")
              debug "  Task progress: #{percent}%", 2
              last_percent = percent
            end
            
            case task_info['TaskState']
            when 'Completed'
              spinner&.stop("Task completed successfully", success: true)
              debug "✓ Task completed successfully", 2, :green
              return { success: true, task: task_info }
            when 'Exception', 'Killed', 'Cancelled'
              spinner&.stop("Task failed: #{task_info['TaskState']}", success: false)
              debug "✗ Task failed: #{task_info['TaskState']}", 1, :red
              if task_info['Messages']
                task_info['Messages'].each do |msg|
                  debug "  #{msg['Message']}", 1, :red
                end
              end
              return { success: false, task: task_info }
            when 'Running', 'Starting', 'Pending', 'New'
              # Still running
              state_msg = task_info['TaskState'] == 'Running' ? "Running" : "Starting"
              spinner&.update("Task #{state_msg.downcase}...")
              debug "  Task state: #{task_info['TaskState']}", 3
            else
              spinner&.update("Task state: #{task_info['TaskState']}")
              debug "  Unknown task state: #{task_info['TaskState']}", 2, :yellow
            end
          end
          
          sleep 1
        end
        
        spinner&.stop("Task timed out after #{timeout} seconds", success: false)
        debug "Task polling timed out after #{timeout} seconds", 1, :yellow
        { success: false, error: 'timeout' }
      ensure
        spinner&.stop if spinner
      end
    end
    
    def wait_for_task_completion(response, timeout: 30)
      return { success: true } unless response.status == 202
      
      # Get task location from response
      task_location = response.headers['Location'] || response.headers['location']
      
      if !task_location && response.body && !response.body.empty?
        begin
          task_data = JSON.parse(response.body)
          # Prefer @odata.id over TaskMonitor as TaskMonitor may return 404
          task_location = task_data['@odata.id']
          
          # Only use TaskMonitor if @odata.id is not available
          if !task_location && task_data['TaskMonitor']
            debug "Using TaskMonitor endpoint (may not be supported): #{task_data['TaskMonitor']}", 2, :yellow
            task_location = task_data['TaskMonitor']
          end
        rescue JSON::ParserError
          # No task info in body
        end
      end
      
      if task_location
        debug "Task started: #{task_location}", 2
        poll_task(task_location, timeout: timeout)
      else
        debug "No task location found, assuming synchronous completion", 2
        { success: true }
      end
    end
  end
end