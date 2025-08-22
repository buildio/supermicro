# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Power
    def power_status
      response = authenticated_request(:get, "/redfish/v1/Systems/1?$select=PowerState")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          power_state = data["PowerState"]
          return power_state
        rescue JSON::ParserError
          raise Error, "Failed to parse power status response: #{response.body}"
        end
      else
        raise Error, "Failed to get power status. Status code: #{response.status}"
      end
    end

    def power_on
      current_state = power_status
      
      if current_state == "On"
        puts "System is already powered on.".yellow
        return true
      end
      
      puts "Powering on system...".yellow
      
      response = authenticated_request(
        :post,
        "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset",
        body: { "ResetType": "On" }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Power on command sent successfully.".green
        return true
      else
        raise Error, "Failed to power on system: #{response.status} - #{response.body}"
      end
    end

    def power_off(force: false)
      current_state = power_status
      
      if current_state == "Off"
        puts "System is already powered off.".yellow
        return true
      end
      
      reset_type = force ? "ForceOff" : "GracefulShutdown"
      puts "#{force ? 'Force powering' : 'Gracefully shutting'} off system...".yellow
      
      response = authenticated_request(
        :post,
        "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset",
        body: { "ResetType": reset_type }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Power off command sent successfully.".green
        return true
      elsif !force
        puts "Graceful shutdown failed, trying force off...".yellow
        
        response = authenticated_request(
          :post,
          "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset",
          body: { "ResetType": "ForceOff" }.to_json,
          headers: { 'Content-Type': 'application/json' }
        )
        
        if response.status.between?(200, 299)
          puts "Force power off command sent successfully.".green
          return true
        else
          raise Error, "Failed to power off system: #{response.status} - #{response.body}"
        end
      else
        raise Error, "Failed to force power off system: #{response.status} - #{response.body}"
      end
    end

    def power_restart(force: false)
      reset_type = force ? "ForceRestart" : "GracefulRestart"
      puts "#{force ? 'Force restarting' : 'Gracefully restarting'} system...".yellow
      
      response = authenticated_request(
        :post,
        "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset",
        body: { "ResetType": reset_type }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Restart command sent successfully.".green
        return true
      elsif !force
        puts "Graceful restart failed, trying force restart...".yellow
        
        response = authenticated_request(
          :post,
          "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset",
          body: { "ResetType": "ForceRestart" }.to_json,
          headers: { 'Content-Type': 'application/json' }
        )
        
        if response.status.between?(200, 299)
          puts "Force restart command sent successfully.".green
          return true
        else
          raise Error, "Failed to restart system: #{response.status} - #{response.body}"
        end
      else
        raise Error, "Failed to force restart system: #{response.status} - #{response.body}"
      end
    end

    def power_cycle
      puts "Power cycling system...".yellow
      
      response = authenticated_request(
        :post,
        "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset",
        body: { "ResetType": "PowerCycle" }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Power cycle command sent successfully.".green
        return true
      else
        raise Error, "Failed to power cycle system: #{response.status} - #{response.body}"
      end
    end

    def reset_type_allowed
      response = authenticated_request(:get, "/redfish/v1/Systems/1")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          allowed_values = data.dig("Actions", "#ComputerSystem.Reset", "ResetType@Redfish.AllowableValues")
          
          if allowed_values
            puts "Allowed reset types:".green
            allowed_values.each { |type| puts "  - #{type}" }
            return allowed_values
          else
            puts "Could not determine allowed reset types".yellow
            return []
          end
        rescue JSON::ParserError
          raise Error, "Failed to parse system response: #{response.body}"
        end
      else
        raise Error, "Failed to get system info. Status code: #{response.status}"
      end
    end
  end
end