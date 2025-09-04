# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Jobs
    def jobs
      tasks = jobs_detail
      
      # Return summary format consistent with iDRAC
      {
        completed_count: tasks.count { |t| t["state"] == "Completed" },
        incomplete_count: tasks.count { |t| t["state"] != "Completed" },
        total_count: tasks.count
      }
    end
    
    def jobs_detail
      response = authenticated_request(:get, "/redfish/v1/TaskService/Tasks")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          members = data["Members"] || []
          
          # Supermicro doesn't support expand, so fetch each task individually
          tasks = members.map do |member|
            task_id = member["@odata.id"].split('/').last
            task_response = authenticated_request(:get, member["@odata.id"])
            
            if task_response.status == 200
              task = JSON.parse(task_response.body)
              {
                "id" => task["Id"],
                "name" => task["Name"],
                "state" => task["TaskState"],
                "status" => task["TaskStatus"],
                "percent_complete" => task["PercentComplete"],
                "start_time" => task["StartTime"],
                "end_time" => task["EndTime"],
                "messages" => task["Messages"]
              }
            else
              nil
            end
          end.compact
          
          return tasks
        rescue JSON::ParserError
          raise Error, "Failed to parse tasks response"
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

    def clear_jobs!
      # Note: Supermicro doesn't actually delete tasks - DELETE just marks them as "Killed"
      # The BMC maintains a rolling buffer of tasks (typically ~28-30) with oldest being overwritten
      # This method will "kill" any running tasks but won't remove them from the list
      
      response = authenticated_request(:get, "/redfish/v1/TaskService/Tasks")
      return true unless response.status == 200
      
      data = JSON.parse(response.body)
      members = data["Members"] || []
      
      if members.empty?
        puts "No jobs to clear.".yellow
        return true
      end
      
      # Only try to kill tasks that are actually running
      running_count = 0
      members.each do |member|
        task_id = member["@odata.id"].split('/').last
        task_response = authenticated_request(:get, member["@odata.id"])
        
        if task_response.status == 200
          task = JSON.parse(task_response.body)
          if ["Running", "Starting", "New", "Pending"].include?(task["TaskState"])
            running_count += 1
            puts "Killing task #{task_id}: #{task['Name']} (#{task['TaskState']})".yellow
            authenticated_request(:delete, member["@odata.id"])
          end
        end
      end
      
      if running_count > 0
        puts "Killed #{running_count} running tasks.".green
      else
        puts "No running tasks to kill (#{members.length} completed/killed tasks remain in history).".yellow
      end
      
      true
    end

    def jobs_summary
      all_jobs = jobs_detail
      
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