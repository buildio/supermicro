# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Utility
    def sel_log
      response = authenticated_request(:get, "/redfish/v1/Managers/1/LogServices/SEL/Entries?$expand=*($levels=1)")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          entries = data["Members"]&.map do |entry|
            {
              "id" => entry["Id"],
              "name" => entry["Name"],
              "created" => entry["Created"],
              "severity" => entry["Severity"],
              "message" => entry["Message"],
              "message_id" => entry["MessageId"],
              "sensor_type" => entry["SensorType"],
              "sensor_number" => entry["SensorNumber"]
            }
          end || []
          
          return entries.sort_by { |e| e["created"] || "" }.reverse
        rescue JSON::ParserError
          raise Error, "Failed to parse SEL log response: #{response.body}"
        end
      else
        raise Error, "Failed to get SEL log. Status code: #{response.status}"
      end
    end

    def clear_sel_log
      puts "Clearing System Event Log...".yellow
      
      response = authenticated_request(
        :post,
        "/redfish/v1/Managers/1/LogServices/SEL/Actions/LogService.ClearLog",
        body: {}.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "SEL cleared successfully.".green
        return true
      else
        raise Error, "Failed to clear SEL: #{response.status} - #{response.body}"
      end
    end

    def sel_summary(limit: 10)
      puts "\n=== System Event Log ===".green
      
      entries = sel_log
      
      if entries.empty?
        puts "No log entries found.".yellow
        return entries
      end
      
      puts "Total entries: #{entries.length}".cyan
      puts "\nMost recent #{limit} entries:".cyan
      
      entries.first(limit).each do |entry|
        severity_color = case entry["severity"]
                        when "Critical" then :red
                        when "Warning" then :yellow
                        when "OK" then :green
                        else :white
                        end
        
        puts "\n[#{entry['created']}] #{entry['severity']}".send(severity_color)
        puts "  #{entry['message']}"
        puts "  ID: #{entry['id']} | MessageID: #{entry['message_id']}" if entry['message_id']
      end
      
      entries
    end

    def accounts
      response = authenticated_request(:get, "/redfish/v1/AccountService/Accounts?$expand=*($levels=1)")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          accounts = data["Members"]&.map do |account|
            {
              "id" => account["Id"],
              "username" => account["UserName"],
              "enabled" => account["Enabled"],
              "locked" => account["Locked"],
              "role_id" => account["RoleId"],
              "description" => account["Description"]
            }
          end || []
          
          return accounts
        rescue JSON::ParserError
          raise Error, "Failed to parse accounts response: #{response.body}"
        end
      else
        raise Error, "Failed to get accounts. Status code: #{response.status}"
      end
    end

    def create_account(username:, password:, role: "Administrator")
      puts "Creating account #{username} with role #{role}...".yellow
      
      body = {
        "UserName" => username,
        "Password" => password,
        "RoleId" => role,
        "Enabled" => true
      }
      
      response = authenticated_request(
        :post,
        "/redfish/v1/AccountService/Accounts",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Account created successfully.".green
        return true
      else
        raise Error, "Failed to create account: #{response.status} - #{response.body}"
      end
    end

    def delete_account(username)
      accounts_list = accounts
      account = accounts_list.find { |a| a["username"] == username }
      
      unless account
        raise Error, "Account #{username} not found"
      end
      
      puts "Deleting account #{username}...".yellow
      
      response = authenticated_request(
        :delete,
        "/redfish/v1/AccountService/Accounts/#{account["id"]}"
      )
      
      if response.status.between?(200, 299)
        puts "Account deleted successfully.".green
        return true
      else
        raise Error, "Failed to delete account: #{response.status} - #{response.body}"
      end
    end

    def update_account_password(username:, new_password:)
      accounts_list = accounts
      account = accounts_list.find { |a| a["username"] == username }
      
      unless account
        raise Error, "Account #{username} not found"
      end
      
      puts "Updating password for account #{username}...".yellow
      
      body = {
        "Password" => new_password
      }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/AccountService/Accounts/#{account["id"]}",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Password updated successfully.".green
        return true
      else
        raise Error, "Failed to update password: #{response.status} - #{response.body}"
      end
    end

    def sessions
      response = authenticated_request(:get, "/redfish/v1/SessionService/Sessions?$expand=*($levels=1)")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          sessions = data["Members"]&.map do |session|
            {
              "id" => session["Id"],
              "username" => session["UserName"],
              "created_time" => session["CreatedTime"],
              "client_ip" => session.dig("Oem", "Supermicro", "ClientIP") || session["ClientOriginIPAddress"]
            }
          end || []
          
          return sessions
        rescue JSON::ParserError
          raise Error, "Failed to parse sessions response: #{response.body}"
        end
      else
        raise Error, "Failed to get sessions. Status code: #{response.status}"
      end
    end

    def service_info
      response = authenticated_request(:get, "/redfish/v1")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          {
            "service_version" => data["RedfishVersion"],
            "uuid" => data["UUID"],
            "product" => data["Product"],
            "vendor" => data["Vendor"],
            "oem" => data["Oem"]
          }
        rescue JSON::ParserError
          raise Error, "Failed to parse service info response: #{response.body}"
        end
      else
        raise Error, "Failed to get service info. Status code: #{response.status}"
      end
    end
  end
end