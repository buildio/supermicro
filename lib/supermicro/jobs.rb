# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Jobs
    def jobs
      response = authenticated_request(:get, "/redfish/v1/TaskService/Tasks?$expand=*($levels=1)")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          tasks = data["Members"]&.map do |task|
            {
              "id" => task["Id"],
              "name" => task["Name"],
              "state" => task["TaskState"],
              "status" => task["TaskStatus"],
              "percent_complete" => task["PercentComplete"] || task.dig("Oem", "Supermicro", "PercentComplete"),
              "start_time" => task["StartTime"],
              "end_time" => task["EndTime"],
              "messages" => task["Messages"]
            }
          end || []
          
          return tasks
        rescue JSON::ParserError
          raise Error, "Failed to parse tasks response: #{response.body}"
        end
      else
        []
      end
    end

    def job_status(job_id)
      response = authenticated_request(:get, "/redfish/v1/TaskService/Tasks/#{job_id}")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          {
            "id" => data["Id"],
            "name" => data["Name"],
            "state" => data["TaskState"],
            "status" => data["TaskStatus"],
            "percent_complete" => data["PercentComplete"] || data.dig("Oem", "Supermicro", "PercentComplete"),
            "start_time" => data["StartTime"],
            "end_time" => data["EndTime"],
            "messages" => data["Messages"]
          }
        rescue JSON::ParserError
          raise Error, "Failed to parse job status response: #{response.body}"
        end
      else
        raise Error, "Failed to get job status. Status code: #{response.status}"
      end
    end

    def wait_for_job(job_id, timeout: 600)
      start_time = Time.now
      
      puts "Waiting for job #{job_id} to complete...".yellow
      
      loop do
        if Time.now - start_time > timeout
          raise Error, "Job #{job_id} timed out after #{timeout} seconds"
        end
        
        begin
          status = job_status(job_id)
          
          case status["state"]
          when "Completed", "Killed", "Exception", "Cancelled"
            if status["status"] == "OK" || status["status"] == "Completed"
              puts "Job completed successfully.".green
              return { status: :success, job: status }
            else
              puts "Job failed: #{status["status"]}".red
              return { status: :failed, job: status, error: status["messages"] }
            end
          when "Running", "Starting", "New", "Pending"
            percent = status["percent_complete"]
            if percent
              puts "Job progress: #{percent}%".cyan
            else
              puts "Job is #{status["state"]}...".cyan
            end
            sleep 5
          else
            puts "Unknown job state: #{status["state"]}".yellow
            sleep 5
          end
        rescue => e
          debug "Error checking job status: #{e.message}", 1, :yellow
          sleep 5
        end
      end
    end

    def cancel_job(job_id)
      puts "Cancelling job #{job_id}...".yellow
      
      response = authenticated_request(
        :delete,
        "/redfish/v1/TaskService/Tasks/#{job_id}"
      )
      
      if response.status.between?(200, 299)
        puts "Job cancelled successfully.".green
        return true
      else
        raise Error, "Failed to cancel job: #{response.status} - #{response.body}"
      end
    end

    def clear_completed_jobs
      all_jobs = jobs
      completed = all_jobs.select { |j| j["state"] == "Completed" }
      
      if completed.empty?
        puts "No completed jobs to clear.".yellow
        return true
      end
      
      puts "Clearing #{completed.length} completed jobs...".yellow
      
      success = true
      completed.each do |job|
        begin
          response = authenticated_request(
            :delete,
            "/redfish/v1/TaskService/Tasks/#{job["id"]}"
          )
          
          if response.status.between?(200, 299)
            puts "  Cleared: #{job["name"]} (#{job["id"]})".green
          else
            puts "  Failed to clear: #{job["name"]} (#{job["id"]})".red
            success = false
          end
        rescue => e
          puts "  Error clearing #{job["id"]}: #{e.message}".red
          success = false
        end
      end
      
      success
    end

    def jobs_summary
      all_jobs = jobs
      
      puts "\n=== Jobs Summary ===".green
      
      if all_jobs.empty?
        puts "No jobs found.".yellow
        return all_jobs
      end
      
      by_state = all_jobs.group_by { |j| j["state"] }
      
      by_state.each do |state, state_jobs|
        puts "\n#{state}:".cyan
        state_jobs.each do |job|
          percent = job["percent_complete"] ? " (#{job["percent_complete"]}%)" : ""
          puts "  #{job["name"]} - #{job["status"]}#{percent}".light_cyan
          puts "    ID: #{job["id"]}"
          puts "    Started: #{job["start_time"]}" if job["start_time"]
          puts "    Ended: #{job["end_time"]}" if job["end_time"]
        end
      end
      
      all_jobs
    end
  end
end